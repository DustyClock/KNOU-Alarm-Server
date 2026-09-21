# 24시간 실행 설정

이 폴더를 GitHub 공개 저장소에 올리면 GitHub Actions가 15분마다 방송대 최신 공지 40개를 확인합니다.

## 저장소에 등록할 비밀값

GitHub 저장소에서 **Settings → Secrets and variables → Actions → New repository secret**으로 이동해 아래 두 값을 등록합니다.

- `TELEGRAM_BOT_TOKEN`: BotFather에서 받은 봇 토큰
- `TELEGRAM_CHAT_ID`: 현재 사용 중인 텔레그램 채팅 ID

비밀값은 워크플로 실행 화면이나 공개된 코드에 표시되지 않습니다. `config.json`은 `.gitignore`에 포함되어 업로드되지 않습니다.

## 첫 실행 시험

1. 저장소의 **Actions** 탭을 엽니다.
2. 왼쪽에서 **KNOU notice notifier**를 선택합니다.
3. **Run workflow**를 누릅니다.
4. **Send a Telegram test message**를 선택하고 실행합니다.
5. 실행 결과가 초록색 체크로 끝나고 텔레그램 테스트 메시지가 오는지 확인합니다.

시험이 성공하면 PC에 등록된 `KNOU Notice Notifier` 예약 작업을 제거해 중복 실행을 막습니다. 프로그램 폴더의 `uninstall-task.ps1`로 제거할 수 있습니다.

## 알아둘 점

- 예약 실행은 15분 간격으로 요청되지만 GitHub가 혼잡하면 몇 분 늦게 시작될 수 있습니다.
- 저장소를 삭제하거나 Actions를 비활성화하면 알림도 중단됩니다.
- 봇 토큰을 코드, 이슈 또는 실행 로그에 직접 입력하지 마세요.
