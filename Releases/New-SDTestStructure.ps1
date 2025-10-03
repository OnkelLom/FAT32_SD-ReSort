<#
.SYNOPSIS
    Creates a test folder structure with folders and files for FAT32 sorting tests.

.DESCRIPTION
    Creates folders and files with Normal, ReadOnly, and Hidden attributes.
    Supports a rebuild mode that removes the existing test folder before creation.

.PARAMETER Path
    Root path where the test structure will be created. Optional. Defaults to a "TestStructure" folder in the script directory.

.PARAMETER RebuildTest
    If true, deletes the existing test folder before creating the structure. Default: $true
#>

[CmdletBinding()]
param(
    [string]$Path = "",        # default to empty string to avoid interactive prompt
    [bool]$RebuildTest = $true
)

#region Variables

$Folders = @(
    @{ Name="Test_NormalFolder";   Attributes="Normal" },
    @{ Name="Test_ReadOnlyFolder"; Attributes="ReadOnly" },
    @{ Name="Test_HiddenFolder";   Attributes="Hidden" }
)

$FileTypes = @(
    @{ Suffix="NormalFile.txt";   Content="Normal test file"; Attributes="Normal" },
    @{ Suffix="ReadOnlyFile.txt"; Content="ReadOnly test file"; Attributes="ReadOnly" },
    @{ Suffix="HiddenFile.txt";   Content="Hidden test file"; Attributes="Hidden" }
)

#endregion

#region Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","PASS","FAIL","ERROR","WARN")]
        [string]$Level = "INFO"
    )

    $color = switch ($Level) {
        "INFO"  { "White" }
        "PASS"  { "Green" }
        "FAIL"  { "Red" }
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
    }

    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Convert-Attribute {
    param([string]$Attr)
    switch ($Attr.ToLower()) {
        "normal"   { return [System.IO.FileAttributes]::Normal }
        "readonly" { return [System.IO.FileAttributes]::ReadOnly }
        "hidden"   { return [System.IO.FileAttributes]::Hidden }
        default    { return [System.IO.FileAttributes]::Normal }
    }
}

function New-Folder {
    param([string]$TargetPath)
    try {
        if (-not (Test-Path $TargetPath)) {
            New-Item -ItemType Directory -Path $TargetPath -ErrorAction Stop | Out-Null
            Write-Log "Folder created: $TargetPath" -Level "INFO"
        }
    } catch {
        Write-Log "Failed to create folder $TargetPath. $_" -Level "ERROR"
    }
}

function New-File {
    param([string]$TargetPath, [string]$Content)
    try {
        Set-Content -Path $TargetPath -Value $Content -ErrorAction Stop
        Write-Log "File created: $TargetPath" -Level "INFO"
    } catch {
        Write-Log "Failed to create file $TargetPath. $_" -Level "ERROR"
    }
}

function Set-Attributes {
    param([string]$TargetPath, [System.IO.FileAttributes]$Attributes)
    try {
        if (Test-Path $TargetPath) {
            $item = Get-Item -Path $TargetPath -Force
            $item.Attributes = $Attributes
            Write-Log "Set attributes for $TargetPath to $Attributes" -Level "INFO"
        } else {
            Write-Log "Cannot set attributes: $TargetPath does not exist" -Level "WARN"
        }
    } catch {
        Write-Log "Failed to set attributes for $TargetPath. $_" -Level "ERROR"
    }
}

function Test-Attributes {
    param([string]$TargetPath, [System.IO.FileAttributes]$ExpectedAttributes)
    try {
        if (Test-Path $TargetPath) {
            $ActualAttributes = (Get-Item $TargetPath -Force).Attributes

            # Remove Directory flag if this is a folder
            if (Test-Path $TargetPath -PathType Container) {
                $ActualAttributes = $ActualAttributes -band -bnot [System.IO.FileAttributes]::Directory
            }

            # Treat 0 as Normal
            if ($ActualAttributes -eq 0) { $ActualAttributes = [System.IO.FileAttributes]::Normal }

            Write-Log "Verifying $TargetPath" -Level "INFO"
            Write-Log "Expected Attributes: $ExpectedAttributes" -Level "INFO"
            Write-Log "Actual Attributes  : $ActualAttributes" -Level "INFO"

            if (($ActualAttributes -band $ExpectedAttributes) -eq $ExpectedAttributes) {
                Write-Log "$TargetPath has expected attributes: $ExpectedAttributes" -Level "PASS"
            } else {
                Write-Log "$TargetPath attributes mismatch!" -Level "FAIL"
                Write-Log "Expected: $ExpectedAttributes, Actual: $ActualAttributes" -Level "FAIL"
            }
        } else {
            Write-Log "$TargetPath does not exist" -Level "FAIL"
        }
    } catch {
        Write-Log "Verification failed for $TargetPath. $_" -Level "ERROR"
    }
}

function Reset-AttributesForDeletion {
    param([string]$TargetPath)
    try {
        if (Test-Path $TargetPath) {
            Get-ChildItem -Path $TargetPath -Recurse -Force | ForEach-Object {
                try { $_.Attributes = [System.IO.FileAttributes]::Normal } catch {}
            }
            (Get-Item $TargetPath -Force).Attributes = [System.IO.FileAttributes]::Normal
        }
    } catch {
        Write-Log "Failed to reset attributes for deletion on $TargetPath. $_" -Level "ERROR"
    }
}

#endregion

#region Default Path Handling

if ([string]::IsNullOrWhiteSpace($Path)) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $Path = Join-Path $ScriptDir "TestStructure"
    Write-Log "No path provided. Using default test folder: $Path" -Level "INFO"
}

#endregion

#region Rebuild Test Folder

try {
    if ($RebuildTest -and (Test-Path $Path)) {
        Write-Log "Rebuild mode active: Removing existing test folder $Path" -Level "INFO"
        Normalize-AttributesForDeletion -TargetPath $Path
        Remove-Item $Path -Recurse -Force -ErrorAction Stop
    }

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -ErrorAction Stop | Out-Null
        Write-Log "Base folder created: $Path" -Level "INFO"
    }
} catch {
    Write-Log "Failed to prepare test root $Path. $_" -Level "ERROR"
    return
}

#endregion

#region Create Folders

foreach ($folder in $Folders) {
    $fullPath = Join-Path $Path $folder.Name
    Create-Folder -TargetPath $fullPath
    Set-Attributes -TargetPath $fullPath -Attributes (Convert-Attribute $folder.Attributes)
}

#endregion

#region Create Files

foreach ($folder in $Folders) {
    $parentFolder = Join-Path $Path $folder.Name
    foreach ($fileType in $FileTypes) {
        $fullPath = Join-Path $parentFolder $fileType.Suffix
        Create-File -TargetPath $fullPath -Content $fileType.Content
        Set-Attributes -TargetPath $fullPath -Attributes (Convert-Attribute $fileType.Attributes)
    }
}

#endregion

#region Verify Objects

Write-Log "Starting verification of all objects..." -Level "INFO"

foreach ($folder in $Folders) {
    $fullPath = Join-Path $Path $folder.Name
    Test-Attributes -TargetPath $fullPath -ExpectedAttributes (Convert-Attribute $folder.Attributes)
}

foreach ($folder in $Folders) {
    $parentFolder = Join-Path $Path $folder.Name
    foreach ($fileType in $FileTypes) {
        $fullPath = Join-Path $parentFolder $fileType.Suffix
        Test-Attributes -TargetPath $fullPath -ExpectedAttributes (Convert-Attribute $fileType.Attributes)
    }
}

Write-Log "Test setup and verification completed under $Path" -Level "INFO"

#endregion
