<#
.SYNOPSIS
    Unified Script: Test Structure Creation & FAT32 ReSort

.DESCRIPTION
    Creates a test folder structure (optional) with Normal, ReadOnly, Hidden attributes,
    and performs a FAT32-style re-sorting of folders and files.

.PARAMETER Path
    Root path for test structure and sorting. Defaults to TestStructure in script folder for testmode,
    otherwise script folder if not specified.

.PARAMETER SortBy
    Sorting criteria: Name | CreationTime | LastWriteTime | Length

.PARAMETER testmode
    If true, creates test folder structure and performs sorting test.

.PARAMETER DryRun
    If true, only simulates moves and folder creation/removal.

.PARAMETER HandleReadOnlyHidden
    Temporarily removes ReadOnly/Hidden attributes to allow moving.

.PARAMETER Verbose
    If true, shows move logs (only relevant when testmode=false).

.PARAMETER ShowProgress
    If true, shows progress bars.

.PARAMETER Force
    If true, forces overwriting existing test structure (only relevant in testmode).
#>

[CmdletBinding()]
param(
    [string]$Path = "",                                     # Root path for test structure and sorting. Defaults to TestStructure in script folder for testmode, otherwise script folder if not specified
    [ValidateSet("Name", "CreationTime", "LastWriteTime", "Length")]
    [string]$SortBy = "Name",                               # Sorting criteria: Name | CreationTime | LastWriteTime | Length
    [Switch]$DryRun,                                        # If set, only simulates moves and folder creation/removal
    [bool]$HandleReadOnlyHidden = $true                     # If set, temporarily removes ReadOnly/Hidden attributes to allow moving
)

#region Global Variables & Constants

# Handle DryRun globally
$GlobalDryRun = $PSBoundParameters.ContainsKey('DryRun') -and $DryRun

# Handle ReadOnly/Hidden globally
$GlobalHandleReadOnlyHidden = $HandleReadOnlyHidden

# Exclusions - files or folders to exclude from sorting (e.g. the script itself)
$Exclusions = @(
    $MyInvocation.MyCommand.Source,
    "System Volume Information"
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

    Write-Host "[$Level] $Message $(if($GlobalDryRun) { '(DryRun)' })" -ForegroundColor $color
}
function Move-ItemWithAttributes {
    param(
        [Parameter(Mandatory=$true)][System.IO.FileSystemInfo]$Item,
        [Parameter(Mandatory=$true)][string]$Target
    )

    # Determine if item is file or folder   
    $currentItemType = if ($Item.PSIsContainer) { 'Folder' } else { 'File' }

    # check if ReadOnly or Hidden
    [System.IO.FileAttributes]$originalAttributes = $Item.Attributes
    $isSpecial = $Item.Attributes -band ([System.IO.FileAttributes]::ReadOnly -bor [System.IO.FileAttributes]::Hidden)

    if ($isSpecial) {
        if ($GlobalHandleReadOnlyHidden) {

            # INFO, move with Attributes
            Write-Log "[MOVE] $currentItemType (ReadOnly/Hidden) $($Item.FullName)" -Level "INFO"
            
        } else {
            # WARN, no move
            Write-Log "[WARN] $currentItemType has special attributes (ReadOnly/Hidden) and will NOT be moved: $($Item.FullName)" -Level "WARN"
            return
        }
    } else {
        Write-Log "[MOVE] $currentItemType $($Item.FullName)" -Level "INFO"
    }

    # Do if not DryRun
    if (-not $GlobalDryRun) {
        try {
            if ($GlobalHandleReadOnlyHidden -and $isSpecial) {
                # temporarily remove attributes
                $Item.Attributes = [System.IO.FileAttributes]::Normal 
            }

            # do move
            Move-Item $Item.FullName $Target -ErrorAction Stop

            if ($GlobalHandleReadOnlyHidden -and $isSpecial) {
                # restore attributes
                (Get-Item $Target -Force).Attributes = $originalAttributes
            }
        } catch {
            Write-Log "[ERROR] Failed to move item $($item.FullName): $($_.Exception.Message)" -Level "ERROR"
        }
    }
}

