# KeyboardWarrior 작업 규칙

1. README.md로 실행 경로를 확인하고 docs/GameDesign.ko.md와 docs/Harness.ko.md에서 변경할 기능의 확정 조건과 파일럿 가정을 확인한다. FromGPT는 원본 참고 자료로 보존한다.
2. GPT Work에서 규칙·화면·승인 기준을 작성하고 Cursor에서 해당 단계의 구현과 검증을 한다. 기획 변경은 기획서와 관련 검증 조건에 함께 반영한다. Studio 수동 확인과 자동 통과를 구분해 보고한다.
3. 단일 Lobby Place와 모바일 가로 공통 GUI를 유지한다. Workspace의 수작업 맵은 KeyboardWarrior.rbxl에서 관리한다. Rojo 빌드의 출력은 build/에 둔다.
4. 반복되는 행 데이터는 tables/*.xlsx, 시스템 수치는 src/ReplicatedStorage/Shared/IngameConstants.luau, 표시 문자열은 src/localization/CoreStrings.csv가 원본이다. 생성된 Table/*.txt와 ItemIconSlots.luau는 도구로 갱신한다.
5. 클라이언트는 입력·표시·미리보기를 담당한다. 서버가 문제·점수·보상·소유·저장을 확정한다. UI가 직접 DataStore나 상품 지급 함수를 호출하는 경로를 만들지 않는다.
6. UI는 KeyboardWarriorUI.SafeRoot와 Layout의 크기 변경을 사용한다. 새 디바이스용 화면 복제 대신 같은 화면에서 배치·스크롤·표시 밀도를 조절한다.
7. 변경 후 python tools/verify.py를 실행한다. 화면 변경은 기기 매트릭스, 데이터 변경은 키·참조·생성본, 저장 변경은 실패·재시도·재접속을 추가 확인한다. 미확인 항목은 재현 절차와 함께 남긴다.
