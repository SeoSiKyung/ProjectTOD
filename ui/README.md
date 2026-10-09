# UI 규칙

`res://ui/`는 프로젝트 UI의 공통 스타일과 화면별 UI 컴포넌트를 관리한다.

## 폴더 역할

```text
ui/
├─ theme/                 # 전역 Theme, ThemeManager, 폰트
├─ common/                # 특정 게임 도메인을 모르는 공용 UI
│  ├─ buttons/
│  └─ parchment/          # 양피지 프레임/배지/게이지 같은 조립식 부품
├─ defense/
│  ├─ deployment/         # 유닛/병기/함정/용병 배치 UI
│  ├─ hud/                # 디펜스 전투 HUD
│  └─ result/             # 디펜스 결과 UI
├─ tycoon/                # 타이쿤 전용 UI
└─ event/                 # 이벤트 팝업 UI
```

- `common`: Defense, Tycoon 같은 게임 도메인 데이터를 몰라도 재사용할 수 있는 UI만 둔다.
- 도메인 데이터를 직접 사용하는 UI는 해당 도메인 폴더에 둔다.
- 디펜스 화면 UI는 `DefenseDeploymentView`, `DefenseBattleHUDView`, `DefenseResultView`처럼 화면 단위 `Control` View로 분리한다.
- 이미지 에셋은 `res://assets/picture/`에 두고, UI 전용 이미지는 `res://assets/picture/ui/` 아래에서 관리한다.

## Theme 책임

`ui.tres`는 모든 컴포넌트의 세부 디자인을 모아두는 카탈로그가 아니다. 전역 폰트와 정말 반복되는 기본 텍스트 규칙만 관리한다.

현재 양피지 계열 Theme Type Variation은 다음 세 가지를 기본으로 한다.

```text
ParchmentTitleLabel  # 큰 제목/섹션 제목
ParchmentLabel       # 일반 본문/값
ParchmentSmallLabel  # 보조 설명/작은 스탯
```

카드 이름, 영웅 이름, 카운트, 힌트처럼 특정 컴포넌트에서만 필요한 차이는 새 Theme Type을 만들지 않고 해당 `.tscn` 또는 `.gd`에서 font size/color override로 표현한다.

- `theme/ThemeManager.gd`: 언어 변경과 언어별 전역 폰트 전환만 담당한다.
- `theme/ui.tres`: 전역 폰트, 기본 Button/Label, 최소한의 공통 텍스트 variation을 담당한다.
- 공용 컴포넌트 `.tscn`: 양피지 프레임, 버튼, 배지, 게이지의 실제 시각 구조를 담당한다.
- 화면별 `.tscn`: 화면 배치와 화면 특유의 margin/spacing을 담당한다.
- 화면별 `.gd`: 상태와 데이터 갱신을 담당한다.

## 조립식 양피지 컴포넌트

양피지 UI는 Theme Type을 계속 추가하는 대신 아래 공용 씬을 조립해서 만든다.

- `ParchmentFrame.tscn`: 버튼/카드처럼 상태 표현이 필요한 곳에서 쓰는 저수준 양피지 비주얼이다.
- `ParchmentPanel`: `class_name`으로 등록된 공용 Container 타입이다. 노드 추가 창에서 바로 생성할 수 있고, 양피지 비주얼과 콘텐츠 안전 마진을 자동으로 제공한다.
- `ParchmentSelectableCard.tscn`: 선택/비활성화 상태와 클릭·드래그 입력을 공통 처리하는 양피지 카드 기반 씬이다.
- `BasicButton.tscn`: `ParchmentFrame` 위에 투명 Button을 얹은 공용 액션 버튼이다.
- `ParchmentBadge.tscn`: 작은 상태/태그 표시용 배지다.
- `ParchmentProgressBar.tscn`: 전투 HUD 등의 HP/MP 게이지용 공용 진행 바다.

새 UI를 만들 때 `BattleHUDPauseButton`, `MercenaryStatusLabel` 같은 전용 Theme Type을 추가하지 않는다. 구조가 필요한 경우 공용 컴포넌트를 만들고, 단순한 크기/색 차이는 해당 컴포넌트에서 override한다.

일반적인 양피지 패널은 `ParchmentPanel` 노드를 추가하고 그 바로 아래에 `VBoxContainer`, `HBoxContainer` 같은 콘텐츠 루트 하나를 넣는다. 기본 안전 마진은 좌우 16, 상하 14이며, 화면 특성에 따라 `contentMarginLeft/Top/Right/Bottom`만 Inspector에서 override한다. `Editable Children`이나 별도 `MarginContainer`는 필요하지 않다.

## 간격

특별한 이유가 없다면 다음 단위 안에서 선택한다.

```text
4  = XS
8  = S
12 = M
16 = L
24 = XL
32 = XXL
```

## 디펜스 UI 디자인

디펜스 UI는 따뜻한 베이지 양피지, 짙은 갈색 글자/테두리, 선택 상태의 황금빛 강조를 공통 디자인 언어로 사용한다.

- 배치 상단 HUD: 현재 배치 단계, 핵심 요약, `1 / 3` 단계 표시를 보여준다.
- 배치 하단 Dock: 선택 카드, 단계별 설정/안내, 이전/확정 액션을 한 양피지 패널에 배치한다.
- 전투 HUD: 양피지 패널 안에서 시간, 일시정지, 지휘소 HP/MP, 병력 현황을 보여준다.
- 결과 화면: 화면을 어둡게 덮고 중앙 양피지 결과 패널을 표시한다.
- 월드 배치 Grid: 네온색 대신 금빛/갈색 계열 강조를 사용하고, 배치 인구 라벨에는 외곽선을 넣어 맵 위 가독성을 확보한다.

## 디펜스 배치 UX

디펜스 배치는 셀 옆 팝업 대신 화면 하단의 `DefenseDeploymentDock`을 사용한다.

- 카드 클릭 후 배치 가능한 셀을 좌클릭하면 즉시 배치한다.
- 카드를 전장 셀까지 드래그해서 놓는 방식도 같은 동작으로 지원한다.
- 우클릭은 해당 셀의 배치/할당을 회수한다.
- TOWER 배치 단계에서는 Dock에서 징집 비율과 실제 배치 인구를 함께 설정한다.
- MACHINE/TRAP은 처음부터 보유 수량이 0이면 카드 자체를 만들지 않는다.
- 배치 중 잔여 수량이 0이 된 카드는 유지하되 비활성화하고, 회수 시 다시 활성화한다.
- 선택한 카드가 있을 때 배치 가능한 셀을 강조하고 hover 셀에는 반투명 preview를 표시한다.

드래그는 빠른 보조 입력이며, 모든 배치 기능은 클릭만으로도 수행할 수 있어야 한다.
