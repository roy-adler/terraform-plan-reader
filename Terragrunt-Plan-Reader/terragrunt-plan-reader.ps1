# Terragrunt Plan Reader (PowerShell version)
# Reads terragrunt/terraform log output and emits GitHub Actions ##[group] / ##[endgroup]
# with leading timestamp, bracketed stack prefix, and "terraform:" prefix stripped for readability.

param(
    [Parameter(Position = 0)]
    [string]$LogFile = ""
)

if ($args.Count -gt 1) {
    Write-Error "Usage: $MyInvocation.MyCommand.Name [logfile]"
    exit 1
}

$InputPath = $LogFile

$currentGroup = ""

function Remove-AnsiEscapes {
    param([string]$s)
    $s -replace '\x1b\[[0-9;]*m', ''
}

function Format-TerragruntLine {
    param([string]$raw)

    # Strip leading ISO timestamp (e.g. 2026-01-26T16:13:09.7526386Z )
    $raw = $raw -replace '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\s*', ''

    $clean = Remove-AnsiEscapes $raw

    # Match: [unit] terraform: ...
    if ($clean -match '\[(.+?)\]\s+terraform:') {
        $unit = $Matches[1]

        if ($unit -ne $currentGroup) {
            if ($currentGroup) { Write-Host '##[endgroup]' }
            Write-Host "##[group]$unit"
            $script:currentGroup = $unit
        }

        # Remove everything in brackets + "terraform:" prefix
        $out = $raw -replace '\[[^\]]+\]\s+.*?terraform:\s?', ''
        Write-Host $out
    } else {
        # Remove standalone [stack] prefix only
        $out = $raw -replace '\[[^\]]+\]\s+', ''
        Write-Host $out
    }
}

if ($InputPath) {
    if (-not (Test-Path -LiteralPath $InputPath)) {
        Write-Error "File not found: $InputPath"
        exit 1
    }
    Get-Content -LiteralPath $InputPath | ForEach-Object { Format-TerragruntLine $_ }
} else {
    $input | ForEach-Object { Format-TerragruntLine $_ }
}

if ($currentGroup) { Write-Host '##[endgroup]' }
