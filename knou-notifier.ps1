[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Initialize,
    [string]$ConfigPath = '',
    [string]$StatePath = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $PSScriptRoot 'config.json' }
if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = Join-Path $PSScriptRoot 'state.json' }
$BaseUrl = 'https://www.knou.ac.kr'
$ListUrl = "$BaseUrl/bbs/knou/51/artclList.do"
$UserAgent = 'KNOU-Notice-Notifier/1.0 (+personal notice checker)'

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
    param([Parameter(Mandatory)][string]$Html)
    $rows = [regex]::Matches($Html, '<tr\b[^>]*>([\s\S]*?)</tr>', 'IgnoreCase')
    foreach ($row in $rows) {
        $body = $row.Groups[1].Value
        $link = [regex]::Match($body, 'href="(?<url>/bbs/knou/51/(?<id>\d+)/artclView\.do[^"]*)"', 'IgnoreCase')
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
            id       = $link.Groups['id'].Value
            category = $category
            title    = $title
            writer   = (ConvertFrom-HtmlText $writerMatch.Groups['writer'].Value)
            date     = (ConvertFrom-HtmlText $dateMatch.Groups['date'].Value).Replace('.', '-')
            url      = $BaseUrl + $link.Groups['url'].Value.Split('?')[0]
        }
    }
}

function Get-LatestNotices {
    param([int]$Count = 40)
    $found = [ordered]@{}
    for ($page = 1; $page -le 10 -and $found.Count -lt $Count; $page++) {
        $html = Invoke-KnouRequest "${ListUrl}?page=$page"
        foreach ($notice in (Get-NoticeRows $html)) {
            if (-not $found.Contains($notice.id)) { $found[$notice.id] = $notice }
            if ($found.Count -ge $Count) { break }
        }
    }
    if ($found.Count -lt $Count) { throw "최신 공지를 $Count개 수집하지 못했습니다. 수집된 개수: $($found.Count)" }
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
        $cut = $bodyText.Substring(0, $MaxLength)
        $sentence = [regex]::Match($cut, '^(.{80,}[.!?。]|.{80,}다\.)\s')
        if ($sentence.Success) { return $sentence.Groups[1].Value }
        return $cut.TrimEnd() + '…'
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

    $notices = @(Get-LatestNotices -Count 40)
    $currentIds = @($notices | ForEach-Object id)
    if ($Initialize -or -not (Test-Path -LiteralPath $StatePath)) {
        @{ seenIds = $currentIds; initializedAt = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding utf8
        Write-Log "기준점 저장 완료: 최신 공지 $($currentIds.Count)개 (알림 없음)"
        exit 0
    }

    $state = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
    $seen = @{}; foreach ($id in @($state.seenIds)) { $seen[[string]$id] = $true }
    $newNotices = @($notices | Where-Object { -not $seen.ContainsKey([string]$_.id) })

    foreach ($notice in @($newNotices | Select-Object -Last 40 | Sort-Object id)) {
        $summary = Get-NoticeSummary -Notice $notice
        $message = @"
<b>방송대 새 공지</b>
분류: $(Escape-TelegramHtml $notice.category)
제목: $(Escape-TelegramHtml $notice.title)
작성: $(Escape-TelegramHtml $notice.writer) · $(Escape-TelegramHtml $notice.date)

$(Escape-TelegramHtml $summary)

<a href="$($notice.url)">공지 바로가기</a>
"@
        if ($DryRun) { Write-Host "`n$message`n" } else { Send-TelegramMessage -Config $config -Message $message }
    }

    if ($newNotices.Count -gt 0) {
        @{ seenIds = $currentIds; checkedAt = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding utf8
    }
    Write-Log "확인 완료: 최신 40개, 새 공지 $($newNotices.Count)개"
} catch {
    Write-Log "오류: $($_.Exception.Message)"
    exit 1
}
