# KeyboardWarrior

모바일 가로와 PC에서 함께 플레이하는 서버당 최대 12명의 단일 Lobby Place 타자 대결 프로젝트. 원본 월드는 KeyboardWarrior.rbxl, 동기화할 코드는 default.project.json이 관리한다. 프로젝트 저장소는 [kimdaegyu/KeyboardWarrior](https://github.com/kimdaegyu/KeyboardWarrior)다.

- [정식 기획서](docs/GameDesign.ko.md) · [데이터 플로우·화면 검증·Cursor 첫 작업](docs/Harness.ko.md) · [에이전트 규칙](AGENTS.md)
- src/ReplicatedStorage/Shared — Localization, TableData, 아이콘·UI 아틀라스 조회기, IngameConstants
- src/ServerScriptService/Core — PlayerStore, 게임 전용 DataConfig, DocumentService
- src/StarterPlayerScripts — 공통 GUI의 SafeRoot와 반응형 레이아웃 시작점
- tables, assets, tools — 편집용 Excel, 재사용 이미지, 직렬화·아틀라스·검증 도구
- FromGPT — 기획 초안과 8개 화면 시안

## 로컬 실행

Windows PowerShell에서 프로젝트 루트로 이동한다. 기준 환경은 Python 3.12 및 Rojo 7.7.0이다.

```powershell
python -m pip install -r requirements.txt
python tools/verify.py
rojo serve default.project.json
```

Studio에서 **KeyboardWarrior.rbxl**을 열고 Rojo 플러그인으로 터미널에 표시된 주소에 연결한다. 첫 동기화 변경 목록에서 Shared, Core, KeyboardWarrior 클라이언트 폴더, CoreStrings 및 StarterGui 방향을 확인한다. Workspace는 Studio가 관리한다. Play 시 PlayerGui에 KeyboardWarriorUI/SafeRoot가 한 개 생긴다. 패널과 번역 확인은 Play 전 Workspace에 boolean 속성 PreviewCoreUI=true를 넣어 실행한다. 정식 로비 메뉴는 후속 구현이다.

소스만 묶은 검증용 Place를 별도로 만들 수 있다. 이 파일은 원본 맵을 포함하지 않는다.

```powershell
New-Item -ItemType Directory -Force build | Out-Null
rojo build default.project.json -o build/Lobby-Core.rbxl
```

프로필 저장 어댑터는 제공되며 현재 시작 스크립트가 플레이어 데이터를 열거나 쓰지 않는다. Studio 실플레이, 실제 저장 왕복, 이미지 로딩 권한과 게시 설정의 서버 최대 인원 12명은 Studio 인수 항목이다.

## Cursor 및 Studio 검증

Cursor의 Run Task에서 KeyboardWarrior: Verify, Sync Excel, Build icon atlas, Serve Lobby를 실행할 수 있다. Studio Play의 서버 Command Bar에서 아래 명령으로 실제 Luau 테이블 파서, 참조 키, 아이콘 조회, 경기 상수와 프로필 기본값 검사를 수행한다. 이 검사는 저장소 쓰기를 수행하지 않는다.

```luau
require(game.ServerScriptService.Core.StudioSmoke)()
```
