# 기여 가이드 (Contributing)

Flight Data Dashboard 프로젝트에 기여해 주셔서 감사합니다.
본 문서는 코드 스타일, 커밋 규칙, 브랜치 전략, PR 절차를 정리합니다.

## 시작하기

### 개발 환경

- **MATLAB R2024b 이상** (R2025a 권장)
- **Image Processing Toolbox**
- **Parallel Computing Toolbox** (비동기 디코딩 테스트 시)
- **Git for Windows** + GitHub 계정
- (선택) **Visual Studio Code** + MATLAB Extension

### 첫 셋업

```bash
git clone https://github.com/kiki-github2019/flight-dashboard.git/
cd flight-dashboard
```

MATLAB에서:

```matlab
addpath(genpath(pwd))
FlightDataDashboard
```

## 브랜치 전략

```
main                — 배포 가능한 안정 버전 (보호 브랜치)
└── develop         — 통합 개발 브랜치
    ├── feature/*   — 신규 기능 (예: feature/sync-model-step5)
    ├── fix/*       — 버그 수정 (예: fix/zombie-listener)
    ├── refactor/*  — 리팩토링 (예: refactor/view-decoupling)
    └── docs/*      — 문서 (예: docs/architecture-update)
```

- `main` 직접 push 금지 — PR을 통해서만 머지
- `develop` 에서 분기 → 작업 완료 후 `develop` 으로 PR
- 릴리스 시 `develop` → `main` 머지 + 태그 (`v0.13.0` 등)

## 커밋 메시지 규칙

