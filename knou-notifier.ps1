[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Initialize,
    [switch]$TestLatest,
    [string]$ConfigPath = '',
    [string]$StatePath = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $PSScriptRoot 'config.json' }
if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = Join-Path $PSScriptRoot 'state.json' }
$UserAgent = 'KNOU-Notice-Notifier/2.0 (+personal notice checker)'
$Sources = @(
    [pscustomobject]@{ key = 'school'; name = '학교 전체 공지'; baseUrl = 'https://www.knou.ac.kr'; listPath = '/bbs/knou/51/artclList.do'; boardPath = '/bbs/knou/51' },
    [pscustomobject]@{ key = 'socialwelfare'; name = '사회복지학과 공지'; baseUrl = 'https://socialwelfare.knou.ac.kr'; listPath = '/bbs/socialwelfare/2111/artclList.do'; boardPath = '/bbs/socialwelfare/2111' },
    [pscustomobject]@{ key = 'seoul'; name = '서울지역대학 공지'; baseUrl = 'https://wseoul.knou.ac.kr'; listPath = '/bbs/regional/2062/artclList.do?bbsClSeq=2141'; boardPath = '/bbs/regional/2062' },
    [pscustomobject]@{ key = 'admission'; name = '입학공지'; baseUrl = 'https://admission.knou.ac.kr'; listPath = '/bbs/admission/29/artclList.do'; boardPath = '/bbs/admission/29' }
)

function ConvertFrom-HtmlText {
    param([AllowEmptyString()][string]$Html)
    if ([string]::IsNullOrWhiteSpace($Html)) { return '' }
    $text = [regex]::Replace($Html, '<script\b[^>]*>[\s\S]*?</script>', ' ', 'IgnoreCase')
    $text = [regex]::Replace($text, '<style\b[^>]*>[\s\S]*?</style>', ' ', 'IgnoreCase')
    $text = [regex]::Replace($text, '<br\s*/?>|</p>|</div>|</li>|</tr>', "`n", 'IgnoreCase')
    $text = [regex]::Replace($text, '<[^>]+>', ' ')
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    $lines = foreach ($line in ($text -split "`r?`n")) {
        $clean = [regex]::Replace($line, '\s+', ' ').Trim()
        if ($clean) { $clean }
    }
    return ($lines -join "`n").Trim()
}

function Invoke-KnouRequest {
    param([Parameter(Mandatory)][string]$Uri)
    $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -Headers @{ 'User-Agent' = $UserAgent } -TimeoutSec 45
    return $response.Content
}

function Get-NoticeRows {
    param([Parameter(Mandatory)][string]$Html, [Parameter(Mandatory)]$Source)
    $rows = [regex]::Matches($Html, '<tr\b[^>]*>([\s\S]*?)</tr>', 'IgnoreCase')
    $escapedBoardPath = [regex]::Escape($Source.boardPath)
    foreach ($row in $rows) {
        $body = $row.Groups[1].Value
        $link = [regex]::Match($body, 'href="(?<url>' + $escapedBoardPath + '/(?<id>\d+)/artclView\.do[^\"]*)"', 'IgnoreCase')
        if (-not $link.Success) { continue }
        $titleMatch = [regex]::Match($body, '<td\b[^>]*class="[^"]*td-subject[^"]*"[^>]*>(?<title>[\s\S]*?)</td>', 'IgnoreCase')
        $dateMatch = [regex]::Match($body, '<td\b[^>]*class="[^"]*td-date[^"]*"[^>]*>(?<date>[\s\S]*?)</td>', 'IgnoreCase')
        $writerMatch = [regex]::Match($body, '<td\b[^>]*class="[^"]*td-write[^"]*"[^>]*>(?<writer>[\s\S]*?)</td>', 'IgnoreCase')
        $title = ConvertFrom-HtmlText $titleMatch.Groups['title'].Value
        $title = ($title -replace '\s*새글\s*$', '').Trim()
        $category = ''
        if ($title -match '^\[(?<category>[^\]]+)\]\s*(?<rest>.+)$') {
            $category = $Matches.category.Trim()
            $title = $Matches.rest.Trim()
        }
        [pscustomobject]@{
            id = $link.Groups['id'].Value
            sourceKey = $Source.key
            sourceName = $Source.name
            category = $category
            title = $title
            writer = (ConvertFrom-HtmlText $writerMatch.Groups['writer'].Value)
            date = (ConvertFrom-HtmlText $dateMatch.Groups['date'].Value).Replace('.', '-')
            url = $Source.baseUrl + $link.Groups['url'].Value.Split('?')[0]
        }
    }
}

function Get-LatestNotices {
    param([Parameter(Mandatory)]$Source, [int]$Count = 40)
    $found = [ordered]@{}
    for ($page = 1; $page -le 10 -and $found.Count -lt $Count; $page++) {
        $separator = if ($Source.listPath.Contains('?')) { '&' } else { '?' }
        $html = Invoke-KnouRequest ($Source.baseUrl + $Source.listPath + $separator + "page=$page")
        foreach ($notice in (Get-NoticeRows -Html $html -Source $Source)) {
            if (-not $found.Contains($notice.id)) { $found[$notice.id] = $notice }
            if ($found.Count -ge $Count) { break }
        }
    }
    if ($found.Count -eq 0) { throw "$($Source.name)에서 공지를 수집하지 못했습니다." }
    return @($found.Values)
}

