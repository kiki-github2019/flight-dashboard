# 직렬화 포맷 설계: `.frsproj` (FlightReviewStudio Project)

**문서 버전:** v1.0 | **작성일:** 2026-05-08 | **Phase:** 0.5 (Phase 1 진입 전 결정사항)

---

## 0. 결정 요약

| 항목 | 결정 |
|---|---|
| **확장자** | `.frsproj` (단일 파일) + 옵션 `.frsproj-pack/` (Pack Project 시 폴더) |
| **컨테이너** | ZIP (단일 파일 모드) / Folder (Unpacked 모드 — 개발·디버그용) |
| **메타데이터 직렬화** | JSON (Markdown 래퍼는 사용하지 않음 — ConfigManager와 차이점) |
| **대용량 데이터 직렬화** | MAT v7.3 (HDF5 기반, 부분 로드 지원) |
| **외부 자원** | 절대경로 + 상대경로 + 정책 플래그 (Copy/Link/Pack) |
| **Schema versioning** | `manifest.SchemaVersion` 정수, 마이그레이션 chain |
| **Lazy load** | 메타만 메모리, 세션 데이터는 활성 시 로드 |

**한 줄 요약:** OriginPro `.OPJU`처럼 ZIP 컨테이너 + manifest.json + 자원 폴더로 구성하며, 메타·결과·테마는 JSON으로 텍스트 diff 가능하게 두고, 비행 raw table·plot data array 같은 대용량은 MAT v7.3로 HDF5 부분 로드를 지원한다.

---

## 1. 후보 포맷 비교

| 포맷 | 장점 | 단점 | 채택 여부 |
|---|---|---|:---:|
| **단일 `.mat` (struct save)** | MATLAB 네이티브, 1줄로 save/load | handle class 직접 저장 불가, diff 불가, 부분 로드 어려움, 외부 도구로 검증 불가 | ✗ |
| **단일 JSON** | diff 친화, 외부 도구로 편집 가능 | 대용량 numeric array 비효율 (텍스트 인코딩), MATLAB jsonencode가 큰 table 처리 시 느림/실패 | ✗ |
| **ZIP + manifest.json + assets** | 메타 텍스트 + 데이터 바이너리, 외부 도구 검증 가능, 부분 로드, 압축 | ZIP 라이브러리 의존 (MATLAB 내장 zip/unzip 충분), 임시 폴더 압축/해제 비용 | ✓ |
| **자체 binary** | 최고 성능, 완전 제어 | 외부 도구 호환 0, 디버깅 어려움, 마이그레이션 비용 큼 | ✗ |
| **HDF5 단일 파일 (`.h5`)** | 부분 로드 우수, 표준 포맷 | 메타데이터 표현력 부족 (string 처리 등), MATLAB struct → HDF5 매핑 불완전 | ✗ |

**채택:** ZIP + manifest.json + assets — OriginPro `.OPJU`와 동일한 철학. ZIP 안에 들어가는 개별 자원은 JSON 또는 MAT v7.3.

---

## 2. 파일 구조

### 2.1 `.frsproj` 내부 구조 (ZIP 풀었을 때)

```
ProjectName.frsproj/                      (ZIP 컨테이너)
├── manifest.json                         (필수, 첫 번째 항목 — fast scan)
├── project.json                          (ProjectModel 메타)
├── thumbnails/
│   └── project_thumb.png                 (Windows 탐색기 미리보기용)
├── sessions/
│   ├── S001/
│   │   ├── session.json                  (SessionModel 메타 — flight path, sync state, ROI rows 등)
│   │   ├── plots.json                    (PlotTabs, plotMeta — 가벼운 메타)
│   │   ├── data/
│   │   │   ├── flight_raw.mat            (raw flight table — v7.3, 부분 로드)
│   │   │   └── data_hash.txt             (shallow hash 기록)
│   │   ├── results/
│   │   │   ├── R001.json                 (ReviewResultModel 메타 + computed values)
│   │   │   └── R002.json
│   │   └── snapshots/
│   │       └── frame_8642.png
│   ├── S002/
│   │   └── ...
│   └── ...
├── figures/
│   ├── F001.json                         (FigureModel — Comparison Graph 등 세션 무관 figure)
│   └── ...
├── themes/
│   ├── default_roi.json                  (AnalysisThemeModel)
│   └── compare_sync_quality.json
├── reports/
│   └── 2026-05-08_review.md              (Markdown report — Note Window)
├── logs/
│   ├── message.log                       (CSV: time,project,session,tag,msg)
│   ├── error.log
│   └── result.log
└── external_links.json                   (절대경로 외부 자원 매핑 — 이동 시 깨짐 방지용)
```

### 2.2 manifest.json 스키마

