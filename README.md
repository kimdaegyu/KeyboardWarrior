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

접속 시 PlayerStore로 프로필을 연다. 열기에 실패하면 기본값으로 덮어쓰지 않으며 Studio와 live 저장 범위는 분리되어 있다. Studio 실플레이, 실제 저장 왕복, 이미지 로딩 권한과 게시 설정의 서버 최대 인원 12명은 Studio 인수 항목이다.

## Cursor 및 Studio 검증

Cursor의 Run Task에서 KeyboardWarrior: Verify, Sync Excel, Build icon atlas, Serve Lobby를 실행할 수 있다. Studio Play의 서버 Command Bar에서 아래 명령으로 실제 Luau 테이블 파서, 참조 키, 아이콘 조회, 경기 상수와 프로필 기본값 검사를 수행한다. 이 검사는 저장소 쓰기를 수행하지 않는다.

```luau
require(game.ServerScriptService.Core.StudioSmoke)()
```

### 정식 UI 리소스

`FromGPT/*.png`는 모바일 가로 화면 시안 8장이다. 금액·점수는 화면 예시이며 실제 값은 게임 데이터를 따른다.

| 용도 | 소스 | 빌드 | Roblox 이미지 ID 등록 |
| --- | --- | --- | --- |
| 숫자 ID 아이템 아이콘 | `assets/item-icons/source/<Id>.png` | `python tools/build_item_icons.py` | `ItemIconPages.luau`의 페이지 1 |
| 이름 기반 UI 이미지 | `assets/ui-images/source/<이름>.png` | `python tools/build_ui_atlas.py` | `UIImageAssetIds.luau`의 `KeyboardWarriorUI` |
| 최초 접속 로딩 배경·투명 타이틀 | 업로드한 배경 PNG, 투명 타이틀 PNG | 아틀라스에 넣지 않음 | `LoadingArt.luau`의 `BackgroundImage`, `TitleImage` |

두 등록 모듈은 `src/ReplicatedStorage/Shared`에 있다. 각 atlas 폴더의 PNG를 Roblox에 업로드하고 이미지 ID를 등록하면 해당 페이지를 조회할 수 있다. UI에는 `UIImageUtil.apply(image, "Shop")`처럼 대소문자를 구분한 파일명을 확장자 없이 전달한다. 발판 미리보기는 ShopDataSheet의 Id를 사용한다. 패널·키캡의 9-slice 좌표는 자동 생성된다. 흰 패널과 노란 버튼의 글자색은 남색(#172945), 파란 선택 버튼의 글자색은 흰색을 사용한다.
