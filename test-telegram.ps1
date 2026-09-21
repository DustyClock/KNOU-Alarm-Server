$ErrorActionPreference = 'Stop'
$configPath = Join-Path $PSScriptRoot 'config.json'
if (-not (Test-Path $configPath)) { throw '먼저 setup.ps1을 실행해 주세요.' }
$config = Get-Content -Raw $configPath | ConvertFrom-Json
$uri = "https://api.telegram.org/bot$($config.telegramBotToken)/sendMessage"
$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$payload = @{ chat_id = $config.telegramChatId; text = "방송대 공지 알림 테스트입니다. ($now)" }
$result = Invoke-RestMethod -Method Post -Uri $uri -Body $payload -TimeoutSec 45
if (-not $result.ok) { throw '텔레그램 서버가 전송을 승인하지 않았습니다.' }
Write-Host "테스트 알림을 보냈습니다. 메시지 번호: $($result.result.message_id)"
Write-Host "받는 대화: $($result.result.chat.first_name)"