```json
{
  "format": "FlightReviewStudio Project",
  "magic": "FRSPROJ",
  "schemaVersion": 1,
  "createdAt": "2026-05-08T14:23:45+09:00",
  "modifiedAt": "2026-05-08T16:01:12+09:00",
  "createdBy": {
    "studioVersion": "1.0.0",
    "matlabVersion": "9.13",
    "user": "kiki",
    "host": "ws-jungsub"
  },
  "packageMode": "linked",
  "sessions": ["S001", "S002"],
  "figureCount": 3,
  "resultCount": 12,
  "themeCount": 4,
  "checksum": {
    "algorithm": "sha256-shallow",
    "manifestSelf": "ab12...ef89"
  }
}
```

**`packageMode` 값:**

| 값 | 의미 |
|---|---|
| `"linked"` | 외부 자원(flight log, video) 절대경로 참조만 보관 — 가장 가볍고 빠름 |
| `"copied"` | 외부 자원을 `sessions/SXXX/data/`에 복사 → 자체 완결성 |
| `"packed"` | `copied` + ZIP 압축 + 비디오는 별도 `assets/` 폴더 (대용량 처리) |

---

## 3. 핵심 직렬화 규약

### 3.1 handle class → struct 변환

**규칙:** 모든 `+project/*Model.m`은 `value class`로 정의하거나, handle class라면 `saveobj`/`loadobj` 메서드를 명시.

**권장 패턴 — value class 채택:**

> 모든 Model 클래스는 `classdef ProjectModel` (value)로 정의하고, 변경은 새 인스턴스 반환. 컨트롤러가 `app.ProjectModel = updatedModel` 형태로 교체. 이 방식이 직렬화/diff/undo에 모두 유리.

**불가피하게 handle인 경우:**
- `saveobj(obj)` → struct 반환
- `static loadobj(s)` → struct에서 인스턴스 복원

### 3.2 raw flight table 처리

**원칙:** raw table은 manifest에 포함하지 않고 별도 `data/flight_raw.mat`에 저장.

```text
data/flight_raw.mat (MAT v7.3)
 └── rawData         : table (메인 데이터)
 └── mappedCols      : struct (Time, Roll, Pitch, ... 매핑)
 └── displayMeta     : struct array (header, unit, format, order)
```

**부분 로드:** `matfile('data/flight_raw.mat')`로 lazy access — 활성 세션만 메모리 적재.

### 3.3 ReviewResultModel JSON 표현

**원칙:** 결과 자체는 작은 numeric/text이므로 JSON으로 충분. 단, 컬럼이 numeric array면 `[1.2, 3.4, 5.6]` 형식으로 직렬화.

```json
{
  "resultId": "R001",
  "sessionId": "S001",
  "resultType": "ROI",
  "channelIdx": 1,
  "timeRange": [12.5, 18.7],
  "frameRange": [625, 935],
  "variables": ["Roll", "Pitch"],
  "computedValues": {
    "mean": {"Roll": 2.31, "Pitch": -0.45},
    "rmse": {"Roll": 1.07, "Pitch": 0.82},
    "std":  {"Roll": 1.41, "Pitch": 0.98}
  },
  "userComment": "Loiter phase, stable.",
  "linkedFigureId": "F002",
  "sourceDataHash": "sha256-shallow:ab12...",
  "syncStateHash":  "sha256:cd34...",
  "analysisThemeId": "default_roi",
  "recalculateMode": "Auto",
  "dirtyFlag": false,
  "dependsOn": ["S001:rawData", "S001:roi:0"],
  "createdAt": "2026-05-08T14:30:00+09:00",
  "lastCalculatedAt": "2026-05-08T15:42:11+09:00"
}
```

### 3.4 Shallow hash 알고리즘

**목적:** 수십 MB raw flight 파일의 변경을 빠르게 감지.

**알고리즘:**

```text
shallow_hash(filepath) =
    SHA256(
        file_size                       (8 bytes)
      ⊕ mtime_ns                        (8 bytes)
      ⊕ first_1KB                       (1024 bytes)
      ⊕ middle_1KB (offset = size/2)    (1024 bytes)
      ⊕ last_1KB                        (1024 bytes)
    )
```

**비교 비용:** O(1) — 파일 크기와 무관. 50MB 비행 로그도 ~5ms.

**오탐 위험:** 의도적으로 동일 mtime+size를 만들면서 중간 일부만 바꾸는 경우 → 거의 발생 안 함. 실수로 동일 파일을 다른 시점에 저장하면 mtime 다름.

**fallback:** `forceFullHash()` 옵션 — 사용자가 의심스러울 때 강제 풀스캔 (수십 초 소요).

---

## 4. Schema versioning & migration

### 4.1 SchemaVersion 정책

```text
v1: 최초 릴리스 (Phase 9 시점)
v2+: 필드 추가/제거/이름 변경 시 +1
```

