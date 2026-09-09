# Game Data Pipeline

기획/밸런스 데이터는 편집하기 쉬운 ODS로 관리하고, 게임 런타임에서는 CSV만 읽도록 데이터 제작 과정과 런타임 로딩을 분리했다.

## Structure

Private Repository
ProjectTOD_PrivateData
├─ GameDataManifest.json
└─ unpackGameData/
   └─ <category>/<Table>.ods
             │
             │ Manifest whitelist
             ▼
Public Repository
ProjectTOD/data/convertTools/ConvertGameData
             │
             │ LibreOffice headless export
             ▼
ProjectTOD/data/gameData/
└─ <category>/<Table>.csv
             │
             ▼
          CSVLoader
             │
             ▼
       GameDataManager

실제 ODS 원본은 Private Repository에서 공동 작업한다. 공개 저장소에는 런타임에 필요한 CSV, 변환 스크립트, Manifest 예시, 공개용 샘플만 포함한다.

## Design Points

- **원본/런타임 데이터 분리**: ODS는 제작용 원본, CSV는 게임이 사용하는 데이터로 역할을 구분한다.
- **Whitelist 변환**: Private Manifest에 등록한 ODS만 CSV로 생성한다.
- **경로 규칙 단순화**: ODS와 CSV는 동일한 상대 경로를 사용하고 확장자만 변경한다.
- **변경 감지**: SHA-256 캐시를 사용해 변경되지 않은 데이터는 변환하지 않는다.
- **CSV 규격 고정**: UTF-8, BOM 없음, LF 형식으로 결과를 정규화한다.
- **Godot Import 자동화**: 생성된 게임 데이터 CSV의 importer를 `keep`으로 자동 유지해 번역 리소스가 생성되지 않도록 한다.
- **런타임 독립성**: LibreOffice와 변환 스크립트는 개발 과정에서만 사용하며 게임 런타임은 CSVLoader와 GameDataManager에만 의존한다.

## Public Sample

`sample/`에는 실제 게임 데이터와 분리된 공개용 예제를 둔다.

sample/
├─ unpackGameData/
│  └─ defense/
│     └─ SampleDefenseSpawnTable.ods
└─ gameData/
   └─ defense/
      ├─ SampleDefenseSpawnTable.csv
      └─ SampleDefenseSpawnTable.csv.import

이 샘플은 실제 파이프라인과 동일하게 다음 대응 관계를 보여준다.

defense/SampleDefenseSpawnTable.ods
    -> defense/SampleDefenseSpawnTable.csv

실제 Private Manifest와 원본 데이터는 공개하지 않고, `data/convertTools/GameDataManifest.example.json`과 이 샘플을 통해 변환 규칙과 구조를 확인할 수 있다.

## Converter

구체적인 실행 방법과 변환 규칙은 [`data/convertTools/README.md`](../../data/convertTools/README.md)에 정리되어 있다.
