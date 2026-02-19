# Terraform Plan Formatter (PowerShell version)
# Reads Terraform plan log output and emits GitHub Actions ##[group] / ##[endgroup]
# with leading timestamp and ANSI codes stripped for readability in CI.

param(
    [Parameter(Position = 0)]
    [string]$LogFile = ""
)

if ($args.Count -gt 1) {
    Write-Error "Usage: $MyInvocation.MyCommand.Name [logfile]"
    exit 1
}

$InputPath = $LogFile

# Set to $true to strip leading ISO timestamps (e.g. 2026-01-26T16:13:09.7526386Z ) for readability
$StripIsoTimestamp = $true

function Remove-AnsiEscapes {
    param([string]$s)
    # Strip ESC [ ... m sequences (standard ANSI)
    $s = $s -replace '\x1b\[[0-9;]*m', ''
    # Strip [ ... m when stored as literal text (e.g. in pipeline logs)
    $s = $s -replace '\[[0-9;]*m', ''
    return $s
}

function Format-TerraformLine {
    param([string]$raw)

    if ($StripIsoTimestamp) {
        $raw = $raw -replace '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\s*', ''
    }

    $out = Remove-AnsiEscapes $raw
    # Strip "HH:MM:SS.mmm STDOUT " prefix (from Azure DevOps / script output)
    $out = $out -replace '^\d{1,2}:\d{2}:\d{2}\.\d+\s+STDOUT\s+', ''
    Write-Host $out
}

Write-Host '##[group]Terraform Plan'

if ($InputPath) {
    if (-not (Test-Path -LiteralPath $InputPath)) {
        Write-Host '##[endgroup]'
        Write-Error "File not found: $InputPath"
        exit 1
    }
    Get-Content -LiteralPath $InputPath | ForEach-Object { Format-TerraformLine $_ }
} else {
    $input | ForEach-Object { Format-TerraformLine $_ }
}

Write-Host '##[endgroup]'
