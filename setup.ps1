[CmdletBinding()]
param([int]$IntervalMinutes = 15)

$ErrorActionPreference = 'Stop'
$appDir = $PSScriptRoot
$runner = Join-Path $appDir 'knou-notifier.ps1'
$configPath = Join-Path $appDir 'config.json'
$taskName = 'KNOU Notice Notifier'

Write-Host '텔레그램에서 @BotFather로 봇을 만들고 받은 토큰을 입력하세요.'
$tokenSecure = Read-Host '봇 토큰' -AsSecureString
$tokenPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenSecure)
try { $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPtr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPtr) }
$chatId = Read-Host '채팅 ID'
if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($chatId)) { throw '봇 토큰과 채팅 ID는 필수입니다.' }

@{ telegramBotToken = $token.Trim(); telegramChatId = $chatId.Trim() } |
    ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Initialize
if ($LASTEXITCODE -ne 0) { throw '최초 공지 확인에 실패했습니다. notifier.log를 확인해 주세요.' }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runner`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description '한국방송통신대학교 최신 공지 40개를 확인하고 새 공지를 텔레그램으로 알립니다.' -Force | Out-Null

Write-Host "설정 완료: $IntervalMinutes분마다 최신 공지 40개를 확인합니다."
Write-Host '최초 설정 시점의 기존 공지는 보내지 않으며, 이후 올라오는 새 공지만 알립니다.'
