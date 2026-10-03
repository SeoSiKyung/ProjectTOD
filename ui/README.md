# UI 규칙

`res://ui/`는 프로젝트 UI의 공통 스타일과 화면별 UI 컴포넌트를 관리한다.

## 폴더 역할

```text
ui/
├─ theme/                 # 전역 Theme, ThemeManager, 폰트
├─ common/                # 특정 게임 도메인을 모르는 공용 UI
│  └─ buttons/
├─ defense/
│  ├─ deployment/         # 유닛/병기/함정/용병 배치 UI
│  ├─ hud/                # 디펜스 전투 HUD
│  └─ result/             # 디펜스 결과 UI
├─ tycoon/                # 타이쿤 전용 UI
└─ event/                 # 이벤트 팝업 UI
```

- `common`: Defense, Tycoon 같은 게임 도메인 데이터를 몰라도 재사용할 수 있는 UI만 둔다.
- 도메인 데이터를 직접 사용하는 UI는 해당 도메인 폴더에 둔다.
- 디펜스 화면 UI는 `DefenseDeploymentView`, `DefenseBattleHUDView`, `DefenseResultView`처럼 화면 단위 `Control` View로 분리하고, `DefenseScene`은 게임 흐름과 배치 규칙 조율에 집중한다.
- 이미지 에셋은 `res://assets/picture/`에 두고, UI 전용 이미지는 `res://assets/picture/ui/` 아래에서 관리한다.

## Theme 책임

- `theme/ThemeManager.gd`: 언어 변경과 언어별 전역 폰트 전환만 담당한다.
- `theme/ui.tres`: 공통 폰트 크기, 텍스트 색, Button 상태 스타일, Theme Type Variation을 관리한다.
- 개별 `.tscn`: 화면 배치, 컴포넌트 크기, 화면 특유의 margin을 담당한다.
- 개별 `.gd`: 상태와 데이터 처리에 집중하고 공통 색상/폰트 크기를 하드코딩하지 않는다.

## 폰트 크기

| 용도             | 크기 | Theme Type Variation |
| ---------------- | ---: | -------------------- |
| 큰 제목          |   32 | `TitleLabel`         |
| 섹션 제목        |   24 | `HeadingLabel`       |
| 카드 이름        |   22 | `CardTitleLabel`     |
| 일반 텍스트      |   20 | 기본값               |
| 작은 정보 / 스탯 |   16 | `SmallLabel`         |
| 헤더 / 보조 정보 |   14 | `CaptionLabel`       |

주인공 카드 이름은 `HeroCardTitleLabel`을 사용한다.

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

## Button 구분

- `Button`: 일반적인 게임 UI 액션 버튼. `ui.tres`의 공통 Button 스타일을 따른다.
- `BasicButton`: 양피지 비주얼을 사용하는 특수 공용 버튼. 자체 이미지/상태 표현을 유지한다.

## 양피지 UI

중세풍 양피지 비주얼은 `ui/common/parchment/ParchmentFrame.tscn`을 공통 기반으로 사용한다.

- `ParchmentFrame`: 양피지 질감, 갈색 테두리, hover/pressed/selected/disabled 상태 표현을 담당한다.
- `BasicButton`: `ParchmentFrame` 위에 실제 입력 Button을 얹은 공용 액션 버튼이다.
- `ParchmentCardButton`: 양피지 카드 위에서 사용하는 투명 선택 Button Theme Variation이다.
- `ParchmentPanel`: `ParchmentFrame`을 배경으로 사용하는 PanelContainer의 기본 패널을 투명하게 만든다.
- `ParchmentLabel`, `ParchmentCardTitleLabel`, `ParchmentLargeCardTitleLabel`, `ParchmentHeroCardTitleLabel`, `ParchmentSmallLabel`, `ParchmentCaptionLabel`, `ParchmentCountLabel`: 양피지 위의 짙은 갈색 텍스트 규칙이다.

양피지 카드의 선택 상태는 밝은 황금빛 테두리로 표현한다. 카드의 실제 입력 영역은 투명 Button이 담당하고, 시각 상태는 `ParchmentFrame`이 담당한다.

## 디펜스 배치 UX

디펜스 배치는 셀 옆 팝업 대신 화면 하단의 `DefenseDeploymentDock`을 사용한다.

- 카드 클릭 후 배치 가능한 셀을 좌클릭하면 즉시 배치한다.
- 카드를 전장 셀까지 드래그해서 놓는 방식도 같은 동작으로 지원한다.
- 우클릭은 해당 셀의 배치/할당을 회수한다.
- UNIT 단계에서는 Dock에서 징집 비율과 실제 배치 인구를 함께 설정한다.
- MACHINE/TRAP은 처음부터 보유 수량이 0이면 카드 자체를 만들지 않는다.
- 배치 중 잔여 수량이 0이 된 카드는 유지하되 비활성화하고, 회수 시 다시 활성화한다.
- 선택한 카드가 있을 때 배치 가능한 셀을 강조하고 hover 셀에는 반투명 preview를 표시한다.

드래그는 빠른 보조 입력이며, 모든 배치 기능은 클릭만으로도 수행할 수 있어야 한다.
