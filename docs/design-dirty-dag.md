# Dirty DAG 설계: Auto Update / Recalculate 의존성 추적

**문서 버전:** v1.0 | **작성일:** 2026-05-08 | **Phase:** 0.5 (Phase 8 진입 전 결정사항)

---

## 0. 결정 요약

| 항목 | 결정 |
|---|---|
| **데이터 구조** | 명시적 의존 그래프 (DAG) — 각 노드가 `dependsOn[]` 보유 |
| **노드 식별자** | `NodeId` 문자열 — `"<scope>:<sessionId>:<kind>:<localId>"` |
| **Dirty 전파 알고리즘** | 깊이 우선 BFS 기반 forward marking + 위상 정렬 후 재계산 |
| **재계산 트리거** | Manual / Auto / Frozen — 노드별 모드 |
| **Auto debounce** | 100ms 슬라이딩 윈도우 — burst 변경 시 마지막만 처리 |
| **순환 검출** | 그래프 추가 시 즉시 Tarjan SCC 검사 |
| **재계산 실패 처리** | 노드를 `dirty` + `error` 상태로 마킹, 의존 노드도 stale |

**한 줄 요약:** 모든 결과/플롯/분석 노드를 단일 DAG에 등록하고, 원본 변경 시 forward 전파로 dirty 마킹, 재계산은 위상 정렬 순서대로 실행, Auto 모드는 debounce로 burst 변경을 흡수한다.

---

## 1. 핵심 개념

### 1.1 노드 (Node)

DAG의 모든 노드는 다음 인터페이스를 가짐:

```text
DirtyNode
 ├─ NodeId          : 고유 식별자 (string)
 ├─ NodeKind        : 'source' | 'derived'
 ├─ DependsOn[]     : 직접 의존 NodeId 목록
 ├─ Dependents[]    : 본 노드에 의존하는 NodeId 목록 (역방향, 캐시)
 ├─ DirtyState      : 'clean' | 'dirty' | 'computing' | 'error' | 'stale'
 ├─ RecalculateMode : 'Manual' | 'Auto' | 'Frozen'
 ├─ LastCalculatedAt: ISO timestamp
 ├─ LastError       : MException or empty
 └─ ComputeFn       : 재계산 함수 핸들 (derived 노드만)
```

### 1.2 노드 종류

**Source 노드 (잎 노드):**
- 외부 입력에 의해 변경됨 (사용자 액션, 파일 변경)
- 의존 없음 (`DependsOn = []`)
- `ComputeFn` 없음 (수동으로 dirty 마킹)

**Derived 노드 (내부 노드):**
- 다른 노드에서 계산됨
- `DependsOn`이 비어있지 않음
- `ComputeFn`을 호출하면 자동 재계산

### 1.3 Dirty 상태 전이

```text
        [external change]
              ↓
clean ──────► dirty ──────► computing ──┬──► clean
                                        └──► error

clean (upstream changed)  ─────► stale (Frozen 노드만)

stale ──[user acknowledge]──► clean (force)
```

**상태 의미:**
- `clean` : 결과 유효, 표시 가능
- `dirty` : 의존 변경 감지, 재계산 필요
- `computing` : 재계산 진행 중 (UI에 spinner)
- `error` : 마지막 재계산 실패, 결과 없음
- `stale` : Frozen 노드 — 의존이 변했으나 사용자가 동결 의도

---

## 2. NodeId 명명 규칙

### 2.1 형식

```text
<scope>:<sessionId>:<kind>:<localId>
```

| 필드 | 값 | 비고 |
|---|---|---|
| scope | `proj` / `sess` / `fig` / `result` / `theme` | 1차 분류 |
| sessionId | `S001`, `S002` 등, 또는 `*` (전역) | proj/theme는 `*` |
| kind | `rawData` / `roi` / `sync` / `analysis` / `plot` / `figure` | 노드 종류 |
| localId | 정수 또는 결과 ID (예: `R001`) | scope+kind 내 unique |

