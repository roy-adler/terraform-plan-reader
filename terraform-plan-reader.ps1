# Terraform Plan Reader (PowerShell version)

param(
    [Parameter(Position=0)]
    [string]$InputFile = "terraform_plan.txt",
    
    [Alias("l")]
    [int]$Limit = 0,
    
    [Alias("g")]
    [switch]$GroupByModule,
    
    [Alias("d")]
    [switch]$Detail,
    
    [Alias("a")]
    [switch]$Alphabetical,
    
    [Alias("h")]
    [switch]$Help
)

# Show help
if ($Help) {
    Write-Host "Usage: .\terraform-plan-reader.ps1 [OPTIONS] [FILE]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Limit N, -l N        Show categorized lists with N items per section (0 = show all)"
    Write-Host "  -GroupByModule, -g    Group modules with identical action patterns and show detailed changes"
    Write-Host "  -Detail, -d           Show detailed parameter changes for resources"
    Write-Host "  -Alphabetical, -a     Show alphabetically sorted list of all resources"
    Write-Host "  -Help, -h             Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\terraform-plan-reader.ps1 terraform_plan.txt"
    Write-Host "  .\terraform-plan-reader.ps1 -Limit 20 terraform_plan.txt"
    Write-Host "  .\terraform-plan-reader.ps1 -GroupByModule terraform_plan.txt"
    Write-Host "  .\terraform-plan-reader.ps1 -l 50 -g terraform_plan.txt"
    exit 0
}

# Check if -l was explicitly provided (for showing lists)
$ShowLists = $PSBoundParameters.ContainsKey('Limit')

# Check if file exists
if (-not (Test-Path $InputFile)) {
    Write-Error "Error: File '$InputFile' not found"
    exit 1
}

# Read file content
$FileContent = Get-Content $InputFile -Raw
$FileLines = Get-Content $InputFile

# Function to clean line (remove timestamps and ANSI codes)
function Clean-Line {
    param([string]$Line)
    $Line = $Line -replace '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+Z ', ''
    $Line = $Line -replace '\x1b\[[0-9;]*m', ''
    return $Line
}

# Function to extract detailed changes for a resource
function Extract-ResourceChanges {
    param(
        [string]$ResourceName,
        [bool]$UsePlaceholder = $false,
        [string]$PlaceholderModule = ""
    )
    
    $escapedResource = [regex]::Escape($ResourceName)
    $inBlock = $false
    $braceCount = 0
    $skipNext = $false
    $startFound = $false
    
    foreach ($line in $FileLines) {
        $cleanLine = Clean-Line $line
        
        # Detect start of resource block
        if (-not $startFound -and $cleanLine -match "^\s*#\s*$escapedResource\s+(will be|must be)") {
            $startFound = $true
            $inBlock = $true
            $skipNext = $true
            continue
        }
        
        if (-not $startFound) { continue }
        
        # Skip reason lines
        if ($skipNext) {
            $skipNext = $false
            if ($cleanLine -match '^\s*#\s*\(because' -or $cleanLine -match '^\s*#\s*\(moved from') {
                continue
            }
        }
        
        # Detect next resource (stop processing)
        if ($inBlock -and $cleanLine -match '^\s*#\s*\S+\s+(will be|must be)' -and $cleanLine -notmatch $escapedResource) {
            break
        }
        
        if ($inBlock) {
            # Track braces
            $braceCount += ($cleanLine -split '{').Count - 1
            $braceCount -= ($cleanLine -split '}').Count - 1
            
            $processedLine = Clean-Line $line
            
            # Check if this is a change line
            if ($processedLine -match '^\s*[+-~]' -or $processedLine -match '->' -or ($processedLine -match '^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*=' -and $braceCount -gt 0)) {
                # Replace module name with placeholder if requested
                if ($UsePlaceholder -and $PlaceholderModule) {
                    $processedLine = $processedLine -replace [regex]::Escape($PlaceholderModule), '{module}'
                }
                
                # Clean up indentation
                $processedLine = $processedLine -replace '^\s{6,}', '      '
                
                # Skip comment-only and empty lines
                if ($processedLine -notmatch '^\s*#' -and $processedLine.Trim().Length -gt 0) {
                    if ($processedLine -match '[+-~]' -or $processedLine -match '->' -or $processedLine -match '^\s*[a-zA-Z_]') {
                        Write-Host "        $processedLine"
                    }
                }
            }
            
            # Stop when we exit the resource block
            if ($braceCount -lt 0) {
                break
            }
        }
    }
}

