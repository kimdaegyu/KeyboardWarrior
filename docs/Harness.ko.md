# 구현 계약과 검증 하네스

## 작업 단위

GPT Work의 기획 변경에는 목적, 해당 화면과 상태 전이, 데이터 원본, 서버 책임, 수용 조건을 기록한다. Cursor는 작업 하나를 끝낼 때 수정 파일, 재생성한 결과물, 통과한 명령, Studio에서 직접 관찰한 결과, 남은 결정을 구분해 보고한다. 새 모듈은 호출하는 기능과 함께 도입한다.

| 단계 | Cursor가 구현할 범위 | 인수 조건 |
|---|---|---|
| M1 월드·사이클 | MatchService, ArenaService, HUD 상태 읽기 | 두 클라이언트가 같은 종료 시각을 표시. 원 안/밖 참가 구분. 1~12명 참가와 발판 12개 중복 없는 배정. 120/30/30 전환 |
| M2 출제·입력 | QuestionService, 입력 버퍼, PC/터치 입력 | 정답 시 사용자별 다음 문제. Enter와 자동 완료가 겹쳐도 한 번 처리. 모바일 모든 활성 영문 문제 입력 가능 |
| M3 점수·순위 | 서버 점수와 라이브 순위 | 31초·30초·0초 경계, 동점, 지연·중복 입력 확인. 각 행 언어와 본인 순위 유지 |
| M4 결산·성장 | 결과, 프로필 세션, 보상 원장 | 재전송·이탈·서버 종료에도 지급 중복 없음. 열기 실패 시 임시 기본값으로 덮어쓰기 방지 |
| M5 로비 기능 | 연습, 튜토리얼, 설정, 전체 랭크 | 독립 GUI의 HUD 가시성, 설정 복원, 빈 랭크, 첫 접속과 재방문 확인 |
| M6 상점 | 골드 구매, 소유권, 미리보기, 장착, Robux 연계 | 취소 시 원상 복구. 소유·잔액과 부위별 장착 일관성. 재접속·재처리 확인 |
| M7 출시 검수 | PC 언어 확대, 지표, 실제 다인·기기 점검 | IME 완성 전 오판정 없음. 순위·결과 언어 표시. 콘텐츠·상품·이미지 ID 실환경 확인 |

### 첫 Cursor 요청

AGENTS.md, docs/GameDesign.ko.md, docs/Harness.ko.md를 기준으로 단일 Lobby Place의 M1(경기장·참가·타이머·로비 HUD)을 구현해 주세요.

1. Workspace.Arena 아래 LobbySpawn, JoinZone, ArenaCenter의 배치 여부를 확인하고 기존 오브젝트를 재사용하세요. Studio 수작업이 필요하면 정확한 경로와 속성을 알려 주세요. 지름 100 studs는 경기장 외곽 기준이며 참가 원의 크기는 배치된 JoinZone에서 읽으세요.
2. IngameConstants.Match와 Arena를 사용하세요. ArenaCenter 주위에 지름 12 studs인 원형 발판 12개를 30° 간격으로 생성하세요. 인접 발판 가장자리 간 직선 간격은 4 studs이며, 중심 배치 반지름은 상수 모듈의 계산값(약 30.91 studs)을 쓰세요. 다음 경기에도 같은 발판을 재사용하세요.
3. 서버가 시작 순간 참가 원 안에 있는 1~12명을 확정하고, 서로 다른 발판에 무작위 배정해 중앙을 보게 하세요. 0명은 참가·보상 처리 없이 기존 파일럿 시계를 진행하세요. 두 클라이언트에 같은 서버 종료 시각을 사용하고 대결 120초, 결산 30초, 휴식 30초를 적용하세요. 마지막 30초 점수 2배 규칙은 M3에 연결하세요.
4. SafeRoot의 로비 HUD에 대기 인원/정원(예: 3/12), 참가 대기 상태, 남은 시간을 표시하세요. 분모는 Match.MaxParticipants에서 읽고 문구는 CoreStrings.csv에서 관리하세요. 12행 결과표는 M4 범위로 두세요.
5. 1인 시작, 2명 중 원 안의 1명만 이동, 12명 전원 고유 배정, 13개 모의 후보에서 최대 12명 선발, 다음 경기에도 발판 12개 유지를 검증하세요. python tools/verify.py 결과, Studio에서 직접 확인한 항목, 게시된 Lobby Place의 서버 최대 인원 12 설정 여부를 나눠 보고해 주세요.

