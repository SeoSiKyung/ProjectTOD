# Game Data Convert Tools

게임 데이터 원본 ODS를 런타임용 CSV로 변환하는 개발 도구다.
실제 ODS 원본과 Manifest는 별도의 Private Repository에서 관리하고, 공개 저장소에는 변환 도구와 Manifest 예시만 둔다.

## Repository Structure

TOD/
├─ ProjectTOD/
│  └─ data/
│     ├─ gameData/                  # 런타임에서 사용하는 CSV
│     └─ convertTools/
│        ├─ ConvertGameData.bat
│        ├─ ConvertGameData.ps1
│        └─ GameDataManifest.example.json
│
└─ ProjectTOD_PrivateData/
   ├─ GameDataManifest.json
   └─ unpackGameData/               # ODS 원본

## Pipeline

ProjectTOD_PrivateData/unpackGameData/*.ods
                    │
                    │ GameDataManifest.json whitelist
                    ▼
             ConvertGameData
                    │
                    ▼
ProjectTOD/data/gameData/*.csv
                    │
                    ▼
                 CSVLoader
                    │
                    ▼
              GameDataManager

Manifest에 등록된 ODS만 변환한다.
ODS와 CSV는 동일한 상대 경로를 사용하며 확장자만 `.ods`에서 `.csv`로 변경된다.


## Conversion Rules

변환된 CSV는 다음 형식으로 정규화한다.

- UTF-8
- BOM 없음
- LF 줄바꿈
- CSV 구분자 `,`

ODS와 출력 CSV의 SHA-256 해시를 캐시에 저장해 변경이 없으면 변환을 생략한다. ODS가 변경되거나 CSV가 삭제/수정되면 다시 변환한다.

## Usage

Private Repository의 `GameDataManifest.json`에 변환할 ODS를 등록한 뒤 다음 파일을 실행한다.

data/convertTools/ConvertGameData.bat

실제 `GameDataManifest.json`, ODS 원본, 변환 캐시는 Private Repository에서 관리한다. 공개 저장소의 `GameDataManifest.example.json`은 Manifest 형식 확인용이다.