**호환성 규칙:**

| 변경 유형 | minor (v1.x) | major (v2.0) |
|---|---|---|
| 새 필드 추가 (옵셔널) | 가능 — 미존재 시 기본값 | — |
| 필드 제거 | 불가 (deprecated 표시 후 다음 major에서 제거) | 가능 |
| 필드 이름 변경 | 불가 | 가능 (마이그레이션 필수) |
| 필드 타입 변경 | 불가 | 가능 (마이그레이션 필수) |

### 4.2 마이그레이션 chain

> `+project/+migration/migrate_v1_to_v2.m`, `migrate_v2_to_v3.m` ... 순차 호출.

**로드 흐름:**

```text
1. manifest.json 읽기
2. schemaVersion = manifest.SchemaVersion
3. while schemaVersion < CURRENT_SCHEMA:
       call migrate_v{N}_to_v{N+1}(projectFolder)
       schemaVersion += 1
4. 모델 인스턴스화
```

**migrate 함수 시그니처:**

```text
input:  projectFolderPath (압축 풀린 임시 디렉토리)
output: 동일 폴더에 수정된 JSON/MAT 파일 (in-place)
```

### 4.3 Forward compatibility

**원칙:** 미래 schema의 추가 필드는 무시 (warning 로그만). 단, **major 버전 차이는 로드 거부**.

```text
loaded.SchemaVersion > CURRENT_SCHEMA의 major:
    → "이 프로젝트는 신버전 Studio에서 작성됨, 업그레이드 필요" 에러
loaded.SchemaVersion > CURRENT_SCHEMA의 minor:
    → "신규 필드 일부 무시" warning + 계속 로드
```

---

## 5. External assets 정책

### 5.1 3가지 모드

**Linked mode (기본):**
- `external_links.json`에 절대경로 + shallow hash 저장
- 자원 이동 시 깨짐 → "파일 찾을 수 없음" 다이얼로그 표시 + 사용자 재지정
- 가장 가벼움, 권장 default

**Copied mode:**
- 프로젝트 저장 시 `sessions/SXXX/data/`로 복사
- 자체 완결, 이메일 송부 가능
- 비디오 파일은 보통 GB급이라 실용성 낮음 → flight log만 copy 권장

**Packed mode:**
- `copied` + 추가로 비디오를 `assets/` 폴더 (ZIP 외부)로 함께 패키징
- `.frsproj` 단일 파일이 아닌 `.frsproj-pack/` 폴더 형태
- 학회 발표·인계 시 사용

### 5.2 external_links.json 스키마

```json
{
  "links": [
    {
      "linkId": "L001",
      "sessionId": "S001",
      "channelIdx": 1,
      "kind": "flight_data",
      "absolutePath": "D:/data/flight_001.dat",
      "relativePath": "../data/flight_001.dat",
      "shallowHash": "sha256-shallow:ab12...",
      "lastVerifiedAt": "2026-05-08T16:00:00+09:00"
    },
    {
      "linkId": "L002",
      "sessionId": "S001",
      "channelIdx": 1,
      "kind": "video",
      "absolutePath": "D:/data/flight_001.avi",
      "relativePath": "../data/flight_001.avi",
      "shallowHash": "sha256-shallow:cd34...",
      "lastVerifiedAt": "2026-05-08T16:00:00+09:00"
    }
  ]
}
```

**경로 해석 우선순위:**
1. 상대경로 (프로젝트 폴더 기준)
2. 절대경로
3. 사용자 지정 다이얼로그 (둘 다 실패 시)

---

## 6. Save / Load 흐름

### 6.1 Save 흐름

```text
1. tempDir = tempname()
2. mkdir tempDir/sessions, tempDir/figures, tempDir/themes, tempDir/reports, tempDir/logs
3. for each session in project.Sessions:
       write session.json → tempDir/sessions/{id}/session.json
       write plots.json
       if packageMode == "copied" or "packed":
           copy raw flight file → tempDir/sessions/{id}/data/flight_raw.mat
       compute shallow hash → data_hash.txt
       for each result in session.Results:
           write R{N}.json → tempDir/sessions/{id}/results/
4. write project.json
5. write manifest.json (LAST 단계 — checksum 포함)
6. zip(tempDir, projectFilePath)
7. delete tempDir
```

### 6.2 Load 흐름

```text
1. unzip(projectFilePath, tempDir)
2. read manifest.json → schemaVersion check + migration chain
3. read project.json → ProjectModel 인스턴스 (메타만)
4. for each sessionId in manifest.sessions:
       read session.json → SessionModel (메타만, raw data 미로드)
       read plots.json  → PlotTabs 메타
5. external_links.json 검증 → 깨진 링크 사용자에게 알림
6. 활성 세션 결정 (마지막 활성 세션 또는 첫 번째)
7. activeSession.loadRawData() → matfile로 lazy access
8. UI 렌더링 시작
9. tempDir는 프로젝트 close 시 삭제 (또는 즉시 삭제 후 압축 안에서 직접 읽기)
```

