# Cursor 작업 요청 · 점수 타이틀과 상점 색상 적용

D:\KeyboardWarrior에서 docs/TitleSystem.ko.md, tables/AchievementDataSheet.xlsx, tables/ShopDataSheet.xlsx, src/localization/CoreStrings.csv를 기준으로 아래 기능을 구현해 주세요. 원본 엑셀과 영문·국문 타이틀 및 상품명 40개는 입력되어 있습니다.

1. **이전 프로젝트 코드 이식.** D:\KDefenceSimulator\src 아래 ReplicatedStorage/Shared/Data/AchievementData.luau, Shared/TitleRules.luau, Shared/TitleProgress.luau, Shared/Tests/TitleRulesTest.luau(모두 ReplicatedStorage 기준), ServerScriptService/Services/TitleService.luau, ReplicatedStorage/Controllers/TitleOverheadController.luau와 TitlePopupController.luau를 참고합니다. 보유 여부 검사, 서버 장착 검증, 속성 복제, 캐릭터 생명주기 처리를 재사용합니다. Stage 일치 검사를 단일 경기 Score 하한 검사로, RewardId 처리를 ShopId 소유권 지급으로 교체합니다. 이 프로젝트의 TableData, Localization, ProfileService 및 Bootstrap에 연결합니다.
2. **테이블 전환.** 기존 ShopRules의 Style 허용 목록, Paint와 상품 payload, PadLook, FloorRise, 서버 발판·상점 미리보기 경로 및 StudioSmoke의 하드코딩된 색상 분기를 조사합니다. Color 문자열은 로드 시 검증하고 3개 채널을 파싱합니다. Body 본체, Rim 테두리, Effect 입자·장식과 층 상승 연출에 같은 색을 반영합니다. 기존 저장 데이터의 상품 ID와 기본 Rim·Effect의 숨김 동작을 보존합니다. Live 상품 30행, Studio 3행, Default 3행을 구분합니다.
3. **서버 정산.** RewardService가 확정한 완주 점수로 미보유 업적 중 경기 점수 ≥ 행의 Score 조건을 모두 선별합니다. RewardRules.applyGrant와 ProfileService.commit에서 기존 settlementId 중복 방지와 같은 프로필 갱신 단위로 타이틀 소유, 연동 Rim 소유, 장착 상태, 경기 보상을 반영합니다. 처리 결과의 신규 획득 ID 목록을 기존 결과 스냅샷에 보존합니다. 저장 재시도나 결과창 재조회 때 두 번 지급하거나 신규 목록이 소실되지 않도록 합니다. 프로필이 늦게 열려 재정산되는 경로도 포함합니다.
4. **프로필·장착.** 보유 ID, 장착 ID, 자동/수동 모드를 영속화합니다. 기존 계정은 빈 보유 목록과 자동 모드로 시작합니다. DataConfig 검증, ProfileService 복사, 설정·튜토리얼·상점·보상 처리의 명시적 필드 복사를 모두 확인합니다. 자동 모드에서는 신규 획득 후 최고 보유 ID를 적용합니다. 수동 선택은 새 타이틀 해금 후에도 유지합니다. 로비의 기존 상점에서 접근 가능한 타이틀 선택 UI에 보유 목록·장착 상태·자동 장착 복귀를 제공합니다. 서버는 미보유 ID, 잘못된 모드, 과도한 요청을 거절합니다.
5. **표시와 구매.** 결과창에 신규 타이틀과 보상 Rim의 현지화된 이름을 모두 표시합니다. 친구·다른 유저·자기 자신에게 EquippedTitleId를 기반으로 로비 머리 위 타이틀이 보이게 합니다. 늦은 입장, 리스폰, 언어 변경, 장착 변경, 경기 진입·로비 복귀와 연결 해제를 처리합니다. 잠긴 Achievement 상품에는 획득 점수를 표시하고 서버 구매 요청을 차단합니다. 획득 후에는 일반 소유 상품처럼 장착할 수 있습니다. RobloxBadgeId가 빈 행은 배지 API를 호출하지 않습니다.
6. **검증과 적용.** tools/verify.py의 기존 Style·Gold/Robux 전용·Live 판매 금지 계약과 관련 Luau 테스트를 새 스펙으로 교체합니다. 기존 기본·Studio 상품 검증은 유지합니다. 중복 ID, 잘못된 RGB, 보상 참조 오류를 검출하도록 하고 python tools/sync_tables.py로 생성본을 갱신한 뒤 python tools/verify.py와 Rojo 빌드를 실행합니다. 생성된 txt는 직접 편집하지 않습니다.

### 완료 기준

- 첫 완주 199점은 0개, 200점은 1개, 720점은 3개, 1,500점은 10개다. 동일·낮은 기록, 정산 재시도, 중도 퇴장, 연습에서는 이미 지급한 타이틀 및 Rim이 추가되지 않는다.
- 자동 상태에서 720점 달성 후 장착 ID는 3이다. 수동으로 ID 1을 장착한 뒤 900점을 달성하면 ID 4와 Rim을 획득하고 장착은 1이다. 재접속해도 동일하며 자동으로 복귀하면 ID 4가 장착된다.
- 두 클라이언트가 서로의 타이틀과 장착 변경을 확인한다. 모바일 가로에서 첫 경기 10개 획득 결과 전체를 확인하고 닫을 수 있다.
- 기존 계정의 골드·경험치·랭크·설정·장착 상품이 유지된다. Body/Effect 구매 및 재구매 방지, 업적 Rim 구매 거부, 소유 Rim 장착, RGB 미리보기와 실제 발판 일치를 확인한다.