## 데이터 원본과 변환

| 원본 | 소비 경로 | 편집 규칙 |
|---|---|---|
| tables/QuestionDataSheet.xlsx | TableData.rows("QuestionDataSheet") → 출제·정답 판정 | Id는 의미 단위 고정 키. Kind, GradeId, Score, Enabled 및 언어 열. 번역 언어의 동일 행을 뜻으로 조회 |
| GradeDataSheet.xlsx | GradeId → ColorHex → 문제 프레임 | #RRGGBB. 색상과 숫자 점수를 함께 표시 |
| RewardDataSheet.xlsx, LevelDataSheet.xlsx | 서버 보상·누적 경험치 → 레벨 조회 | 정답 종류와 Complete 분리. TotalExp는 1레벨 0부터 단조 증가 |
| ShopDataSheet.xlsx | 서버 구매·장착 / 클라이언트 카탈로그 | Body, Rim, Effect. 가격과 플랫폼 ID 분리. 샘플 상품 모두 Enabled=0 |
| ItemDataSheet.xlsx | Id → PNG → 페이지·슬롯 → ItemIconUtil | 현재 행은 재사용 UI 아이콘 목록. 상점 판매 SKU와 독립 |
| IngameConstants.luau | 경기 서비스·공통 레이아웃 | 시간·정원·배율·화면 전환 기준 등 코드가 공유하는 시스템 수치 |
| CoreStrings.csv | LocalizationService.CoreStrings → Shared.Localization.bind | UI 키는 안정적으로 유지. 문제 텍스트는 문제 Excel에서 관리 |
| DataConfig.luau | PlayerStore → DocumentService | 현재 v1 필드는 schemaVersion, gold, exp, bestScore. 설정·소유·장착 추가 시 이전 프로필 fixture와 마이그레이션 포함 |

Excel은 첫 시트의 첫 행에 고유한 열명을 사용한다. 중복 키, 깨진 참조, 출력과 원본의 불일치는 작업 실패다. 숫자·플래그는 TXT에서 문자열이므로 소비 모듈이 초기화 때 한 번 파싱하고 ID 인덱스를 만든다. Enabled는 "1"을 명시 비교한다. 문항 점수·골드·경험치·레벨·상품 행은 **개발 샘플**이다. 활성 영어 콘텐츠는 기본 키보드로 입력할 수 있는 문자와 공백만 허용한다.

```powershell
python tools/sync_tables.py
python tools/build_item_icons.py
python tools/verify.py
```

첫 명령은 tables → src/ReplicatedStorage/Shared/Table로 직렬화한다. 두 번째는 아이콘 원본과 ItemDataSheet로 assets/item-icons/atlas와 ItemIconSlots.luau를 갱신한다. 데이터만 바꾼 경우 첫 번째와 세 번째로 충분하다. verify는 임시 경로에서 다시 생성해 누락·오래된 테이블, 아틀라스 페이지 픽셀과 슬롯을 비교하고 Rojo 빌드 내부의 주요 인스턴스를 확인한다. 새 표는 동일하게 직렬화되며 새 도메인의 고유 제약을 verify.py에 추가한다.

## 런타임 데이터 흐름

1. 서버가 경기 ID, 종료 시각, 참가자와 언어 스냅샷을 만든다. 클라이언트는 종료 시각에서 표시용 시간을 계산한다.
2. 서버가 문제 ID와 사용자별 순번을 발급한다. 클라이언트는 입력 버퍼를 로컬에서 갱신하고 완료 시 경기 ID·발급 순번·입력 문자열을 제출한다.
3. 서버가 세션·순번·기한·정답을 확인하고 해당 순번을 한 번만 소비한다. 서버가 선택한 Excel 행으로 점수와 골드를 계산한다. 확정 순위와 다음 문제를 UI에 전달한다. 중복 완료는 기존 상태를 재전달한다.
4. 결산은 참가자별 고정 결과를 만든다. 계정별 경기 ID를 보상 변경과 함께 기록해 재시도에도 한 번만 반영한다. 문제마다 DataStore를 쓰지 않는다. 순위 집계 실패는 이미 확정한 보상에 영향을 주지 않는다.
5. 플레이어 데이터 작업은 PlayerStore.getDocument(userId) → Open 성공 확인 → 캐시 변경 → 저장·Close 순서로 구성한다. 세션 잠금과 BindToClose를 유지한다. Studio와 live scope를 분리한다. 실패 중 구매·보상을 확정 표시하지 않는다. 상품 소유권, 재화 차감, 중복 처리 키는 같은 프로필 변경에서 확정한다.
6. 분석에는 경기·문제 ID, 언어, 기기, 완료 시간, 결과를 사용한다. 원문 입력을 지표에 보관할 필요는 없다.

