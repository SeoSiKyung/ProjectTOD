$ErrorActionPreference = "Stop"


# ----------------------------------------
# Paths
# ----------------------------------------

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$workspaceRoot = Split-Path $projectRoot -Parent

$privateRepoRoot = Join-Path $workspaceRoot "ProjectTOD_PrivateData"

$manifestPath = Join-Path `
    $privateRepoRoot `
    "GameDataManifest.json"

$cachePath = Join-Path `
    $privateRepoRoot `
    ".GameDataConvertCache.json"

$unpackDataRoot = Join-Path `
    $privateRepoRoot `
    "unpackGameData"

$gameDataRoot = Join-Path `
    $projectRoot `
    "data\gameData"

$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)


$normalizedUnpackDataRoot =
    [System.IO.Path]::GetFullPath($unpackDataRoot).TrimEnd(
        [char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
    ) + [System.IO.Path]::DirectorySeparatorChar

$normalizedGameDataRoot =
    [System.IO.Path]::GetFullPath($gameDataRoot).TrimEnd(
        [char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
    ) + [System.IO.Path]::DirectorySeparatorChar


# ----------------------------------------
# Functions
# ----------------------------------------

function Ensure-GodotKeepImport {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CsvPath
    )

    $importPath = "$CsvPath.import"
    $importContent = "[remap]`n`nimporter=`"keep`"`n"

    if (Test-Path $importPath -PathType Leaf) {
        $currentContent = [System.IO.File]::ReadAllText($importPath)
        $currentContent = $currentContent `
            -replace "`r`n", "`n" `
            -replace "`r", "`n"

        if ($currentContent -eq $importContent) {
            return $false
        }
    }

    [System.IO.File]::WriteAllText(
        $importPath,
        $importContent,
        $utf8WithoutBom
    )

    return $true
}


# ----------------------------------------
# Manifest
# ----------------------------------------

if (-not (Test-Path $manifestPath -PathType Leaf)) {
    throw "GameDataManifest.json not found: $manifestPath"
}

$manifest = Get-Content `
    $manifestPath `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json

$targets = @($manifest.targets)

if ($targets.Count -eq 0) {
    throw "No targets found in GameDataManifest.json"
}


# ----------------------------------------
# Normalize Manifest Targets
# ----------------------------------------

$normalizedTargets = @()

foreach ($target in $targets) {
    if ($null -eq $target) {
        $normalizedTargets += $target
        continue
    }

    $normalizedTargets += $target.ToString().Replace("\", "/")
}

$targets = $normalizedTargets


# ----------------------------------------
# Duplicate Check
# ----------------------------------------

$duplicateTargets = $targets |
    Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    } |
    Group-Object |
    Where-Object {
        $_.Count -gt 1
    }

if (@($duplicateTargets).Count -gt 0) {
    $duplicateNames = @($duplicateTargets.Name) -join ", "

    throw "Duplicate targets found in manifest: $duplicateNames"
}


# ----------------------------------------
# Cache
# ----------------------------------------

$cache = @{}

if (Test-Path $cachePath -PathType Leaf) {
    $cacheJson = Get-Content `
        $cachePath `
        -Raw `
        -Encoding UTF8 |
        ConvertFrom-Json

    foreach ($entry in @($cacheJson.entries)) {
        if ($null -eq $entry.target) {
            continue
        }

        $targetKey = $entry.target.ToString().Replace("\", "/")

        $cache[$targetKey] = @{
            sourceHash      = $entry.sourceHash
            destinationHash = $entry.destinationHash
        }
    }
}


# ----------------------------------------
# LibreOffice
# ----------------------------------------

$libreOfficeCandidates = @(
    (Join-Path $env:ProgramFiles "LibreOffice\program\soffice.com"),
    (Join-Path $env:ProgramFiles "LibreOffice\program\soffice.exe")
)

if (${env:ProgramFiles(x86)}) {
    $libreOfficeCandidates +=
        (Join-Path ${env:ProgramFiles(x86)} "LibreOffice\program\soffice.com")

    $libreOfficeCandidates +=
        (Join-Path ${env:ProgramFiles(x86)} "LibreOffice\program\soffice.exe")
}

$libreOfficePath = $libreOfficeCandidates |
    Where-Object {
        Test-Path $_ -PathType Leaf
    } |
    Select-Object -First 1


if ($null -eq $libreOfficePath) {
    $libreOfficeCommand = Get-Command `
        "soffice.com" `
        -ErrorAction SilentlyContinue

    if ($null -eq $libreOfficeCommand) {
        $libreOfficeCommand = Get-Command `
            "soffice.exe" `
            -ErrorAction SilentlyContinue
    }

    if ($null -ne $libreOfficeCommand) {
        $libreOfficePath = $libreOfficeCommand.Source
    }
}


if ($null -eq $libreOfficePath) {
    throw "LibreOffice not found."
}


# 44 = comma
# 34 = double quote
# 76 = UTF-8
$csvFilter = "csv:Text - txt - csv (StarCalc):44,34,76,1,,0,false,true,true"


# ----------------------------------------
# Convert
# ----------------------------------------

Write-Host ""
Write-Host "========================================"
Write-Host " Game Data Converter"
Write-Host "========================================"
Write-Host ""
Write-Host "Project Root : $projectRoot"
Write-Host "Private Root : $privateRepoRoot"
Write-Host "LibreOffice  : $libreOfficePath"
Write-Host "Targets      : $($targets.Count)"
Write-Host ""


$convertedCount = 0
$skippedCount = 0
$failedCount = 0


foreach ($target in $targets) {

    # ----------------------------------------
    # Validate Target
    # ----------------------------------------

    if ([string]::IsNullOrWhiteSpace($target)) {
        Write-Host "[ERROR] Target is empty."
        Write-Host ""

        $failedCount++
        continue
    }


    if ([System.IO.Path]::IsPathRooted($target)) {
        Write-Host "[ERROR] Absolute path is not allowed: $target"
        Write-Host ""

        $failedCount++
        continue
    }


    if ([System.IO.Path]::GetExtension($target) -ine ".ods") {
        Write-Host "[ERROR] Invalid target: $target"
        Write-Host "        Only .ods files are allowed."
        Write-Host ""

        $failedCount++
        continue
    }


    # ----------------------------------------
    # Resolve Paths
    # ----------------------------------------

    $sourcePath = [System.IO.Path]::GetFullPath(
        (Join-Path $unpackDataRoot $target)
    )

    $destinationRelativePath =
        [System.IO.Path]::ChangeExtension(
            $target,
            ".csv"
        )

    $destinationPath = [System.IO.Path]::GetFullPath(
        (Join-Path $gameDataRoot $destinationRelativePath)
    )


    # ----------------------------------------
    # Path Boundary Check
    # ----------------------------------------

    if (-not $sourcePath.StartsWith(
        $normalizedUnpackDataRoot,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        Write-Host "[ERROR] Target escapes unpackGameData: $target"
        Write-Host ""

        $failedCount++
        continue
    }


    if (-not $destinationPath.StartsWith(
        $normalizedGameDataRoot,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        Write-Host "[ERROR] Target escapes gameData: $target"
        Write-Host ""

        $failedCount++
        continue
    }


    if (-not (Test-Path $sourcePath -PathType Leaf)) {
        Write-Host "[MISSING] $target"
        Write-Host "          $sourcePath"
        Write-Host ""

        $failedCount++
        continue
    }


    # ----------------------------------------
    # Godot Import Setting
    # ----------------------------------------

    if (Test-Path $destinationPath -PathType Leaf) {
        $importUpdated = Ensure-GodotKeepImport `
            -CsvPath $destinationPath

        if ($importUpdated) {
            Write-Host "[IMPORT] $destinationRelativePath"
            Write-Host "         importer=keep"
            Write-Host ""
        }
    }


    # ----------------------------------------
    # Change Check
    # ----------------------------------------

    $sourceHash = (
        Get-FileHash `
            -Path $sourcePath `
            -Algorithm SHA256
    ).Hash


    $canSkip = $false

    if (
        $cache.ContainsKey($target) -and
        (Test-Path $destinationPath -PathType Leaf)
    ) {
        $destinationHash = (
            Get-FileHash `
                -Path $destinationPath `
                -Algorithm SHA256
        ).Hash

        $cachedEntry = $cache[$target]

        if (
            $cachedEntry.sourceHash -eq $sourceHash -and
            $cachedEntry.destinationHash -eq $destinationHash
        ) {
            $canSkip = $true
        }
    }


    if ($canSkip) {
        Write-Host "[SKIP] $target"
        Write-Host "       No changes"
        Write-Host ""

        $skippedCount++
        continue
    }


    # ----------------------------------------
    # Destination Directory
    # ----------------------------------------

    $destinationDirectory = Split-Path `
        $destinationPath `
        -Parent

    if (-not (Test-Path $destinationDirectory -PathType Container)) {
        New-Item `
            -ItemType Directory `
            -Path $destinationDirectory `
            -Force |
            Out-Null
    }


    # ----------------------------------------
    # Temporary Directory
    # ----------------------------------------

    $tempDirectory = Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        ("ProjectTOD_GameData_" +
            [System.Guid]::NewGuid().ToString("N"))

    New-Item `
        -ItemType Directory `
        -Path $tempDirectory `
        -Force |
        Out-Null


    try {
        Write-Host "[CONVERT] $target"


        # ----------------------------------------
        # ODS -> CSV
        # ----------------------------------------

        & $libreOfficePath `
            --headless `
            --convert-to $csvFilter `
            --outdir $tempDirectory `
            $sourcePath |
            Out-Null


        if ($LASTEXITCODE -ne 0) {
            throw "LibreOffice conversion failed with exit code $LASTEXITCODE."
        }


        $sourceFileName =
            [System.IO.Path]::GetFileNameWithoutExtension(
                $sourcePath
            )

        $convertedPath = Join-Path `
            $tempDirectory `
            "$sourceFileName.csv"


        if (-not (Test-Path $convertedPath -PathType Leaf)) {
            throw "CSV was not generated."
        }


        # ----------------------------------------
        # Normalize CSV
        # UTF-8 / No BOM / LF
        # ----------------------------------------

        $csvContent =
            [System.IO.File]::ReadAllText(
                $convertedPath
            )

        $csvContent = $csvContent `
            -replace "`r`n", "`n" `
            -replace "`r", "`n"


        [System.IO.File]::WriteAllText(
            $destinationPath,
            $csvContent,
            $utf8WithoutBom
        )


        # ----------------------------------------
        # Godot Import Setting
        # ----------------------------------------

        $importUpdated = Ensure-GodotKeepImport `
            -CsvPath $destinationPath

        if ($importUpdated) {
            Write-Host "[IMPORT] $destinationRelativePath"
            Write-Host "         importer=keep"
        }


        # ----------------------------------------
        # Update Cache
        # ----------------------------------------

        $destinationHash = (
            Get-FileHash `
                -Path $destinationPath `
                -Algorithm SHA256
        ).Hash

        $cache[$target] = @{
            sourceHash      = $sourceHash
            destinationHash = $destinationHash
        }


        Write-Host "          -> $destinationRelativePath"
        Write-Host ""

        $convertedCount++
    }
    catch {
        Write-Host "[ERROR] $target"
        Write-Host "        $($_.Exception.Message)"
        Write-Host ""

        $failedCount++
    }
    finally {
        if (Test-Path $tempDirectory) {
            Remove-Item `
                -Path $tempDirectory `
                -Recurse `
                -Force
        }
    }
}


