$taskName = 'KNOU Notice Notifier'
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host '자동 확인 작업을 제거했습니다. 프로그램 파일과 설정은 그대로 남아 있습니다.'
} else {
    Write-Host '등록된 자동 확인 작업이 없습니다.'
}
