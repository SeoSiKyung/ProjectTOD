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
- 이미지 에셋은 `res://assets/picture/`에 두고, UI 전용 이미지는 `res://assets/picture/ui/` 아래에서 관리한다.

## Theme 책임

- `theme/ThemeManager.gd`: 언어 변경과 언어별 전역 폰트 전환만 담당한다.
- `theme/ui.tres`: 공통 폰트 크기, 텍스트 색, Button 상태 스타일, Theme Type Variation을 관리한다.
- 개별 `.tscn`: 화면 배치, 컴포넌트 크기, 화면 특유의 margin을 담당한다.
- 개별 `.gd`: 상태와 데이터 처리에 집중하고 공통 색상/폰트 크기를 하드코딩하지 않는다.

## 폰트 크기

| 용도 | 크기 | Theme Type Variation |
| --- | ---: | --- |
| 큰 제목 | 32 | `TitleLabel` |
| 섹션 제목 | 24 | `HeadingLabel` |
| 카드 이름 | 22 | `CardTitleLabel` |
| 일반 텍스트 | 20 | 기본값 |
| 작은 정보 / 스탯 | 16 | `SmallLabel` |
| 헤더 / 보조 정보 | 14 | `CaptionLabel` |

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

## 선택형 카드

선택 가능한 카드형 Button은 `SelectableCardButton` Theme Type Variation을 사용한다.

- 기본: 어두운 배경 + 얇은 테두리
- Hover: 배경과 테두리를 조금 밝게
- Selected/Pressed: 밝은 2px 테두리
- Hero: 선택 상태와 분리하여 이름만 `HeroCardTitleLabel`로 강조
- Disabled: 전역 `Button` disabled 스타일 사용

`선택됨`과 `주인공`은 서로 다른 의미이므로 같은 강조 색을 사용하지 않는다.

## Button 구분

- `Button`: 일반적인 게임 UI 액션 버튼. `ui.tres`의 공통 Button 스타일을 따른다.
- `SelectableCardButton`: 유닛/용병/병기/함정 등 선택형 카드.
- `BasicButton`: 양피지 비주얼을 사용하는 특수 공용 버튼. 자체 이미지/상태 표현을 유지한다.

## 양피지 UI

중세풍 양피지 비주얼은 `ui/common/parchment/ParchmentFrame.tscn`을 공통 기반으로 사용한다.

- `ParchmentFrame`: 양피지 질감, 갈색 테두리, hover/pressed/selected/disabled 상태 표현을 담당한다.
- `BasicButton`: `ParchmentFrame` 위에 실제 입력 Button을 얹은 공용 액션 버튼이다.
- `ParchmentCardButton`: 양피지 카드 위에서 사용하는 투명 선택 Button Theme Variation이다.
- `ParchmentPanel`: `ParchmentFrame`을 배경으로 사용하는 PanelContainer의 기본 패널을 투명하게 만든다.
- `ParchmentLabel`, `ParchmentCardTitleLabel`, `ParchmentLargeCardTitleLabel`, `ParchmentHeroCardTitleLabel`, `ParchmentSmallLabel`, `ParchmentCaptionLabel`, `ParchmentCountLabel`: 양피지 위의 짙은 갈색 텍스트 규칙이다.

양피지 카드의 선택 상태는 밝은 황금빛 테두리로 표현한다. 카드의 실제 입력 영역은 투명 Button이 담당하고, 시각 상태는 `ParchmentFrame`이 담당한다.