function New-TempFolderWithId {
    param(
        [string]$BasePath
    )
    try {
        $uniqueId = ([guid]::NewGuid().ToString('N')).Substring(0,6)
        $tempFolder = Join-Path $BasePath $uniqueId
        Write-Log "[CREATE] Folder $tempFolder temporarily created" -Level "INFO"
        if (-not $GlobalDryRun) {
            New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null
        }  
        return $tempFolder
    }
    catch {
        Write-Log "[ERROR] Failed to create temp folder in $BasePath : $($_.Exception.Message)" -Level "ERROR"
    }
}

#endregion

#region Check & Set Root Path

if ([string]::IsNullOrWhiteSpace($Path)) {
    $Path = Split-Path -Parent $MyInvocation.MyCommand.Definition
    Write-Log "No path provided. Using script folder as root: $Path" -Level "INFO"
} else {
    Write-Log "Using provided path as root: $Path" -Level "INFO"
}

#endregion

#region FAT32 ReSort Logic

# Initialize runtime variables
$folders          = @()

# Collect all folders recursively (exclude temp folder)
$folders = Get-ChildItem -Path $Path -Directory -Recurse -Force | Where-Object {
    ($Exclusions -notcontains $_.FullName) -and
    ($Exclusions -notcontains $_.Name)
} | Sort-Object FullName

# Process each folder
$totalFolders = $folders.Count
$folderIndex = 0
$lastPercent = -1

foreach ($folder in $folders) {
    $folderIndex++
    $percent = [math]::Floor(($folderIndex / $totalFolders) * 100)
    if ($percent -ne $lastPercent) {
        Write-Progress -Activity "FAT32 Resort" -Status "Ordner $folderIndex von $totalFolders" -PercentComplete $percent -CurrentOperation "Processing folder: $($folder.FullName)"
        $lastPercent = $percent
    }

    Write-Log "[INFO] Processing folder: $($folder.FullName)" -Level "INFO"

    # Collect all items in the folder, sort by chosen criteria
    $allItems  = Get-ChildItem -Path $folder.FullName -Force | Where-Object {
        ($Exclusions -notcontains $_.FullName) -and
        ($Exclusions -notcontains $_.Name)
    } | Sort-Object $SortBy
    $totalItems = $allItems.Count

    # Skip if no items to sort
    if ($totalItems -eq 0) {
        Write-Log "Nothing to sort in $($folder.FullName), skipping." -Level "INFO"
        continue
    }

    # Create temporary folder
    try {
        $currenttempfolder = New-TempFolderWithId -BasePath $folder.FullName
    } catch {
        Write-Log "[ERROR] Failed to create temp folder $currenttempfolder : $($_.Exception.Message)" -Level "ERROR"
        continue
    }

    # Move each item into temp folder
    foreach ($item in $allItems) {
        $dest = Join-Path $currenttempfolder $item.Name
        Move-ItemWithAttributes -Item $item -Target $dest
    }

    # Move items back from temp folder to original folder in sorted order
    if (-not $GlobalDryRun) {
        Write-Log "[INFO] All items moved to $currenttempfolder - Start Sorting" -Level "INFO"
        $sortedItems = Get-ChildItem -Path $currenttempfolder -Force | Sort-Object $SortBy
        foreach ($item in $sortedItems) {
            $dest = Join-Path $folder.FullName $item.Name
            Move-ItemWithAttributes -Item $item -Target $dest
        }
    } else {
        Write-Log "[INFO] Would sort and move items back from $currenttempfolder" -Level "INFO"
    }

    # Remove temporary folder
    try {
        if (-not $GlobalDryRun) {
            Remove-Item $currenttempfolder -Force -ErrorAction Stop
        }
        Write-Log "[REMOVE] Folder $currenttempfolder removed" -Level "INFO"
    } catch {
        Write-Log "[ERROR] Failed to remove temp folder $currenttempfolder : $($_.Exception.Message)" -Level "ERROR"
    }
    }
Write-Progress -Activity "FAT32 Resort" -Completed

#endregion

Write-Log "[SUCCESS] Script completed successfully" -Level "INFO"