# Extract and display summary
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  TERRAFORM PLAN SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Extract summary line
$summaryLine = $FileLines | Where-Object { (Clean-Line $_) -match '^Plan:' } | Select-Object -First 1
$summaryLine = Clean-Line $summaryLine

if ($summaryLine) {
    Write-Host $summaryLine -ForegroundColor White
    Write-Host ""
    
    # Extract counts from summary
    $addCount = if ($summaryLine -match '(\d+) to add') { [int]$Matches[1] } else { 0 }
    $changeCount = if ($summaryLine -match '(\d+) to change') { [int]$Matches[1] } else { 0 }
    $destroyCount = if ($summaryLine -match '(\d+) to destroy') { [int]$Matches[1] } else { 0 }
} else {
    $addCount = 0
    $changeCount = 0
    $destroyCount = 0
}

# Count moves
$movedLines = $FileLines | Where-Object { $_ -match 'has moved to' }
$moveCount = ($movedLines | Measure-Object).Count

# Extract resources
$createdResources = $FileLines | Where-Object { (Clean-Line $_) -match 'will be created' } | ForEach-Object {
    $line = Clean-Line $_
    $line = $line -replace '^\s*#\s*', ''
    $line = $line -replace '\s*will be created.*$', ''
    $line.Trim()
} | Where-Object { $_ } | Sort-Object -Unique

$changedResources = $FileLines | Where-Object { (Clean-Line $_) -match 'will be updated' } | ForEach-Object {
    $line = Clean-Line $_
    $line = $line -replace '^\s*#\s*', ''
    $line = $line -replace '\s*will be updated.*$', ''
    $line.Trim()
} | Where-Object { $_ } | Sort-Object -Unique

$replacedResources = $FileLines | Where-Object { (Clean-Line $_) -match 'must be.*replaced|will be.*replaced' } | ForEach-Object {
    $line = Clean-Line $_
    $line = $line -replace '^\s*#\s*', ''
    $line = $line -replace '\s*must be.*replaced.*$', ''
    $line = $line -replace '\s*will be.*replaced.*$', ''
    $line.Trim()
} | Where-Object { $_ } | Sort-Object -Unique

$destroyedResources = $FileLines | Where-Object { (Clean-Line $_) -match 'will be.*destroyed' } | ForEach-Object {
    $line = Clean-Line $_
    $line = $line -replace '^\s*#\s*', ''
    $line = $line -replace '\s*will be.*destroyed.*$', ''
    $line = $line -replace '\s*\(because.*$', ''
    $line.Trim()
} | Where-Object { $_ } | Sort-Object -Unique

$movedResources = $FileLines | Where-Object { (Clean-Line $_) -match 'has moved to' } | ForEach-Object {
    $line = Clean-Line $_
    $line = $line -replace '^\s*#\s*', ''
    $line = $line -replace '\s*has moved to.*$', ''
    $line.Trim()
} | Where-Object { $_ } | Sort-Object -Unique

# Count replaced for summary
$replacedCountSummary = ($replacedResources | Measure-Object).Count