### 2.2 예시

| NodeId | 의미 |
|---|---|
| `sess:S001:rawData:0` | 세션 1의 비행 raw data |
| `sess:S001:videoSync:0` | 세션 1의 비디오 동기 상태 |
| `sess:S001:roi:0` | 세션 1의 ROI 0번 |
| `sess:S001:roi:1` | 세션 1의 ROI 1번 |
| `result:S001:R001` | 세션 1의 분석 결과 R001 |
| `result:S001:R002` | 세션 1의 분석 결과 R002 (R001에 의존 가능) |
| `fig:*:F003` | 세션 무관 비교 그래프 F003 |
| `theme:*:default_roi` | 분석 테마 |

### 2.3 의존 관계 예시

```text
sess:S001:rawData:0   (source)
   ├─► sess:S001:roi:0           (derived — rawData에서 잘라냄)
   │     └─► result:S001:R001    (derived — ROI 통계)
   │           └─► fig:*:F002    (derived — 결과 시각화)
   └─► sess:S001:roi:1
         └─► result:S001:R002
               └─► result:S001:R003   (derived — R001+R002 비교)
                     └─► fig:*:F003
```

---

## 3. 핵심 알고리즘

### 3.1 markDirty: 변경 전파

**입력:** 변경된 노드의 NodeId

**동작:**

```text
function markDirty(nodeId):
    queue = [nodeId]
    visited = {}
    while queue not empty:
        current = queue.pop_front()
        if current in visited: continue
        visited.add(current)

        node = graph[current]
        if node.RecalculateMode == 'Frozen':
            node.DirtyState = 'stale'
            // Frozen 노드는 dirty 전파를 멈추지 않음
        else:
            node.DirtyState = 'dirty'

        for dep in node.Dependents:
            queue.push_back(dep)

    notify('NodeDirty', visited)
```

**복잡도:** O(V + E) — 변경 영향 노드 수에 비례.

### 3.2 recalculateAll: 위상 정렬 후 재계산

**입력:** dirty 노드 집합

**동작:**

```text
function recalculateAll(dirtyNodeIds):
    // 1. 영향받는 모든 dirty 노드 수집 (downstream 포함)
    affected = collectDirtyClosure(dirtyNodeIds)

    // 2. affected 노드의 sub-graph에서 위상 정렬
    sorted = topologicalSort(affected)
    if hasCycle(sorted):
        raise CycleDetectedException

    // 3. 순서대로 재계산
    for nodeId in sorted:
        node = graph[nodeId]
        if node.RecalculateMode == 'Frozen':
            continue  // 동결 노드는 건너뜀
        if any upstream still dirty:
            continue  // 직전 단계 실패 시 스킵

        try:
            node.DirtyState = 'computing'
            notify('NodeComputing', nodeId)
            result = node.ComputeFn()
            node.cachedValue = result
            node.LastCalculatedAt = now()
            node.DirtyState = 'clean'
        catch ex:
            node.DirtyState = 'error'
            node.LastError = ex
            log('Recalc failed', nodeId, ex)
        notify('NodeStateChanged', nodeId)
```