## 반응형 UI 검수

StarterGui는 LandscapeSensor이고 클라이언트는 CoreUISafeInsets가 적용된 SafeRoot의 AbsoluteSize를 측정한다. 크기가 바뀌면 Compact, ContentWidth, TouchTarget 속성을 다시 계산한다. 공통 화면은 속성 변경을 구독하고 목록·미리보기·키보드 영역을 재배치한다. 터치 키보드 노출은 입력 방식, 화면 밀도는 사용 가능 크기로 결정한다. 터치가 가능한 노트북과 외장 키보드 태블릿도 별도 확인한다.

| Studio 에뮬레이션 기준 | 점검할 압박 조건 | 통과 기준 |
|---|---|---|
| 568×320 가로 | 짧은 세로, 모바일 키보드 4행, 긴 문제 | 문제·입력·Enter 동시 노출. 키 행이나 순위 패널이 겹치지 않음 |
| 844×390 가로 | 노치·상단 Core UI, 긴 번역 | 양쪽 회전에서 닫기·Backspace가 안전 영역 안에 있고 마지막 글자 보임 |
| 1024×768 태블릿 | 상대적으로 좁은 가로 비율 | 상점 목록/미리보기/버튼 접근 가능. 긴 목록은 내부 스크롤 |
| 1366×768 PC | 물리 키보드·창 크기 변경 | 터치 키보드 없이 문제 공간 확장. 열린 화면·입력·선택 보존 |
| 1920×1080 및 2560×1080 | 넓은 양쪽 여백 | 중앙 콘텐츠 너비 제한, 순위와 본문이 읽을 수 있는 거리 유지 |

이 해상도와 36/44 UI 픽셀 터치 목표는 **초기 검수 기준**이다. 출시 최소 사양은 실기기에서 정한다. 작은 화면에서는 순위 행 수와 장식을 먼저 줄이고, 긴 설명은 줄바꿈·스크롤한다. 핵심 점수·언어·입력 키를 잘라내지 않는다. 화면 작업의 증빙에는 해상도, SafeRoot 크기, 입력 방식, 언어, 해당 화면 스크린샷과 관찰 결과를 기록한다.

## 재사용 이미지와 Studio 확인

- KDefenceSimulator/assets/item-icons/source에서 골드·이동·닫기·잠금·확인·설정·사운드·랭킹 등에 해당하는 22개 원본을 복사했다. ID와 의미는 ItemDataSheet에서 확인한다. 새 페이지는 기존 게임과 슬롯이 다르므로 생성된 ItemIconAtlas_1.png를 게시한 뒤 Shared/ItemIconPages에 해당 이미지 ID를 등록한다. 등록 전 ItemIconUtil.apply의 false 반환을 처리한다.
- UI 패널 2종과 중립 발광·반짝임·버스트 원본, 해당 아틀라스 4장, 기존 이미지 ID 및 영역 좌표를 함께 복사했다. Shared.UIImageUtil.apply(panel, "panel-9slice")로 사용한다. Studio 프리뷰는 이 경로로 9-slice를 실제 호출한다. 대상 경험에서 이미지가 로드되는지 확인하고, 권한이 다르면 복사한 페이지를 게시해 UIImageAssetIds를 갱신한다.
- Studio Play에서 리스폰과 창 크기 변경 후 SafeRoot가 하나인지 확인한다. PreviewCoreUI에서 패널 모서리·문자열·Output을 확인한다. 실제 저장 왕복은 M4 테스트 계정으로 수행한다. 게시할 Lobby Place의 최대 플레이어 수를 12로 설정하고 게시된 값도 확인한다. Luau의 경기 정원과 별개인 Place 설정이다.