Write-Host "Resources to add:    " -ForegroundColor Green -NoNewline
Write-Host $addCount
Write-Host "Resources to change:  " -ForegroundColor Yellow -NoNewline
Write-Host $changeCount
if ($replacedCountSummary -gt 0) {
    Write-Host "Resources to replace: " -ForegroundColor Magenta -NoNewline
    Write-Host $replacedCountSummary
}
Write-Host "Resources to destroy: " -ForegroundColor Red -NoNewline
Write-Host $destroyCount
if ($moveCount -gt 0) {
    Write-Host "Resources to move:    " -ForegroundColor Blue -NoNewline
    Write-Host $moveCount
}
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Helper function to apply limit
function Apply-Limit {
    param([array]$Items)
    if ($Limit -gt 0 -and $Items.Count -gt $Limit) {
        return $Items | Select-Object -First $Limit
    }
    return $Items
}

# Show categorized lists only if -l flag was provided
if ($ShowLists) {
    Write-Host "RESOURCES TO BE CREATED:" -ForegroundColor Green
    Write-Host ""
    if ($createdResources) {
        $displayed = Apply-Limit $createdResources
        foreach ($resource in $displayed) {
            Write-Host "  $resource"
        }
        if ($Limit -gt 0 -and $createdResources.Count -gt $Limit) {
            $remaining = $createdResources.Count - $Limit
            Write-Host "  ... and $remaining more" -ForegroundColor Cyan
        }
    } else {
        Write-Host "  (none)"
    }
    
    Write-Host ""
    Write-Host "RESOURCES TO BE MODIFIED/CHANGED:" -ForegroundColor Yellow
    Write-Host ""
    if ($changedResources) {
        $displayed = Apply-Limit $changedResources
        if ($Detail) {
            foreach ($resource in $displayed) {
                Write-Host "  $resource" -ForegroundColor Yellow
                Extract-ResourceChanges -ResourceName $resource -UsePlaceholder $false -PlaceholderModule ""
                Write-Host ""
            }
        } else {
            foreach ($resource in $displayed) {
                Write-Host "  $resource"
            }
        }
        if ($Limit -gt 0 -and $changedResources.Count -gt $Limit) {
            $remaining = $changedResources.Count - $Limit
            Write-Host "  ... and $remaining more" -ForegroundColor Cyan
        }
    } else {
        Write-Host "  (none)"
    }
    
    Write-Host ""
    Write-Host "RESOURCES TO BE REPLACED:" -ForegroundColor Magenta
    Write-Host ""
    if ($replacedResources) {
        $displayed = Apply-Limit $replacedResources
        if ($Detail) {
            foreach ($resource in $displayed) {
                Write-Host "  $resource" -ForegroundColor Magenta
                Extract-ResourceChanges -ResourceName $resource -UsePlaceholder $false -PlaceholderModule ""
                Write-Host ""
            }
        } else {
            foreach ($resource in $displayed) {
                Write-Host "  $resource"
            }
        }
        if ($Limit -gt 0 -and $replacedResources.Count -gt $Limit) {
            $remaining = $replacedResources.Count - $Limit
            Write-Host "  ... and $remaining more" -ForegroundColor Cyan
        }
    } else {
        Write-Host "  (none)"
    }
    
    Write-Host ""
    Write-Host "RESOURCES TO BE DESTROYED:" -ForegroundColor Red
    Write-Host ""
    if ($destroyedResources) {
        $displayed = Apply-Limit $destroyedResources
        foreach ($resource in $displayed) {
            Write-Host "  $resource"
        }
        if ($Limit -gt 0 -and $destroyedResources.Count -gt $Limit) {
            $remaining = $destroyedResources.Count - $Limit
            Write-Host "  ... and $remaining more" -ForegroundColor Cyan
        }
    } else {
        Write-Host "  (none)"
    }
    
    if ($moveCount -gt 0) {
        Write-Host ""
        Write-Host "RESOURCES TO BE MOVED:" -ForegroundColor Blue
        Write-Host ""
        if ($movedResources) {
            $displayed = Apply-Limit $movedResources
            foreach ($resource in $displayed) {
                Write-Host "  $resource"
            }
            if ($Limit -gt 0 -and $movedResources.Count -gt $Limit) {
                $remaining = $movedResources.Count - $Limit
                Write-Host "  ... and $remaining more" -ForegroundColor Cyan
            }
        } else {
            Write-Host "  (none)"
        }
    }
}

