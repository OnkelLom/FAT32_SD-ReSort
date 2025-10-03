# FAT32 SD-ReSort Script

## Description
This PowerShell script performs a FAT/FAT32-style re-sorting of folders and files, which is especially useful for SD cards using FAT/FAT32 file systems. Some devices, such as EverDrive GB x7 or EverDrive N8 flashcarts, cannot automatically sort files and folders. This script helps achieve the desired order by moving Files and Folders to temporary folders.

**Note:** An additional script is provided to create a test folder structure with various file and folder attributes (Normal, ReadOnly, Hidden) for development and testing purposes. This test script should only be used in a development environment to create a teststructure and is not needed for the functionality.

## Features
- Optional creation of test folder structure with various file attributes.
- FAT/FAT32-style sorting based on:
  - `Name`
  - `CreationTime`
  - `LastWriteTime`
  - `Length`
- Handles ReadOnly and Hidden attributes automatically if enabled.
- Dry-run mode to simulate operations without modifying files.

## Requirements
- Windows PowerShell (v5 or later recommended)
- File system must be FAT/FAT32 if aiming for actual device sorting, otherwise NTFS is fine for testing.

## Installation
1. Clone or download this repository:
   ```bash
   git clone https://github.com/<your-username>/<your-repo>.git
   ```
2. Navigate to the script directory:
   ```powershell
   cd <your-repo>
   ```

## Usage
Basic usage of the script:

```powershell
.\FAT32-ReSort.ps1 -Path "C:\Path\To\SDCard" -SortBy Name
```

### Parameters
- `-Path` (optional): Root path to sort. Defaults to the script folder if not specified.
- `-SortBy` (optional): Sorting criteria. Options: `Name`, `CreationTime`, `LastWriteTime`, `Length`. Default is `Name`.
- `-DryRun` (switch, optional): Simulates actions without moving any files.
- `-HandleReadOnlyHidden` (switch, optional): Temporarily removes ReadOnly and Hidden attributes to allow moving. Default is `true`.

### Examples
```powershell
# Perform a dry-run sort based on file creation time
.\FAT32-ReSort.ps1 -Path "D:\SDCard" -SortBy CreationTime -DryRun

# Sort files by size and handle ReadOnly/Hidden attributes
.\FAT32-ReSort.ps1 -Path "D:\SDCard" -SortBy Length -HandleReadOnlyHidden $true

# Sort using default settings (Name, script folder)
.\FAT32-ReSort.ps1

# Create a development test folder structure with Normal, ReadOnly, and Hidden files/folders
.\Create-TestStructure.ps1 -Path "C:\Path\To\Test" -RebuildTest $true
```

## Logging
The script provides color-coded logging for actions:
- `INFO` – General information
- `PASS` – Successful actions
- `FAIL` / `ERROR` – Failed actions
- `WARN` – Warnings (e.g., ReadOnly/Hidden files not moved)

## License
This project is licensed under the **GNU General Public License v3.0 (GPLv3)**. See [LICENSE](LICENSE) for details.