**위상 정렬 (Kahn's algorithm):**

```text
function topologicalSort(nodes):
    inDegree = {n: count(deps in nodes) for n in nodes}
    queue = [n for n in nodes if inDegree[n] == 0]
    result = []
    while queue not empty:
        n = queue.pop_front()
        result.append(n)
        for dep in n.Dependents ∩ nodes:
            inDegree[dep] -= 1
            if inDegree[dep] == 0:
                queue.push_back(dep)
    if len(result) != len(nodes):
        raise CycleDetectedException
    return result
```

### 3.3 addNode: 노드 추가 + 순환 검출

**입력:** NodeId, DependsOn[]

**동작:**

```text
function addNode(nodeId, dependsOn):
    if nodeId in graph:
        raise NodeExistsException

    // 1. 의존성이 모두 존재하는지 확인
    for dep in dependsOn:
        if dep not in graph:
            raise UnknownDepException

    // 2. 임시로 추가
    graph[nodeId] = newNode
    for dep in dependsOn:
        graph[dep].Dependents.append(nodeId)

    // 3. 순환 검출 (Tarjan SCC)
    sccs = tarjanSCC(graph)
    nontrivialSccs = [scc for scc in sccs if len(scc) > 1]
    if nontrivialSccs not empty:
        // 롤백
        for dep in dependsOn:
            graph[dep].Dependents.remove(nodeId)
        del graph[nodeId]
        raise CycleException(nontrivialSccs)
```

**비용:** Tarjan SCC는 O(V + E) — 그래프 전체 1회 스캔. 노드 1000개·엣지 5000개 기준 ~10ms.

---

## 4. Recalculate 모드 정책

### 4.1 모드별 동작

| 모드 | dirty 발생 시 | 사용자 의도 |
|---|---|---|
| **Manual** | dirty로 마킹, UI에 빨간 점 표시, 사용자가 Recalculate 버튼 누를 때까지 대기 | 명시적 컨트롤 원함 |
| **Auto** | dirty로 마킹 → debounce 100ms → 자동 재계산 | 인터랙티브 분석 |
| **Frozen** | stale로 마킹, 재계산 안 함, 결과 보존 | 과거 결과 보존 (예: 보고서 첨부용) |

### 4.2 모드 변경 시 동작

| from → to | 동작 |
|---|---|
| Manual → Auto | 현재 dirty면 즉시 재계산 시작 |
| Manual → Frozen | dirty면 stale로 변환, clean이면 그대로 |
| Auto → Manual | 진행 중 재계산은 완료까지 진행, 이후 dirty 발생해도 자동 재계산 안 함 |
| Auto → Frozen | 진행 중 재계산 cancel, 결과 보존 |
| Frozen → Manual | stale 상태 유지 (사용자가 Recalculate 또는 Acknowledge 선택) |
| Frozen → Auto | stale이면 즉시 재계산 시작 |

### 4.3 노드별 default 모드

| 노드 종류 | Default | 이유 |
|---|---|---|
| ROI | (의미 없음 — source) | source 노드는 모드 없음 |
| Analysis Result | Auto | 인터랙티브 |
| Comparison Figure | Auto | 인터랙티브 |
| 명시적 보고서 첨부 결과 | Frozen | 보존 의도 |

---

## 5. Auto debounce 메커니즘

### 5.1 문제

빠른 slider drag 또는 ROI resize 시 매 프레임 dirty → 매 프레임 재계산 → UI 멈춤.

### 5.2 해결책

**Sliding window debounce:**

```text
function onNodeDirty(nodeId):
    if RecalculateMode != 'Auto': return

    if pendingTimer[nodeId] exists:
        cancel(pendingTimer[nodeId])

    pendingTimer[nodeId] = scheduleAfter(100ms, () -> {
        recalculateAll([nodeId])
        delete pendingTimer[nodeId]
    })
```

**Per-kind debounce 시간:**

| 노드 종류 | Debounce |
|---|---|
| ROI 통계 (가벼움) | 100ms |
| Sync Quality 분석 | 250ms |
| FFT / 신호 처리 | 500ms |
| Comparison Figure | 200ms (렌더링 비용) |

### 5.3 백그라운드 큐

여러 노드가 동시에 dirty되어 debounce 만료 시:

```text
recalcQueue = priority queue
priority = (active session weight, node priority, dirty timestamp)

worker thread (single):
    while true:
        node = recalcQueue.pop()
        if node.RecalculateMode != 'Auto': continue
        recalculateOne(node)
        notify('NodeStateChanged', node.id)
```

**MATLAB 구현:** Parallel Computing Toolbox `parfeval` 또는 `timer` 객체로 단일 worker. 비행 데이터는 멀티코어가 큰 도움 안 됨 (대부분 I/O + 단순 통계).

---

## 6. 모델 통합

### 6.1 ReviewResultModel 필드 확장

기존 계획서 §4.4의 필드에 추가:

```text
ReviewResultModel
 ├─ ResultId
 ├─ ...
 ├─ DependsOn[]         (string array — NodeId 목록)
 ├─ NodeKind            (항상 'derived')
 ├─ DirtyState          (위 §1.3의 5-state)
 ├─ LastError           (MException or empty)
 └─ ComputeFnHandle     (function_handle — 직렬화 시 themeId+inputSnapshot으로 재구성)
```

### 6.2 직렬화 규칙

`ComputeFnHandle`은 직렬화 불가 → 다음 정보로 재구성:

```json
{
  "computeFnSpec": {
    "analyzer": "RoiStatisticsAnalyzer",
    "method": "computeStats",
    "inputSnapshot": {
      "sessionId": "S001",
      "roiNodeIds": ["sess:S001:roi:0"],
      "themeId": "default_roi"
    }
  }
}
```

로드 시 `AnalyzerRegistry.resolveComputeFn(spec)` → function handle 재구성.

### 6.3 DirtyTracker 클래스 위치

`+flightdash/+project/DirtyTracker.m` (계획서 §3.1 폴더 구조에 이미 존재)

**책임:**
- 그래프 보관 (`Map<NodeId, DirtyNode>`)
- markDirty / recalculateAll 알고리즘 실행
- debounce 타이머 관리
- EventBus를 통한 `NodeDirty`, `NodeComputing`, `NodeStateChanged` 이벤트 발행

---

## 7. 사용자 시나리오 walkthrough

### 7.1 시나리오 A: ROI 추가 후 통계 결과 자동 갱신

```text
User Action: ROI 0번 시간 범위 변경 (Auto mode)
           ↓
sess:S001:roi:0 .markDirty()
           ↓
DirtyTracker:
  affected = [sess:S001:roi:0, result:S001:R001, fig:*:F002]
  topo sort = 위 순서
  debounce timer (100ms) 시작
           ↓ (100ms 후)
recalculateAll:
  result:S001:R001 → RoiAnalyzer.computeStats() → 새 mean/RMSE
  fig:*:F002 → plot 다시 렌더링
           ↓
UI: status bar "Recalculated 2 results in 142ms"
    Explorer R001 노드 빨간 점 사라짐
```

### 7.2 시나리오 B: 비행 raw data 외부 변경

```text
External: flight_001.dat 파일이 외부 도구로 수정됨
           ↓
Studio 시작 시 또는 주기적 hash 검사:
  shallow_hash 변경 감지
           ↓
sess:S001:rawData:0 .markDirty()
           ↓
DirtyTracker:
  affected = 해당 세션의 모든 ROI, 모든 분석 결과, 모든 plot
  Frozen 노드는 stale, 나머지는 dirty
           ↓
사용자에게 알림: "Flight data changed externally. 5 results need recalculation."
[Recalculate All] [Skip] 다이얼로그
```

### 7.3 시나리오 C: Frozen 결과 보존

```text
User Action: result:S001:R001을 Frozen으로 변경
           ↓
이후 sess:S001:roi:0 변경 발생
           ↓
DirtyTracker:
  result:S001:R001.state = 'stale'  (재계산 안 함)
  result:S001:R001 의 downstream인 fig:*:F002는 stale 처리 (R001이 stale이므로)
           ↓
UI: R001 노드 옆 자물쇠 아이콘 + "stale (source changed)" 툴팁
    fig:*:F002 옆 회색 점 + "depends on stale result"
```

### 7.4 시나리오 D: 순환 의존 시도

```text
User Action: result:R003을 정의하면서 dependsOn에 result:R001 추가
           이때 R001이 이미 R003에 의존하면 순환 발생
           ↓
DirtyTracker.addNode(R003, [R001]):
  Tarjan SCC 실행
  → SCC = {R001, R002, R003} (size 3)
  → 롤백
  → CycleException("R001 → R002 → R003 → R001")
           ↓
UI: 에러 다이얼로그 "Cannot create dependency: cycle detected"
    영향 노드 visual highlight
```

---

## 8. 성능 목표

| 지표 | 목표 | 비고 |
|---|---|---|
| 노드 1000개·엣지 5000개 그래프 메모리 | < 50MB | struct array 기반 |
| markDirty 전파 (영향 노드 100개) | < 5ms | BFS 단순 순회 |
| 위상 정렬 (영향 노드 100개) | < 10ms | Kahn O(V+E) |
| 순환 검출 (그래프 1000노드) | < 50ms | Tarjan O(V+E) |
| 가벼운 재계산 1개 (ROI 통계) | < 100ms | RoiAnalyzer 기존 성능 유지 |
| Auto debounce 응답 | 100~250ms | 사용자 인지 임계 |

---

## 9. 구현 단계 (Phase 8 분할)

### Phase 8a — 단일 결과 Manual/Auto/Frozen (의존 없음)

**범위:**
- `DirtyTracker` 클래스 골격
- ROI source 노드 + Analysis Result derived 노드 (직접 의존 1단계)
- Manual/Auto/Frozen 3 모드 전환
- Auto debounce (100ms 단일)

**제외:**
- Result → Result 의존
- 순환 검출
- 위상 정렬

**완료 기준:**
- ROI 변경 시 Auto 모드 결과 자동 갱신
- Frozen 결과는 변경되지 않고 stale 표시

### Phase 8b — 의존 그래프 + 위상 정렬

**범위:**
- Result → Result 의존 추가
- 위상 정렬 + 다단계 재계산
- 순환 검출 (Tarjan SCC)
- 에러 전파 (upstream 실패 시 downstream 스킵)

**완료 기준:**
- Comparison Figure가 두 ROI 결과에 의존 + 양쪽 변경 시 정확한 순서로 재계산
- 순환 의존 시도 차단

### Phase 8c — Auto debounce 고도화 + 백그라운드 큐

**범위:**
- per-kind debounce 시간 (ROI 100ms, FFT 500ms 등)
- 백그라운드 재계산 큐 (timer 또는 parfeval)
- 진행 중 cancel
- UI 진행 표시 (status bar + 노드 spinner)

**완료 기준:**
- Slider 빠르게 drag 시 마지막 값으로만 재계산
- 무거운 분석 진행 중 UI freeze 없음

---

## 10. 결론

**핵심 결정:**
1. 명시적 DAG (각 노드가 dependsOn 보유)
2. NodeId 형식: `<scope>:<sessionId>:<kind>:<localId>`
3. Dirty 전파는 BFS, 재계산은 위상 정렬 (Kahn)
4. 순환은 Tarjan SCC로 즉시 검출
5. Recalculate 모드 3종 (Manual/Auto/Frozen) + Auto debounce 100ms 기본
6. ReviewResultModel에 `DependsOn`, `DirtyState`, `LastError`, `ComputeFnHandle` 필드 추가
7. `DirtyTracker` 단일 클래스가 그래프·전파·재계산·debounce 관리

**Phase 1 진입 전 결정 완료:** ✅ 본 문서 전체

**Phase 7 (Analysis Dialog) 진입 전 추가 결정 필요:**
- AnalyzerRegistry에 등록되는 ComputeFn 시그니처 표준화
- 분석 결과의 NodeId 자동 부여 정책

**Phase 8 진입 전 추가 결정 필요:**
- Tarjan SCC 라이브러리 선택 (MATLAB Graph 객체 vs 자체 구현)
- 백그라운드 큐 worker 수 (1개 권장)