[Conventional Commits](https://www.conventionalcommits.org/) 를 따릅니다.

### 형식

```
<type>(<scope>): <subject>

<body>

<footer>
```

### 타입 (`<type>`)

| 타입 | 용도 | 예시 |
|---|---|---|
| `feat` | 신규 기능 | `feat(eventbus): add SliderChangedFinal event` |
| `fix` | 버그 수정 | `fix(splitter): protect H panel min width` |
| `refactor` | 리팩토링 (동작 동일) | `refactor(view): remove app dependency from InfoPanel` |
| `perf` | 성능 개선 | `perf(cache): replace cellfun with BytesArr lookup` |
| `docs` | 문서 변경 | `docs(readme): add high-DPI section` |
| `test` | 테스트 추가/수정 | `test(sync): add timeToFrame jitter test` |
| `chore` | 빌드/도구/의존성 | `chore(gitignore): add slprj cache` |
| `style` | 포맷팅/공백 | `style: align uigridlayout property names` |

### 스코프 (`<scope>`)

`view`, `controller`, `model`, `util`, `eventbus`, `cache`, `sync`, `splitter`, `dpi`, `async` 등.

### 제목 (`<subject>`)

- 50자 이내
- 영문 명령형 또는 한글 명사형 모두 허용 (한 PR 내 일관성 유지)
- 마침표 없이 종료

### 예시

```
fix(splitter): H panel을 minimum width 아래로 압축되지 않게 보호

기존 max(280, gridW-fixedSum-hMin) 로직이 좁은 창에서 video 280을
H 320 위로 우선시키는 회귀를 일으켰음. H 우선화로 변경.

- maxVideoW = gridW - fixedSum - hMin (양수일 때만 진행)
- videoMin = min(280, maxVideoW) — H 보호 후 잔여 한도 내에서만 양보

Closes #42
```

## 코드 스타일

### MATLAB 일반

- **들여쓰기**: 4 spaces (탭 금지)
- **줄 길이**: 120자 이내 권장
- **줄바꿈**: 긴 호출은 `...` continuation 사용
- **주석**: 기능/의도 설명, 코드 흐름과 일치 유지

### 명명 규칙

| 대상 | 규칙 | 예시 |
|---|---|---|
| 패키지 | 소문자 + `+` prefix | `+flightdash`, `+util` |
| 클래스 | PascalCase | `EventBus`, `FrameCacheModel` |
| 메서드 | camelCase | `applyVideoSync`, `handleFlightFile` |
| Private 메서드 | camelCase + `_` suffix | `evictByScore_`, `frameBytes_` |
| 속성 (public) | PascalCase | `BudgetMB`, `TotalFrames` |
| 속성 (private) | PascalCase | `Cache`, `BytesArr` |
| 상수 | UPPER_SNAKE | `MAX_TABS`, `SLIDER_THROTTLE_S` |
| 이벤트 | PascalCase | `TableRowSelected`, `PlotTabAddRequested` |
| 채널 인덱스 | `fIdx` (1, 2; 비채널 0) | `applyVideoSync(app, fIdx)` |
| 메서드 prefix | `on<Event>` (콜백), `apply<X>` (변경), `update<X>` (UI 갱신) | `onVideoLoaded`, `applyTimeChange`, `updateDashboard` |

### 예외 처리

```matlab
try
    riskyOperation();
catch ME
    app.logCaught(ME, 'tagName');   % ErrorLog 위임
end
```

- `'silent'` 태그는 운영 중 무시할 사소한 예외용 (DebugMode 시에만 콘솔 출력)
- `'tagName'` 은 정상 운영에서도 알 가치 있는 예외용
- 절대 빈 `catch` 사용 금지

### 가드/플래그 패턴

```matlab
if app.IsUpdating(fIdx), return; end
app.IsUpdating(fIdx) = true;
cleanup_ = onCleanup(@() resetIsUpdating(app, fIdx));   %#ok<NASGU>

% ... 작업 ...
% cleanup_은 함수 종료/예외 시 자동 실행
```

플래그 리셋은 항상 `onCleanup` 으로 보장. 수동 리셋 + try-catch 조합 지양.

### EventBus 사용

**View → publish**:

```matlab
'ButtonPushedFcn', @(~,~) EventBus.publish('FlightFileRequested', AppEventData(fIdx))
```

**Controller → subscribe**:

```matlab
obj.Listeners{end+1} = EB('FlightFileRequested', @(~,d) obj.onFlightFile(d));
```

**Controller → 메서드 호출**:

```matlab
function onFlightFile(obj, d)
    obj.App.handleFlightFile(d.ChannelIdx);
end
```

### High-DPI 픽셀

하드코딩 픽셀 값은 항상 `UIScale.px()` 통과:

```matlab
% 잘못
glCtrl.ColumnWidth = {100, 150, '1x'};

% 옳바름
glCtrl.ColumnWidth = {UIScale.px(100), UIScale.px(150), '1x'};
```

## Pull Request 절차

### PR 작성 전 체크리스트

- [ ] 브랜치가 `develop` 최신 상태에서 분기되었는지 (`git pull origin develop --rebase`)
- [ ] 커밋 메시지가 Conventional Commits 형식인지
- [ ] 새 기능에 대한 동작 확인 (수동 테스트 시나리오 PR 본문에 기술)
- [ ] 기존 기능 회귀 없는지 (관련 시나리오 재실행)
- [ ] DebugMode 활성화 후 콘솔 에러/경고 없는지
- [ ] 96 / 125 / 150 DPI 환경에서 UI 깨짐 없는지 (UIScale 영향 변경 시)
- [ ] CHANGELOG.md 의 `[Unreleased]` 섹션 업데이트

### PR 본문 권장 형식

```markdown
## 변경 요약
무엇을 / 왜 변경했는지 1~3문장.

## 상세 변경 내역
- 파일/위치별 핵심 변경

## 테스트 시나리오
1. ...
2. ...

## 회귀 점검
- [x] 슬라이더 드래그 정상
- [x] 플롯 별표 마커 정상
- [x] 동기 버튼 토글 정상

## 관련 이슈
Closes #N
```

### 리뷰 정책

- 최소 1명 승인 필요
- 대규모 변경 (200줄 이상) 은 2명 권장
- 리뷰어는 24시간 내 1차 응답 권장
- 핵심 모듈 (EventBus, FrameCacheModel, SyncModel) 변경 시 아키텍처 영향 평가 필수

## 테스트 가이드

### 수동 테스트 핵심 시나리오

각 PR 머지 전 다음을 확인:

1. **로드 흐름**: 비행경로 1 → AVI 1 → 동기 → 슬라이더 동작
2. **드래그**: 플롯 별표 / Altitude 별표 / Frame Navigator 슬라이더 모두 양방향
3. **줌**: H 패널 줌 → 마커 자동 중앙 점프 + 전체 동기
4. **페이지 넘김**: 확대 상태에서 빠르게 드래그 → X축 자동 이동
5. **패널 토글**: 자세/지도/비디오 ▾▸ 토글 → H 폭 자동 조정
6. **스플리터**: H↔I 경계 드래그 → H 보호 (320px 이하 불가)
7. **종료/재실행**: 앱 종료 후 재실행 → 좀비 컨트롤러 에러 없음
8. **DebugMode**: 체크박스 ON → 핵심 동작 모두 콘솔 추적 가능

### 단위 테스트 (선택, 권장)

`tests/` 디렉토리에 MATLAB Unit Test 추가 권장:

```matlab
classdef TestSyncModel < matlab.unittest.TestCase
    methods (Test)
        function testFrameToTimeIdentity(testCase)
            sm = flightdash.model.SyncModel;
            sm.setAnchor(100, 5.0, 0);
            t = sm.frameToTime(100, 30);
            testCase.verifyEqual(t, 5.0, 'AbsTol', 1e-9);
        end
    end
end
```

실행: `runtests('tests')`

## 보안 / 비밀

- **`.env`**, **`config.local.*`**, 자격증명 등은 절대 커밋 금지 (`.gitignore` 보호 중)
- **API 키**, **사내 URL**, **개인 식별 데이터(PII)** 는 PR 본문/주석에도 포함 금지
- 사고 발견 시 즉시 [BFG Repo-Cleaner](https://rtyley.github.io/bfg-repo-cleaner/) 또는 `git filter-repo` 로 히스토리 정리

## 도움이 필요할 때

- 아키텍처/EventBus 관련 질문 → `docs/architecture.md` 참고
- 변경 이력 → `CHANGELOG.md`
- 알려진 제약사항 → `README.md` 의 "알려진 제약사항" 섹션
- 그 외 → 이슈 등록 (`Question` 라벨)

## 행동 강령

본 프로젝트는 [Contributor Covenant](https://www.contributor-covenant.org/) 의 정신을 따릅니다.
존중하는 토론, 건설적 피드백, 인내를 부탁드립니다.
