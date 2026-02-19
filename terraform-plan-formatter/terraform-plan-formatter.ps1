# Terraform Plan Formatter (PowerShell version)
# Reads Terraform plan log output and emits GitHub Actions ##[group] / ##[endgroup]
# with leading timestamp and ANSI codes stripped for readability in CI.
#
# Structure: Terraform refresh/init and footer notes are foldable; the actual
# plan (resource changes) is shown in full so you can focus on what matters.

param(
    [Parameter(Position = 0)]
    [string]$LogFile = ""
)

if ($args.Count -gt 1) {
    Write-Error "Usage: $MyInvocation.MyCommand.Name [logfile]"
    exit 1
}

$InputPath = $LogFile

# Set to $true to strip leading ISO timestamps for readability
$StripIsoTimestamp = $true

function Remove-AnsiEscapes {
    param([string]$s)
    # Strip ESC [ ... m sequences (standard ANSI)
    $s = $s -replace ("`x1b" + '\[[\d;]*m'), ''
    # Strip [ ... m when stored as literal text (e.g. in pipeline logs)
    # Use \[? to also catch corrupted ESC (when 0x1B becomes '[') leaving stray [[31m
    $s = $s -replace '\[?\[[\d;]*m', ''
    return $s
}

function Get-CleanedLine {
    param([string]$raw)
    if ($StripIsoTimestamp) {
        $raw = $raw -replace '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\s*', ''
    }
    $out = Remove-AnsiEscapes $raw
    # Strip "HH:MM:SS.mmm STDOUT " prefix (from Azure DevOps / script output)
    $out = $out -replace '^\d{1,2}:\d{2}:\d{2}\.\d+\s+STDOUT\s+', ''
    return $out
}

# Section states: preamble (foldable), plan (visible), footer (foldable)
$state = 'preamble'
$pendingLines = [System.Collections.Generic.List[string]]::new()

function Flush-Preamble {
    if ($pendingLines.Count -gt 0) {
        Write-Host '##[group]Terraform Refresh & Init'
        foreach ($l in $pendingLines) { Write-Host $l }
        Write-Host '##[endgroup]'
        $pendingLines.Clear()
    }
}

function Flush-Footer {
    if ($pendingLines.Count -gt 0) {
        Write-Host '##[group]Notes & Warnings'
        foreach ($l in $pendingLines) { Write-Host $l }
        Write-Host '##[endgroup]'
        $pendingLines.Clear()
    }
}

function Process-Line {
    param([string]$raw)
    $cleaned = Get-CleanedLine $raw

    # Detect plan start (real changes section) - only when still in preamble
    if ($state -eq 'preamble' -and ($cleaned -match 'Terraform used the selected providers|Terraform will perform the following actions')) {
        Flush-Preamble
        $script:state = 'plan'
    }

    # Detect plan end (summary or no-changes)
    if ($state -eq 'plan' -and ($cleaned -match 'Plan:.*(?:to add|to change|to destroy)' -or $cleaned -match 'No changes\. Your infrastructure')) {
        Write-Host $cleaned
        $script:state = 'footer'
        return
    }

    switch ($state) {
        'preamble' { [void]$pendingLines.Add($cleaned) }
        'plan'    { Write-Host $cleaned }
        'footer'  { [void]$pendingLines.Add($cleaned) }
    }
}

if ($InputPath) {
    if (-not (Test-Path -LiteralPath $InputPath)) {
        Write-Error "File not found: $InputPath"
        exit 1
    }
    Get-Content -LiteralPath $InputPath | ForEach-Object { Process-Line $_ }
} else {
    $input | ForEach-Object { Process-Line $_ }
}

if ($state -eq 'preamble') { Flush-Preamble }
elseif ($state -eq 'footer') { Flush-Footer }