### 6.3 Auto-save 정책

| 트리거 | 작업 |
|---|---|
| 세션 추가/삭제, 결과 생성/삭제 | 30초 후 dirty 플래그 → auto-save |
| 명시적 Ctrl+S | 즉시 save |
| Studio close | 변경 있을 시 사용자 confirm 다이얼로그 |
| 비정상 종료 | `~/.frsproj-recovery/` 백업 (Phase 9 후순위) |

---

## 7. 라이브러리 의존성

| 기능 | MATLAB 내장 함수 | 비고 |
|---|---|---|
| ZIP | `zip` / `unzip` | R2007+ 내장 |
| JSON | `jsonencode` / `jsondecode` | R2016b+ 내장 |
| MAT v7.3 | `save('-v7.3')` / `matfile` | R2006a+ |
| SHA-256 | `mlreportgen.utils.hash` 또는 `Simulink.getFileChecksum` | R2018b+, 또는 Java `MessageDigest` 폴백 |
| Temp folder | `tempname` | 내장 |

**외부 의존성 0** — 순수 MATLAB만으로 구현 가능.

---

## 8. 테스트 시나리오 (Phase 9 acceptance)

| # | 시나리오 | 기대 결과 |
|---|---|---|
| 1 | 빈 프로젝트 저장/로드 | 라운드트립 동등 |
| 2 | 세션 1개 + ROI 3개 + 분석 결과 2개 저장/로드 | 모든 메타 복원, dirty flag 보존 |
| 3 | linked mode → 외부 flight 파일 이동 | 로드 시 "파일 찾을 수 없음" 다이얼로그, 재지정 후 정상 |
| 4 | copied mode → 다른 PC에서 로드 | 절대경로 미존재해도 정상 로드 |
| 5 | schemaVersion v1 프로젝트를 v2 Studio에서 로드 | migrate 자동 실행 후 정상 |
| 6 | 50개 세션 프로젝트 로드 | 메타만 메모리, 활성 세션만 raw 로드 — 메모리 < 500MB |
| 7 | save 중 강제 종료 | tempDir 잔존, 다음 실행 시 정리 + 사용자에게 알림 |
| 8 | shallow hash 변경 감지 | 외부 파일 1바이트 수정 → dirty 표시 |
| 9 | 잘못된 schemaVersion (v999) | 명확한 에러 메시지 + 로드 거부 |
| 10 | 동시에 두 Studio가 같은 프로젝트 open 시도 | lock 파일로 두 번째 read-only mode |

---

## 9. Phase 2 / Phase 9 작업 분리

**Phase 2 (Project / Session Model 추가) — 모델 정의만:**
- `ProjectModel`, `SessionModel`, `FigureModel`, `ReviewResultModel`, `AnalysisThemeModel`을 value class로 정의
- `saveobj`/`loadobj` 메서드는 선택 (handle 채택 시)
- 직렬화 자체는 미구현 — 인메모리 동작만

**Phase 9 (Project Save / Load) — 본 문서 전체 구현:**
- `ProjectSerializer.m` 신설
- ZIP/JSON/MAT v7.3 read/write
- migration chain
- external_links 검증
- shallow hash
- auto-save

**Phase 2 → Phase 9 사이의 임시 동작:** 메모리상에서만 프로젝트 관리, 저장 미지원. 사용자에게 "프로젝트 저장은 다음 버전" 안내.

---

## 10. 결론

**핵심 결정:**
1. ZIP 컨테이너 + manifest.json + assets 구조
2. 메타는 JSON, raw data는 MAT v7.3 (HDF5 부분 로드)
3. shallow hash로 외부 파일 변경 감지 (5KB만 읽음)
4. linked / copied / packed 3가지 외부 자원 모드
5. SchemaVersion + migration chain으로 forward compatibility

**Phase 1 진입 전 결정 완료 항목:**
- ✅ 포맷 채택 (`.frsproj` ZIP)
- ✅ 메타 표현 (JSON)
- ✅ 대용량 데이터 표현 (MAT v7.3)
- ✅ Hash 전략 (shallow)
- ✅ 외부 자원 모드 (linked default)
- ✅ Schema versioning 정책

**Phase 2 진입 전 결정 필요 항목:** 없음 (본 문서가 충족)

**Phase 9 진입 전 결정 필요 항목:**
- 마이그레이션 함수 위치 패키지 (`+flightdash/+project/+migration/`)
- Auto-save 간격 사용자 설정 가능 여부
- Lock 파일 위치 (`<projectPath>.lock`)
