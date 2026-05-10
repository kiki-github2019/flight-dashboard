Origin Pro 그래픽 사용자 인터페이스(GUI)의 구조적 설계 및 데이터 분석 기능 고도화 연구
과학 데이터 분석 및 시각화 소프트웨어인 Origin Pro는 복잡한 수치 데이터를 정밀한 연구 결과물로 변환하기 위해 고도로 설계된 다층적 인터페이스를 제공한다.[1] 이 시스템의 핵심은 초보자부터 전문가까지 아우르는 유연한 작업 환경이며, 이는 단순한 그래프 작성 도구를 넘어 데이터 관리, 통계 분석, 그리고 자동화된 워크플로우를 통합하는 거대한 플랫폼으로서의 역할을 수행한다.[1] 본 보고서는 Origin Pro GUI의 주요 구성 요소와 그 기능적 메커니즘을 심층적으로 분석하여, 연구자가 데이터로부터 통찰을 도출하는 과정에서 인터페이스가 어떠한 전략적 가치를 제공하는지 고찰한다.
메인 워크스페이스의 기초 설계와 상태 정보 시스템
Origin Pro의 작업 공간은 다중 창 인터페이스(MDI) 구조를 기반으로 하며, 사용자가 프로젝트 파일(.OPJ 또는.OPJU) 내에서 수많은 데이터 창과 분석 결과물을 체계적으로 관리할 수 있도록 설계되었다.[2, 3] 인터페이스의 최상단에 위치한 제목 표시줄(Title Bar)은 현재 실행 중인 소프트웨어의 버전(Pro 여부 포함), 열려 있는 프로젝트의 명칭, 그리고 현재 작업 중인 폴더의 경로를 표시함으로써 사용자가 대규모 프로젝트 내에서 자신의 위치를 즉각적으로 파악하게 돕는다.[4] 이는 특히 수백 개의 폴더와 하위 창을 포함하는 복잡한 연구 프로젝트에서 데이터의 맥락을 잃지 않도록 하는 필수적인 시각적 이정표 역할을 한다.
작업 공간의 하단에 위치한 상태 표시줄(Status Bar)은 단순한 텍스트 표시 영역을 넘어 실시간 데이터 대시보드로서의 기능을 수행한다.[2, 4] 여기에는 소프트웨어의 핵심 진입점인 시작 메뉴(Start Menu)가 포함되어 있으며, 메시지 로그, 자동 업데이트(Auto Update)의 활성화 상태, 현재 활성화된 워크북 및 윈도우의 명칭, 그리고 각도 단위(Radian/Degree) 표시기가 배치되어 있다.[4] 특히 주목할 만한 기능은 사용자가 워크시트에서 특정 셀 범위를 선택했을 때 나타나는 요약 통계(Summary Statistics)이다.[4, 5] 상태 표시줄은 선택된 데이터의 평균, 합계, 개수 등을 실시간으로 계산하여 보여주며, 사용자는 마우스 오른쪽 버튼 클릭을 통해 표시할 통계 항목을 사용자 정의하거나 해당 수치를 탭(TAB) 구분 형식으로 복사하여 보고서 작성에 즉시 활용할 수 있다.[4]
구성 요소
주요 기능적 특성
관련 시스템 변수 및 단축키
제목 표시줄
프로젝트 이름, 폴더 경로, 창 관리 컨트롤 표시
해당 없음
상태 표시줄
요약 통계, 시작 메뉴, 각도 단위, 자동 업데이트 표시
ALT+S (사용자 정의 메뉴)
메시지 로그
작업 결과, 결과 보고, 오류 정보 출력
ALT+6
결과 로그
분석 알고리즘에 의해 생성된 수치 결과 영구 저장
ALT+2
자동 업데이트
데이터 변경 시 분석 결과의 실시간 동기화 상태 제어
상태 표시줄 아이콘 (AU)
데이터 컨테이너의 유형학: 하위 창(Child Windows)의 역할
Origin Pro의 인터페이스 내에서 모든 데이터와 결과물은 각기 다른 목적을 가진 하위 창에 저장된다. 이러한 창들은 독립적으로 존재하거나 프로젝트 탐색기를 통해 폴더 내에 조직화되며, 각각의 창 유형에 따라 상단 메뉴바의 구성이 동적으로 변화하는 '컨텍스트 기반 메뉴 시스템'을 취하고 있다.[4]
워크북(Workbook)과 데이터 조직화의 논리
워크북은 데이터의 수입, 정리, 변환 및 분석이 이루어지는 가장 기본적이면서도 강력한 도구이다.[2, 6] 하나의 워크북은 최대 1,024개의 시트를 포함할 수 있으며, 각 시트는 수천만 개의 행과 65,000개 이상의 열을 처리할 수 있는 방대한 수용력을 가진다.[2, 4, 6] 워크북 인터페이스의 핵심은 '열 지정(Column Designation)' 시스템이다.[4, 6] 각 열은 X, Y, Z, Y-Error, Label 등과 같은 특성을 부여받으며, 이는 이후 그래프 작성이나 분석 대화 상자에서 데이터가 어떻게 처리될지를 결정하는 메타데이터로 작용한다.[4, 6] 또한, 최근의 워크북은 단순한 수치 그리드를 넘어 그래프를 셀 내에 삽입하거나 부동(Floating) 형태로 시트 위에 배치할 수 있는 시각적 유연성을 제공하며, 복잡한 셀 단위 계산을 위해 MS Excel과 유사한 '스프레드시트 셀 표기법(SCN)'을 완벽하게 지원한다.[2, 6, 7]
행렬북(Matrixbook)의 수치 분석 특성
워크시트가 다양한 형태의 데이터 세트를 열 단위로 관리한다면, 행렬 시트는 XY 평면 상의 행과 열 인덱스에 의해 정의되는 단일 수치 데이터 세트(Z값)를 다루는 데 최적화되어 있다.[2] 행렬 창은 주로 3D 표면 플롯, 등고선 그래프 작성 및 복잡한 이미지 처리 작업에 사용된다.[2, 8] 하나의 행렬 시트는 여러 개의 '행렬 객체(Matrix Objects)'를 포함할 수 있으며, 이를 스택 형태로 관리함으로써 시간에 따른 온도 분포나 심도에 따른 지질 데이터와 같은 다차원 데이터를 효율적으로 관리할 수 있게 한다.[2]
그래프 윈도우(Graph Window)와 계층적 레이어 관리
그래프 창은 Origin Pro 시각화의 정점이며, 하나의 페이지 내에 하나 이상의 '레이어(Layer)'를 포함하는 구조를 가진다.[4, 9, 10] 레이어는 독립적인 축 세트와 데이터 플롯을 담는 기본 단위로, 한 페이지 내에 최대 1,024개까지 배치가 가능하다.[9, 10] 그래프 창은 100개 이상의 내장된 그래프 템플릿을 통해 즉각적인 고품질 시각화를 지원하며, 사용자는 '플롯 세부 사항(Plot Details)' 대화 상자를 통해 페이지, 레이어, 플롯 레벨에서 모든 시각적 요소를 정밀하게 제어할 수 있다.[1, 2, 11] 특히, 레이어 간의 링크 기능을 통해 부모 레이어의 축 스케일이 변경될 때 자식 레이어의 스케일이 자동으로 업데이트되도록 설정할 수 있어 다중 패널 그래프 작성 시의 일관성을 보장한다.[9, 12]
창 유형
주요 용도
최대 용량/특징
워크북
원본 데이터 저장, 통계 분석, 수식 계산
1,024 시트, SCN 지원
행렬북
3D 표면 데이터 관리, 이미지 처리
수치 데이터(Z) 전용
그래프
데이터 시각화, 프리젠테이션 품질 플롯
1,024 레이어, 템플릿 기반
이미지
래스터 이미지 및 비디오 편집/분석
.avi,.mov,.mp4 지원
노트
분석 프로시저 기록, 마크다운 보고서
Rich Text, HTML, MD
레이구아웃
여러 그래프/워크시트의 배판 구성
발표용 패널 제작
프로젝트 관리 및 객체 제어 시스템
연구 프로젝트가 비대해짐에 따라 발생하는 관리의 어려움을 극복하기 위해 Origin Pro는 프로젝트 탐색기와 객체 관리자라는 강력한 관리 도구를 GUI 우측과 좌측에 배치하고 있다.[3, 13]
프로젝트 탐색기(Project Explorer)의 구조적 이점
프로젝트 탐색기는 프로젝트 파일 내부의 모든 구성 요소를 폴더 트리 구조로 보여주는 도구이다.[3] 상단 패널은 폴더의 계층 구조를, 하단 패널은 선택된 폴더 내의 하위 창들을 나열한다.[2, 3] 사용자는 여기서 창의 이름을 변경하거나, 드래그 앤 드롭을 통해 폴더 간 창을 이동시키고, 특정 창을 숨기거나 표시하는 작업을 수행한다.[3] 특히 '찾기(Find)' 기능을 활용하면 전체 프로젝트에서 특정 키워드를 포함하는 창이나 노트를 신속하게 검색할 수 있으며, 2018년 버전 이후 도입된.OPJU 형식은 대규모 프로젝트의 파일 크기를 획기적으로 줄여주는 동시에 윈도우 탐색기에서도 그래프 썸네일 미리보기를 지원하여 데이터 탐색의 편의성을 높였다.[3, 14]
객체 관리자(Object Manager)를 통한 미시적 제어
객체 관리자는 현재 활성화된 창 내부의 구성 요소들을 트리 노드 형태로 보여주는 도킹 패널이다.[13] 그래프 창이 활성화된 경우, 모든 레이어, 플롯 그룹, 개별 데이터 플롯 및 텍스트 레이블이 표시된다.[13] 사용자는 여기서 특정 플롯의 체크박스를 해제하여 그래프에서 즉시 숨길 수 있으며, 여러 플롯을 선택하여 색상이나 선 굵기를 일괄 변경할 수 있다.[13, 15] 또한, 워크북이나 행렬북이 활성화된 상황에서는 포함된 모든 시트를 나열하여 수십 개의 탭 사이를 빠르게 전환하거나 관리할 수 있도록 돕는다.[6, 13] 이는 복잡한 다중 레이어 그래프를 다루는 연구자에게 직관적인 제어 환경을 제공하며, 그래프 상에서 직접 객체를 선택하기 어려운 경우에도 정확한 객체 타겟팅을 가능하게 한다.[2]
데이터 분석 프로세스와 대화 상자 인터페이스
Origin Pro의 분석 기능은 'X-Function' 프레임워크를 기반으로 하며, 이는 메뉴 구조와 분석 대화 상자를 통해 사용자에게 노출된다.[8, 16, 17] Analysis 및 Statistics 메뉴는 기능별로 체계적으로 분류되어 있으며, 사용자가 데이터를 워크시트에서 미리 선택했는지 혹은 그래프 상에서 활성 데이터 세트로 지정했는지에 따라 대화 상자의 입력 범위가 자동으로 설정되는 '지능형 입력 시스템'을 갖추고 있다.[8]
분석 대화 상자의 계층 구조
모든 분석 도구는 일관된 트리 구조의 대화 상자를 사용한다.[8, 16] 대화 상자의 상단에는 도구의 명칭과 간단한 설명이 위치하고, 중앙 영역에는 'Input Data', 'Settings', 'Output' 등으로 명명된 확장 가능한 노드들이 배치되어 매개변수 설정을 돕는다.[8, 16] 사용자는 여기서 'Rows' 컨트롤을 통해 전체 열이 아닌 특정 행 범위나 X값 범위를 분석 대상으로 한정할 수 있으며, 이 설정값들은 '대화 상자 테마(Dialog Theme)'로 저장되어 향후 동일한 분석을 수행할 때 클릭 한 번으로 모든 매개변수를 재현할 수 있게 한다.[8, 16, 18]
재계산(Recalculate) 매커니즘과 결과 무결성
Origin Pro 분석 GUI의 가장 큰 특징 중 하나는 분석 결과와 원본 데이터 사이의 동적 연계이다.[1, 8, 19] 분석이 수행되면 결과 워크시트나 그래프에 '녹색 자물쇠' 아이콘이 나타나는데, 이는 해당 결과가 재계산 모드에 있음을 의미한다.[8, 19] 만약 원본 데이터 시트의 수치가 변경되거나 실험 파일이 새로 수입되어 교체되면, 소프트웨어는 이를 감지하고 분석 수치와 관련 그래프를 자동으로 갱신한다.[1, 8, 19] 이는 반복적인 실험 데이터를 처리하는 연구 환경에서 분석 오류를 줄이고 워크플로우를 자동화하는 핵심적인 GUI 기능이다.[18, 19]
분석 범주
주요 메뉴 경로
대표 기능
수치 연산
Analysis: Mathematics
미분, 적분, 보간, 보외
곡선 피팅
Analysis: Fitting
선형/다항식 피팅, 비선형 곡선 피팅
신호 처리
Analysis: Signal Processing
평활화, 필터링, FFT, 웨이블릿 분석
기술 통계
Statistics: Descriptive Statistics
열/행 통계, 정규성 검정, 이상치 검출
가설 검정
Statistics: Hypothesis Testing
t-검정, 분산 검정, 비율 검정
다변량 분석
Statistics: Multivariate Analysis
PCA, 클러스터 분석, 판별 분석
최신 GUI 혁신: 통계 모드와 미니 도구 모음
Origin Pro는 버전 업그레이드를 통해 사용자의 인지 부하를 줄이고 편집 속도를 높이기 위한 새로운 인터페이스 요소를 지속적으로 도입하고 있다.[1, 20, 21]
통계 전용 GUI 모드(Stats Mode)
2025b 버전에서 도입된 '통계 모드'는 통계 분석을 주로 수행하는 사용자를 위해 설계된 역할 기반 인터페이스이다.[22, 23] 이 모드를 활성화하면 범용 그래프 도구 버튼과 복잡한 분석 도구가 숨겨지고, 인터페이스가 통계 기능 중심으로 재구성된다.[22, 23] 그래프 메뉴 역시 통계 그래프(Run Chart, CDF Plot, Main Effects Plot 등) 위주로 나열되어, 데이터의 통계적 유의성을 탐색하려는 사용자가 메뉴를 찾는 시간을 획기적으로 줄여준다.[22, 23] 사용자는 Preferences: GUI Mode 메뉴를 통해 기본 모드와 통계 모드 사이를 자유롭게 전환할 수 있다.[22, 23]
컨텍스트 기반 미니 도구 모음(Mini Toolbars)
미니 도구 모음은 사용자가 특정 객체를 선택했을 때 커서 근처에 즉시 나타나는 '페이드 인(Fade-in)' 형식의 부동 도구 모음이다.[1, 20, 24] 복잡한 대화 상자를 열지 않고도 플롯의 색상, 심볼 형태, 선 굵기, 축의 스케일 등을 신속하게 변경할 수 있도록 설계되었다.[7, 24]
지능적 도구 배치: 사용자가 클릭한 대상이 축(Axis)인지, 데이터 플롯인지, 혹은 텍스트 객체인지에 따라 제공되는 버튼의 종류가 실시간으로 달라진다.[24]
속성 복제 및 전파: 미니 도구 모음을 통해 하나의 그래프 레이어에서 설정한 스타일을 다른 레이어나 프로젝트 내의 다른 그래프에 즉시 적용할 수 있는 'Common Display' 기능에 대한 접근도 가능하다.[24, 25]
상호작용 유지: 도구 모음이 사라졌을 때 Shift 키를 누르면 마지막으로 사용했던 미니 도구 모음이 다시 나타나 연속적인 작업을 지원한다.[24, 26]
확장성 및 커스터마이징 시스템
Origin Pro의 GUI는 사용자의 특정 요구에 맞춰 무한히 확장될 수 있는 유연성을 갖추고 있다. 이는 앱 센터와 사용자 정의 메뉴 시스템을 통해 실현된다.[27, 28]
앱 센터(App Center)와 앱 갤러리(Apps Gallery)
앱은 Origin Pro에 새로운 그래프 유형이나 분석 알고리즘을 추가할 수 있는 독립적인 소프트웨어 모듈이다.[27] 사용자는 앱 센터(F10)를 통해 OriginLab File Exchange에 업로드된 125개 이상의 앱을 검색하고 설치할 수 있다.[27, 29] 설치된 앱은 인터페이스 우측의 앱 갤러리에 아이콘으로 표시되며, 새로운 버전이 출시되면 빨간색 알림 점을 통해 사용자에게 업데이트를 알린다.[27, 30] 이를 통해 사용자는 소프트웨어의 전체 업데이트를 기다리지 않고도 최신 분석 트렌드(예: 기계 학습, 고급 통계 프로세스 제어)를 작업 공간에 즉시 통합할 수 있다.[22, 29, 31]
사용자 정의 도구 모음 및 메뉴 구성
사용자는 Alt 키를 누른 상태에서 도구 모음의 버튼을 드래그하여 위치를 자유롭게 변경하거나, 불필요한 버튼을 제거하여 자신만의 최적화된 도구 모음을 구성할 수 있다.[28] 또한, '사용자 정의 메뉴 구성기(Custom Menu Organizer)'를 활용하면 자주 사용하는 LabTalk 스크립트나 X-Function을 메인 메뉴에 직접 추가하여 전용 워크플로우 메뉴를 생성할 수 있다.[19, 28] 이는 연구실 내에서 공통적으로 사용하는 분석 프로토콜을 표준화하여 배포할 때 매우 유용하다.[28]
프로그래밍 인터페이스와 하이 레벨 제어
GUI의 시각적 편의성 이면에는 코드 기반으로 소프트웨어를 제어할 수 있는 강력한 프로그래밍 인터페이스가 존재한다.[17, 32, 33]
명령 창(Command Window)과 스크립트 창(Script Window)
명령 창은 LabTalk 스크립트를 직접 입력하고 실행하는 현대적인 인터페이스이다.[17, 33] 자동 완성 기능을 통해 X-Function의 매개변수를 신속하게 입력할 수 있으며, 이전에 실행한 명령들을 기록(History) 패널에서 관리하여 반복 작업을 지원한다.[17, 33] 반면 스크립트 창은 간단한 수식 계산이나 단일 행 스크립트 실행에 최적화된 경량 인터페이스로 제공된다.[33, 34]
코드 빌더(Code Builder)와 Python 연동
코드 빌더는 Origin Pro 내부에 내장된 통합 개발 환경(IDE)으로, Origin C 및 Python 코드를 작성, 디버깅 및 컴파일하는 데 사용된다.[2, 4] Alt+4 단축키로 호출되는 이 인터페이스는 외부 하드웨어와의 통신, 사용자 정의 피팅 함수 제작, 또는 복잡한 데이터 처리 알고리즘의 구현을 가능하게 한다.[2, 26, 32] 특히 최근 버전에서는 Python 콘솔을 통해 originpro 라이브러리를 활용함으로써, GUI 내의 데이터를 Python의 방대한 과학 라이브러리(Pandas, SciPy 등)와 실시간으로 교환할 수 있는 환경을 구축하였다.[1, 7, 26]
사용자 지원 및 학습 리소스 인터페이스
Origin Pro는 사용자 수준에 관계없이 소프트웨어의 잠재력을 최대한 활용할 수 있도록 돕는 학습 보조 도구들을 GUI 내에 통합하고 있다.[35]
학습 센터(Learning Center)의 활용
F11 키를 통해 열리는 학습 센터는 수백 개의 그래프 샘플과 분석 프로젝트를 테마별로 제공한다.[4, 35] 사용자는 자신이 원하는 스타일의 그래프 샘플을 더블 클릭하여 프로젝트를 열 수 있으며, 해당 그래프가 어떠한 데이터 구조와 레이어 설정으로 구성되었는지 직접 파헤쳐 볼 수 있다.[35, 36] 샘플에 포함된 'Recreate' 노트를 읽거나 자신의 데이터를 샘플 시트에 붙여넣어 즉시 결과를 확인하는 방식은 새로운 분석 기법을 익히는 데 매우 효과적인 GUI 기반 학습 경로이다.[35]
메시지 및 결과 로그 시스템
메시지 로그(ALT+6)는 그래프 수출 결과나 데이터 수입 성공 여부 등 시스템의 모든 활동을 기록하며, 결과 로그(ALT+2)는 곡선 피팅의 파라미터 값이나 통계 테스트의 p-value와 같은 핵심 수치 결과들을 프로젝트와 별개로 혹은 함께 저장한다.[2, 4, 26] 이러한 로그 창들은 분석 과정에서 발생하는 중요한 정보들을 놓치지 않게 하며, 나중에 분석 과정을 역추적하거나 검증할 때 결정적인 근거를 제공한다.[2, 4]
결론: 통합적 인터페이스 활용 전략
Origin Pro의 GUI 구성 요소들을 종합적으로 고찰한 결과, 이 소프트웨어는 데이터의 '계층적 시각화'와 '작업의 연속성'을 극대화하도록 설계되었음을 알 수 있다. 연구자는 프로젝트 탐색기를 통해 거시적인 데이터 구조를 잡고, 객체 관리자와 미니 도구 모음을 통해 미시적인 편집을 수행하며, X-Function 기반의 분석 대화 상자와 재계산 메커니즘을 통해 데이터의 신뢰성을 확보하는 워크플로우를 구축할 수 있다.[1, 3, 18, 24]
특히 2025b 버전에서 선보인 통계 모드와 코드 단축키(Key Chords) 시스템은 인터페이스의 복잡성을 관리 가능한 수준으로 낮추는 동시에 전문가의 작업 속도를 높이려는 혁신적인 시도로 평가된다.[20, 22, 37] 연구 과정의 효율성을 극대화하기 위해서는 단순히 메뉴를 클릭하는 수준을 넘어, 앱 갤러리를 통한 기능 확장, 대화 상자 테마를 활용한 분석 표준화, 그리고 프로젝트 탐색기의 폴더 노트를 활용한 지식 관리 기법을 병행하는 것이 권장된다.[3, 18, 27] 이러한 GUI의 구조적 특성을 깊이 이해하고 활용하는 것은 과학적 발견의 속도와 데이터 전달의 명확성을 비약적으로 향상시키는 결정적인 요인이 될 것이다.
--------------------------------------------------------------------------------
[1] OriginLab. (n.d.). Data Analysis and Graphing Software. https://www.originlab.com/origin
[2] OriginLab. (n.d.). Help Online - User Guide - The Origin Interface. https://www.originlab.com/doc/User-Guide/Origin-Interface
[3] OriginLab. (n.d.). 2.1.2 Project Explorer. https://www.originlab.com/doc/Origin-Help/Project-Explorer
[4] OriginLab. (n.d.). Help Online - Tutorials - Origin GUI. https://www.originlab.com/doc/Tutorials/Origin-GUI
[5] OriginLab. (n.d.). 1.10 Statistics. https://www.originlab.com/doc/Tutorials/GSB-statistics
[6] OriginLab. (n.d.). 8 Workbooks Worksheets Columns. https://www.originlab.com/doc/User-Guide/Worksheets-Columns
[7] OriginLab. (2021). Origin 2021 Feature Highlights. https://www.originlab.com/2021
[8] OriginLab. (n.d.). 14 Data Analysis. https://www.originlab.com/doc/User-Guide/Data-Analysis
[9] OriginLab. (n.d.). Plotting: Graph Layers [PDF]. https://www.originlab.com/pdfs/9_Layers.pdf
[10] OriginLab. (n.d.). Origin Help - Basic Graph Window Operations. https://www.originlab.com/doc/Origin-Help/GraphWindow-Operation
[11] OriginLab. (n.d.). Plotting: Customizing the Graph [PDF]. https://www.originlab.com/pdfs/11_customizegraph.pdf
[12] OriginLab. (n.d.). Help Online - Tutorials - Multi Layer Graph Customization. https://www.originlab.com/doc/Tutorials/MultiLayer-Graph-Customization
[13] OriginLab. (n.d.). 2.1.7 Object Manager. https://www.originlab.com/doc/Origin-Help/Object-Manager
[14] OriginLab. (2018). Origin 2018 Feature Highlights. https://www.originlab.com/2018
[15] OriginLab. (2021, October 29). Easier Graph Customization with Object Manager in Origin 2022 [Video]. YouTube. https://www.youtube.com/watch?v=MjgqiWDDwtk
[16] OriginLab. (n.d.). 12.2 Origins Analysis Dialog Boxes. https://www.originlab.com/doc/Origin-Help/Analysis-Dialog
[17] OriginLab. (n.d.). Help Online - Tutorials - Command Window and X-Functions. https://www.originlab.com/doc/Tutorials/Command-Window
[18] OriginLab. (n.d.). Handling Repetitive Tasks. https://www.originlab.com/index.aspx?go=Products/Origin/HandlingRepetitiveTasks
[19] OriginLab. (n.d.). Customization and Automation - Origin Help. https://www.originlab.com/doc/Origin-Help/Customization-Automation
[20] OriginLab. (2025). Origin 2025b Feature Highlights. https://www.originlab.com/2025b
[21] OriginLab. (2021, May 11). Origin and OriginPro 2021b Highlights [Video]. YouTube. https://www.youtube.com/watch?v=bOueP-YutMg
[22] OriginLab. (2025). Enhanced Quality Improvement and Stats Features in OriginPro 2025b SR1. OriginLab Blog. https://blog.originlab.com/enhanced-quality-improvement-and-stats-features-in-originpro-2025b-sr1
[23] OriginLab. (n.d.). 2.8 Stats Mode. https://www.originlab.com/doc/Origin-Help/Stats-Mode
[24] OriginLab. (n.d.). 11 Customizing Graphs. https://www.originlab.com/doc/User-Guide/Customizing-Graphs
[25] OriginLab. (n.d.). Origin Help - The (Plot Details) Layers Tab. https://www.originlab.com/doc/Origin-Help/PD-Dialog-Layers-Tab
[26] OriginLab. (n.d.). 2.4.1 Hotkeys/Accelerator Keys/Keyboard Shortcuts in Origin. https://www.originlab.com/doc/Origin-Help/HotKey-in-Origin
[27] OriginLab. (n.d.). Apps Gallery - Origin Help. https://www.originlab.com/doc/Origin-Help/Apps-on-File-Exchange
[28] OriginLab. (n.d.). Help Online - User Guide - Customizing Origin. https://www.originlab.com/doc/User-Guide/Customizing-Origin
[29] OriginLab. (n.d.). Origin Apps. https://www.originlab.com/apps
[30] OriginLab. (n.d.). 18 Apps for Origin. https://www.originlab.com/doc/User-Guide/Apps
[31] OriginLab. (n.d.). Statistics. https://www.originlab.com/index.aspx?go=Products/Origin/Statistics
[32] OriginLab. (n.d.). Program custom graphing and analysis routines in Origin. https://www.originlab.com/index.aspx?go=Products/Origin/Programming
[33] OriginLab. (n.d.). 2.1.14 The Origin Command Window and Script Window. https://www.originlab.com/doc/Origin-Help/CmdWindow
[34] OriginLab. (n.d.). 5.1 Get Started with LabTalk. https://www.originlab.com/doc/LabTalk/Tutorials/Tutorial-Get-Started
[35] OriginLab. (n.d.). Origin Help - Learning Center. https://www.originlab.com/doc/Origin-Help/Origin-Central
[36] OriginLab. (n.d.). Key Features by Version. https://www.originlab.com/VersionComparison
[37] OriginLab. (n.d.). Origin Help - Custom Chorded Keys. https://www.originlab.com/doc/Origin-Help/Custom-Chorded-Keys