function Get-NoticeSummary {
    param([Parameter(Mandatory)]$Notice, [int]$MaxLength = 220)
    try {
        $html = Invoke-KnouRequest $Notice.url
        $blocks = [regex]::Matches($html, '<div\b[^>]*class="[^"]*view-con[^"]*"[^>]*>(?<body>[\s\S]*?)</div>\s*(?:</div>\s*)?(?:<div\b[^>]*class="[^"]*board-button|<form)', 'IgnoreCase')
        if ($blocks.Count -eq 0) {
            $start = [regex]::Match($html, '<div\b[^>]*class="[^"]*view-con[^"]*"[^>]*>', 'IgnoreCase')
            if ($start.Success) { $bodyText = ConvertFrom-HtmlText $html.Substring($start.Index + $start.Length) }
        } else {
            $bodyText = ConvertFrom-HtmlText $blocks[$blocks.Count - 1].Groups['body'].Value
        }
        if ([string]::IsNullOrWhiteSpace($bodyText)) { return '본문 요약을 가져오지 못했습니다.' }
        $bodyText = [regex]::Replace($bodyText, '\s+', ' ').Trim()
        if ($bodyText.Length -le $MaxLength) { return $bodyText }
        return $bodyText.Substring(0, $MaxLength).TrimEnd() + '…'
    } catch {
        return '본문 요약을 가져오지 못했습니다.'
    }
}

function Escape-TelegramHtml {
    param([AllowEmptyString()][string]$Text)
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Send-TelegramMessage {
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$Message)
    $uri = "https://api.telegram.org/bot$($Config.telegramBotToken)/sendMessage"
    $payload = @{ chat_id = $Config.telegramChatId; text = $Message; parse_mode = 'HTML'; disable_web_page_preview = $true }
    Invoke-RestMethod -Method Post -Uri $uri -Body $payload -TimeoutSec 45 | Out-Null
}

function New-NoticeMessage {
    param([Parameter(Mandatory)]$Notice, [switch]$IsTest)
    $summary = Get-NoticeSummary -Notice $Notice
    $heading = if ($IsTest) { '방송대 공지 알림 테스트' } else { '방송대 새 공지' }
    $categoryLine = if ([string]::IsNullOrWhiteSpace($Notice.category)) { '' } else { "`n분류: $(Escape-TelegramHtml $Notice.category)" }
    return @"
<b>$heading</b>
게시판: $(Escape-TelegramHtml $Notice.sourceName)$categoryLine
제목: $(Escape-TelegramHtml $Notice.title)
작성: $(Escape-TelegramHtml $Notice.writer) · $(Escape-TelegramHtml $Notice.date)

$(Escape-TelegramHtml $summary)

<a href="$($Notice.url)">공지 바로가기</a>
"@
}

function Write-Log {
    param([string]$Message)
    $logPath = Join-Path $PSScriptRoot 'notifier.log'
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
    if ($DryRun) { Write-Host $line }
}

try {
    $config = $null
    if (Test-Path -LiteralPath $ConfigPath) { $config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json }
    if (-not $DryRun -and (-not $config -or [string]::IsNullOrWhiteSpace($config.telegramBotToken) -or [string]::IsNullOrWhiteSpace([string]$config.telegramChatId))) {
        throw 'config.json에 텔레그램 봇 토큰과 채팅 ID를 설정해 주세요.'
    }

    $noticesBySource = @{}
    foreach ($source in $Sources) { $noticesBySource[$source.key] = @(Get-LatestNotices -Source $source -Count 40) }

    if ($TestLatest) {
        foreach ($source in $Sources) {
            $latest = @($noticesBySource[$source.key] | Sort-Object { [long]$_.id } -Descending)[0]
            $message = New-NoticeMessage -Notice $latest -IsTest
            if ($DryRun) { Write-Host "`n$message`n" } else { Send-TelegramMessage -Config $config -Message $message }
        }
        Write-Log "게시판별 최신 공지 테스트 완료: $($Sources.Count)개"
        exit 0
    }

    $stateSources = @{}
    if (Test-Path -LiteralPath $StatePath) {
        $oldState = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
        if ($oldState.sources) {
            foreach ($property in $oldState.sources.PSObject.Properties) { $stateSources[$property.Name] = @($property.Value) }
        } elseif ($oldState.seenIds) {
            $stateSources['school'] = @($oldState.seenIds)
        }
    }

    $newBySource = @{}
    foreach ($source in $Sources) {
        $current = @($noticesBySource[$source.key])
        if ($Initialize -or -not $stateSources.ContainsKey($source.key)) {
            $stateSources[$source.key] = @($current | ForEach-Object id)
            $newBySource[$source.key] = @()
            continue
        }
        $seen = @{}; foreach ($id in @($stateSources[$source.key])) { $seen[[string]$id] = $true }
        $newBySource[$source.key] = @($current | Where-Object { -not $seen.ContainsKey([string]$_.id) })
        $stateSources[$source.key] = @($current | ForEach-Object id)
    }

    foreach ($source in $Sources) {
        foreach ($notice in @($newBySource[$source.key] | Sort-Object { [long]$_.id })) {
            $message = New-NoticeMessage -Notice $notice
            if ($DryRun) { Write-Host "`n$message`n" } else { Send-TelegramMessage -Config $config -Message $message }
        }
    }

    $stateObject = [ordered]@{ sources = [ordered]@{}; checkedAt = (Get-Date).ToString('o') }
    foreach ($source in $Sources) { $stateObject.sources[$source.key] = @($stateSources[$source.key]) }
    $stateObject | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StatePath -Encoding utf8
    $newCount = 0; foreach ($source in $Sources) { $newCount += @($newBySource[$source.key]).Count }
    Write-Log "확인 완료: 게시판 $($Sources.Count)개, 새 공지 $newCount개"
} catch {
    Write-Log "오류: $($_.Exception.Message)"
    exit 1
}
