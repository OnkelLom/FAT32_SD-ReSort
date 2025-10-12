<#
.SYNOPSIS
    FAT32 SD-ReSort Script

.DESCRIPTION
    Creates a test folder structure (optional) with Normal, ReadOnly, Hidden attributes,
    and performs a FAT/FAT32-style re-sorting of folders and files. This is especially useful for SD cards
    that use FAT/FAT32 file systems, which have specific sorting behaviors. FlashCarts like the EverDrive GB x7 or EverDrive N8 can't
    sort files/folders by themselves, so this script helps to achieve the desired order.

.PARAMETER Path
    Root path for test structure and sorting. Defaults to script folder if not specified.

.PARAMETER SortBy
    Sorting criteria: Name | CreationTime | LastWriteTime | Length

.PARAMETER DryRun
    If true, only simulates moves and folder creation/removal.

.PARAMETER HandleReadOnlyHidden
    Temporarily removes ReadOnly/Hidden attributes to allow moving.

#>

[CmdletBinding()]
param(
    [string]$Path = "",                                     # Root path for test structure and sorting. Defaults to TestStructure in script folder for testmode, otherwise script folder if not specified
    [ValidateSet("Name", "CreationTime", "LastWriteTime", "Length")]
    [string]$SortBy = "Name",                               # Sorting criteria: Name | CreationTime | LastWriteTime | Length
    [Switch]$DryRun,                                        # If set, only simulates moves and folder creation/removal
    [bool]$HandleReadOnlyHidden = $true                     # If set, temporarily removes ReadOnly/Hidden attributes to allow moving
)
try {
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
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Message,

            [ValidateSet("INFO", "PASS", "FAIL", "ERROR", "WARN")]
            [string]$Level = "INFO",

            [string]$Action
        )

        # Determine output color based on log level
        $color = switch ($Level) {
            "INFO" { "White" }
            "PASS" { "Green" }
            "FAIL" { "Red" }
            "ERROR" { "Red" }
            "WARN" { "Yellow" }
            default { "Gray" }
        }

        # Check if GlobalDryRun exists and is true
        $isDryRun = $false
        if (Get-Variable -Name GlobalDryRun -Scope Global -ErrorAction SilentlyContinue) {
            $isDryRun = [bool]$Global:GlobalDryRun
        }

        # Optional DryRun prefix
        $dryRunText = if ($isDryRun) { "[DryRun] " } else { "" }

        # Fixed column widths for alignment
        $levelWidth = 8     # Total width for the [LEVEL] column
        $actionWidth = 16    # Total width for the [ACTION] column

        # Format level and action fields to align messages consistently
        $levelText = ("[{0}]" -f $Level).PadRight($levelWidth)
        $actionText = if (-not [string]::IsNullOrWhiteSpace($Action)) {
            ("[{0}]" -f $Action).PadRight($actionWidth)
        }
        else {
            "".PadRight($actionWidth)
        }

        # Build final output line
        $output = "$dryRunText$levelText$actionText$Message"

        # Print colored log line to console
        Write-Host $output -ForegroundColor $color
    }

    function Move-ItemWithAttributes {
        param(
            [Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item,
            [Parameter(Mandatory = $true)][string]$Target
        )

        # Determine if item is file or folder   
        $currentItemType = if ($Item.PSIsContainer) { 'Folder' } else { 'File' }

        # check if ReadOnly or Hidden
        [System.IO.FileAttributes]$originalAttributes = $Item.Attributes
        $isSpecial = $Item.Attributes -band ([System.IO.FileAttributes]::ReadOnly -bor [System.IO.FileAttributes]::Hidden)

        if ($isSpecial) {
            if ($GlobalHandleReadOnlyHidden) {

                # INFO, move with Attributes
                Write-Log "$currentItemType (ReadOnly/Hidden) $($Item.FullName)" -Level "INFO" -Action "MOVE"
                
            }
            else {
                # WARN, no move
                Write-Log "$currentItemType has special attributes (ReadOnly/Hidden) and will NOT be moved: $($Item.FullName)" -Level "WARN" -Action $null
                return
            }
        }
        else {
            Write-Log "$currentItemType $($Item.FullName)" -Level "INFO" -Action "MOVE"
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
            }
            catch {
                Write-Log "Failed to move item $($item.FullName): $($_.Exception.Message)" -Level "ERROR" -Action "ABORT"
                throw 
            }
        }
    }

    function New-TempFolderWithId {
        param(
            [string]$BasePath
        )
        try {
            $uniqueId = "temp_" + ([guid]::NewGuid().ToString('N')).Substring(0, 4)
            $tempFolder = Join-Path $BasePath $uniqueId
            Write-Log "Folder $tempFolder temporarily created" -Level "INFO" -Action "CREATE"
            if (-not $GlobalDryRun) {
                New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null
            }  
            return $tempFolder
        }
        catch {
            Write-Log "Failed to create temp folder in $BasePath : $($_.Exception.Message)" -Level "ERROR" -Action $null
        }
    }

    #endregion

    #region Check & Set Root Path

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Split-Path -Parent $MyInvocation.MyCommand.Definition
        Write-Log "No path provided. Using script folder as root: $Path" -Level "INFO" -Action $null
    }
    else {
        Write-Log "Using provided path as root: $Path" -Level "INFO" -Action $null
    }

    #endregion

    #region FAT32 ReSort Logic

    # Initialize runtime variables
    $folders = @()

    # Collect all folders recursively (exclude temp folder)
    $folders = Get-ChildItem -Path $Path -Directory -Recurse -Force | Where-Object {
        ($Exclusions -notcontains $_.FullName) -and
        ($Exclusions -notcontains $_.Name)
    } | Sort-Object FullName

    # Process each folder
    $totalFolders = $folders.Count
    $folderIndex = 0
    $lastPercent = -1

    foreach ($loopfolder in $folders) {
        $folderIndex++
        $percent = [math]::Floor(($folderIndex / $totalFolders) * 100)
        if ($percent -ne ($lastPercent + 2)) {
            Write-Progress -Activity "FAT32 Resort" -Status "Ordner $folderIndex von $totalFolders" -PercentComplete $percent -CurrentOperation "Processing folder: $($loopfolder.FullName)"
            $lastPercent = $percent
        }

        Write-Log "Processing folder: $($loopfolder.FullName)" -Level "INFO" -Action "CHANGEFOLDER"

        # Collect all items in the folder
        $allItems = Get-ChildItem -Path $loopfolder.FullName -Force | Where-Object {
            ($Exclusions -notcontains $_.FullName) -and
            ($Exclusions -notcontains $_.Name)
        } #| Sort-Object $SortBy

        # Skip if no items to sort
        if ($allItems.Count -eq 0) {
            Write-Log "Nothing to sort in $($loopfolder.FullName), skipping." -Level "INFO" -Action $null
            continue
        }

        # Create temporary folder
        try {
            $currenttempfolder = New-TempFolderWithId -BasePath $loopfolder.FullName
        }
        catch {
            Write-Log "Failed to create temp folder $currenttempfolder : $($_.Exception.Message)" -Level "ERROR" -Action "ABORT"
            continue
        }

        # Move each item into temp folder
        foreach ($item in $allItems) {
            $dest = Join-Path $currenttempfolder $item.Name
            Move-ItemWithAttributes -Item $item -Target $dest
        }

        # Move items back from temp folder to original folder in sorted order
        if (-not $GlobalDryRun) {
            Write-Log "All items moved to $currenttempfolder - Start Sorting" -Level "INFO" -Action "STARTSORT"
            $sortedFolders = Get-ChildItem -Path $currenttempfolder -Force -Directory  | Sort-Object $SortBy
            $sortedFiles = Get-ChildItem -Path $currenttempfolder -Force -File  | Sort-Object $SortBy
            if ($sortedFolders.Count -ne 0) {
                foreach ($currentFolder in $sortedFolders) {
                    $dest = Join-Path $loopfolder.FullName $currentFolder.Name
                    Write-Log "Moving Folder $($currentFolder.FullName)" -Level "INFO" -Action "SORT"
                    Move-ItemWithAttributes -Item $currentFolder -Target $dest
                }
            }
            if ($sortedFiles.Count -ne 0) {
                foreach ($currentFile in $sortedFiles) {
                    $dest = Join-Path $loopfolder.FullName $currentFile.Name
                    Move-ItemWithAttributes -Item $currentFile -Target $dest
                }
            }
        }
        else {
            Write-Log "Would sort and move items back from $currenttempfolder" -Level "INFO" -Action "SORT"
        }

        # Remove temporary folder
        try {
            if (-not $GlobalDryRun) {
                Remove-Item $currenttempfolder -Force -ErrorAction Stop
            }
            Write-Log "Folder $currenttempfolder removed" -Level "INFO" -Action "REMOVETEMP"
        }
        catch {
            Write-Log "Failed to remove temp folder $currenttempfolder : $($_.Exception.Message)" -Level "ERROR" -Action "ABORT"
        }
    }
    Write-Progress -Activity "FAT32 Resort" -Completed

    #endregion

    Write-Log "Script completed successfully" -Level "INFO" -Action "PASS"
}
catch { 
}