# ----------------------------------------
# Remove Stale Cache Entries
# ----------------------------------------

$currentTargetSet = @{}

foreach ($target in $targets) {
    if (-not [string]::IsNullOrWhiteSpace($target)) {
        $currentTargetSet[$target] = $true
    }
}


foreach ($cachedTarget in @($cache.Keys)) {
    if (-not $currentTargetSet.ContainsKey($cachedTarget)) {
        $cache.Remove($cachedTarget)
    }
}


# ----------------------------------------
# Save Cache
# ----------------------------------------

$cacheEntries = @()

foreach ($target in ($cache.Keys | Sort-Object)) {
    $cacheEntries += [ordered]@{
        target          = $target
        sourceHash      = $cache[$target].sourceHash
        destinationHash = $cache[$target].destinationHash
    }
}

$cacheOutput = [ordered]@{
    entries = $cacheEntries
}

$cacheContent = $cacheOutput |
    ConvertTo-Json -Depth 4

[System.IO.File]::WriteAllText(
    $cachePath,
    $cacheContent + "`n",
    $utf8WithoutBom
)


# ----------------------------------------
# Result
# ----------------------------------------

Write-Host "----------------------------------------"
Write-Host "Converted : $convertedCount"
Write-Host "Skipped   : $skippedCount"
Write-Host "Failed    : $failedCount"
Write-Host "========================================"


if ($failedCount -gt 0) {
    exit 1
}

exit 0