# Show alphabetically sorted list if -a flag is set
if ($Alphabetical) {
    Write-Host ""
    Write-Host "ALL RESOURCES (ALPHABETICALLY SORTED):" -ForegroundColor Cyan
    Write-Host ""
    
    $allResources = @()
    if ($createdResources) { $allResources += $createdResources }
    if ($changedResources) { $allResources += $changedResources }
    if ($replacedResources) { $allResources += $replacedResources }
    if ($destroyedResources) { $allResources += $destroyedResources }
    if ($movedResources) { $allResources += $movedResources }
    
    $allResources = $allResources | Sort-Object -Unique
    
    if ($allResources) {
        foreach ($resource in $allResources) {
            $color = "White"
            if ($createdResources -contains $resource) { $color = "Green" }
            elseif ($replacedResources -contains $resource) { $color = "Magenta" }
            elseif ($changedResources -contains $resource) { $color = "Yellow" }
            elseif ($destroyedResources -contains $resource) { $color = "Red" }
            elseif ($movedResources -contains $resource) { $color = "Blue" }
            
            Write-Host "  $resource" -ForegroundColor $color
        }
    } else {
        Write-Host "  (none)"
    }
}

# Group by module if requested
if ($GroupByModule) {
    Write-Host ""
    Write-Host "RESOURCES GROUPED BY MODULE:" -ForegroundColor Cyan
    Write-Host ""
    
    # Collect all unique top-level modules
    $allResourcesList = @()
    if ($createdResources) { $allResourcesList += $createdResources }
    if ($changedResources) { $allResourcesList += $changedResources }
    if ($replacedResources) { $allResourcesList += $replacedResources }
    if ($destroyedResources) { $allResourcesList += $destroyedResources }
    if ($movedResources) { $allResourcesList += $movedResources }
    
    $allModules = $allResourcesList | ForEach-Object {
        if ($_ -match '^(module\.[a-zA-Z0-9_]+)(\[[0-9]+\])?') {
            $Matches[0]
        }
    } | Where-Object { $_ } | Sort-Object -Unique
    
    $moduleCount = ($allModules | Measure-Object).Count
    Write-Host "Total modules touched: $moduleCount"
    Write-Host ""
    
    # Collect module data
    $moduleData = @{}
    foreach ($module in $allModules) {
        $escapedModule = [regex]::Escape($module)
        
        $modCreated = @($createdResources | Where-Object { $_ -match "^$escapedModule\." })
        $modChanged = @($changedResources | Where-Object { $_ -match "^$escapedModule\." })
        $modReplaced = @($replacedResources | Where-Object { $_ -match "^$escapedModule\." })
        $modDestroyed = @($destroyedResources | Where-Object { $_ -match "^$escapedModule\." })
        $modMoved = @($movedResources | Where-Object { $_ -match "^$escapedModule\." })
        
        $pattern = "$($modCreated.Count):$($modChanged.Count):$($modReplaced.Count):$($modDestroyed.Count):$($modMoved.Count)"
        
        $moduleData[$module] = @{
            Pattern = $pattern
            Created = $modCreated
            Changed = $modChanged
            Replaced = $modReplaced
            Destroyed = $modDestroyed
            Moved = $modMoved
        }
    }
    
    # Group by pattern
    $groups = $moduleData.GetEnumerator() | Group-Object { $_.Value.Pattern }
    $groupNum = 1
    
    foreach ($group in $groups) {
        $modules = @($group.Group | ForEach-Object { $_.Key })
        $firstModuleData = $group.Group[0].Value
        
        # Build action summary
        $summaryParts = @()
        if ($firstModuleData.Created.Count -gt 0) { $summaryParts += "$($firstModuleData.Created.Count) added" }
        if ($firstModuleData.Changed.Count -gt 0) { $summaryParts += "$($firstModuleData.Changed.Count) changed" }
        if ($firstModuleData.Replaced.Count -gt 0) { $summaryParts += "$($firstModuleData.Replaced.Count) replaced" }
        if ($firstModuleData.Destroyed.Count -gt 0) { $summaryParts += "$($firstModuleData.Destroyed.Count) destroyed" }
        if ($firstModuleData.Moved.Count -gt 0) { $summaryParts += "$($firstModuleData.Moved.Count) moved" }
        $actionSummary = $summaryParts -join ", "
        
        if ($modules.Count -gt 1) {
            Write-Host "  Group $groupNum ($($modules.Count) modules): " -NoNewline
            Write-Host $actionSummary
            foreach ($mod in $modules) {
                Write-Host "    - $mod"
            }
            
            # Show details with placeholder
            $firstModule = $modules[0]
            foreach ($resource in $firstModuleData.Created) {
                $suffix = $resource -replace "^module\.[^.]+\.", ""
                Write-Host "      {module}.$suffix" -ForegroundColor Green
                if ($Detail) {
                    Extract-ResourceChanges -ResourceName $resource -UsePlaceholder $true -PlaceholderModule $firstModule
                }
            }
            foreach ($resource in $firstModuleData.Changed) {
                $suffix = $resource -replace "^module\.[^.]+\.", ""
                Write-Host "      {module}.$suffix" -ForegroundColor Yellow
                if ($Detail) {
                    Extract-ResourceChanges -ResourceName $resource -UsePlaceholder $true -PlaceholderModule $firstModule
                }
            }
            foreach ($resource in $firstModuleData.Replaced) {
                $suffix = $resource -replace "^module\.[^.]+\.", ""
                Write-Host "      {module}.$suffix" -ForegroundColor Magenta
                if ($Detail) {
                    Extract-ResourceChanges -ResourceName $resource -UsePlaceholder $true -PlaceholderModule $firstModule
                }
            }
            foreach ($resource in $firstModuleData.Destroyed) {
                $suffix = $resource -replace "^module\.[^.]+\.", ""
                Write-Host "      {module}.$suffix" -ForegroundColor Red
            }
            foreach ($resource in $firstModuleData.Moved) {
                $suffix = $resource -replace "^module\.[^.]+\.", ""
                Write-Host "      {module}.$suffix" -ForegroundColor Blue
            }
        } else {
            Write-Host "  $($modules[0]): " -NoNewline
            Write-Host $actionSummary
            
            foreach ($resource in $firstModuleData.Created) {
                Write-Host "      $resource" -ForegroundColor Green
                if ($Detail) {
                    Extract-ResourceChanges -ResourceName $resource -UsePlaceholder $false -PlaceholderModule ""
                }
            }
            foreach ($resource in $firstModuleData.Changed) {
                Write-Host "      $resource" -ForegroundColor Yellow
                if ($Detail) {
                    Extract-ResourceChanges -ResourceName $resource -UsePlaceholder $false -PlaceholderModule ""
                }
            }
            foreach ($resource in $firstModuleData.Replaced) {
                Write-Host "      $resource" -ForegroundColor Magenta
                if ($Detail) {
                    Extract-ResourceChanges -ResourceName $resource -UsePlaceholder $false -PlaceholderModule ""
                }
            }
            foreach ($resource in $firstModuleData.Destroyed) {
                Write-Host "      $resource" -ForegroundColor Red
            }
            foreach ($resource in $firstModuleData.Moved) {
                Write-Host "      $resource" -ForegroundColor Blue
            }
        }
        $groupNum++
    }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
