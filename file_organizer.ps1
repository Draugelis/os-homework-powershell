<#
.SYNOPSIS
Organize files in a folder

.DESCRIPTION
Organizes files in a provided folder based on their file extensions and 
detects duplicate files based on file hashes.

.PARAMETER Only
Specifies file categories that shall be limited for organization.

.PARAMETER Except
Specifies file categories that shall be excluded from organization

.PARAMETER IgnoreDuplicates
Specifies whether to ignore duplicate files during organization process.

.INPUTS
OrganizeFiles only accepts inputs using parameters

.EXAMPLE
C:\PS> OrganizeFiles . 

.EXAMPLE
C:\PS> OrganizeFiles -Only Images

.EXAMPLE
C:\PS> OrganizeFiles -Except Documents

.EXAMPLE
C:\PS> OrganizeFiles -Only Videos -IgnoreDuplicates

#>
function OrganizeFiles {
    [CmdletBinding()]

    param(
        [parameter(Mandatory = $False)]
        [ValidateSet("Images", "Documents", "Videos", "Audio")]
        [String[]]$Only,

        [parameter(Mandatory = $False)]
        [ValidateSet("Images", "Documents", "Videos", "Audio")]
        [String[]]$Except,

        [switch]$IgnoreDuplicates
    )

    # Ensure that only -Only or -Except is set but not both
    if ($PSBoundParameters.ContainsKey('Only') -and $PSBoundParameters.ContainsKey('Except')) {
        throw "You can use either -Only or -Except parameter."
    }
    
    # Pre-defined file categories
    $FileCategories = @{
        "Images"    = @(".jpg", ".png", ".gif", ".bmp")
        "Documents" = @(".pdf", ".docx", ".xlsx", ".pptx")
        "Videos"    = @(".mp4", ".mkv", ".avi", ".mov")
        "Audio"     = @(".mp3", ".wav", ".flac", ".ogg")
    }

    # Generate list of extensions that will be targeted
    $TargetExtensions = @()
    if (-not $Only -and -not $Except) {
        # Neither Only or Except are used in params
        foreach ($category in $FileCategories.Keys) {
            $TargetExtensions += $FileCategories[$category]
        }
    }
    elseif ($Only) {
        # Only param is set
        foreach ($category in $Only) {
            $TargetExtensions += $FileCategories[$category]
        }
    }
    else {
        # Except param is set
        foreach ($category in $FileCategories.Keys) {\
            if ($category -notin $Except) {
                $TargetExtensions += $FileCategories[$category]
            }
        }
    }

    Write-Host "Target extensions: $($TargetExtensions)"

    # Get files with extensions and generate hashes
    $Files = Get-ChildItem -File | 
        Where-Object {$_.Extension -in $TargetExtensions } |
        Select-Object FullName, Name, Extension, @{
            # Keeping track of the file category for a subfolder allcoation
            # Not the most aesthetic piece of code but it does the trick
            Name = "Category";
            Expression = {
                foreach ($category in $FileCategories.Keys) {
                    if ($FileCategories[$category] -contains $_.Extension) {
                        $category
                        break
                    }
                }
            }
        }, @{
            # Keeping track of file hash for detecting duplicate files
            # This ensures that duplicates with different names are found
            Name = "Hash";
            Expression = { (Get-FileHash $_.FullName).Hash }
        }

    # Write-Host "[DEBUG] Files: $($Files)"

    # Handle duplicates if IgnoreDuplicates flag is not set
    if (-not $IgnoreDuplicates) {
        Write-Host "Detecting duplicates..."
        $Duplicates = $Files | Group-Object Hash | Where-Object $_.Count -gt 1
        # Write-Host "[DEBUG] Duplicates: $($Duplicates)"
        foreach ($group in $Duplicates) {
            if ($group.Count -le 1) {
                continue
            }

            Write-Host "Found $($group.Count) files with identical content (hash: $($group.Name)):"
            foreach ($file in $group.Group) {
                Write-Host "  - $($file.FullName)"
            }
            
            # Prompt user for a decision
            while ($True) {
                $choice = Read-Host "Choose action: [S]kip, [M]ove all"
                $choice = $choice.ToUpper()
                
                switch ($choice) {
                    'S' {
                        Write-Host "Will skip these duplicates..."
                        # Removing duplicate group from $Files
                        $Files = $Files | Where-Object { $_.Hash -ne $group.Name }
                        break
                    }
                    'M' {
                        # No-op here since files will be moved later
                        Write-Host "Will move these files..."
                        break
                    }
                    default {
                        Write-Host "Invalid choice. Select [S] or [M]"
                        continue  # Retry selection
                    }
                }
                break
            }
        }
    }

    # Move the files to subfolders
    Write-Host "Moving files..."
    $Files | ForEach-Object {
        $Destination = Join-Path (Split-Path -Parent $_.FullName) $_.Category
        # Write-Host "[DEBUG] Destination: $($Destination)"

        # Create destination folder if doesn't exist
        if (-not (Test-Path $Destination)) {
            New-Item -ItemType Directory -Path $Destination | Out-Null  # Out-Null is to supress New-Item output
        }

        Move-Item -Path $_.FullName -Destination $Destination
        Write-Host "Moved $($_.Name) to $($_.Category) subfolder."
    }

    Write-Host "Finished moving files."
}