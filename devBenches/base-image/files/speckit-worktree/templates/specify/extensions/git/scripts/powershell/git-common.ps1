#!/usr/bin/env pwsh
# Git-specific common functions for the git extension.
# Extracted from scripts/powershell/common.ps1 — contains only git-specific
# branch validation and detection logic.

function Test-HasGit {
    param([string]$RepoRoot = (Get-Location))
    try {
        if (-not (Test-Path (Join-Path $RepoRoot '.git'))) { return $false }
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $false }
        git -C $RepoRoot rev-parse --is-inside-work-tree 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Test-FeatureBranch {
    param(
        [string]$Branch,
        [bool]$HasGit = $true
    )

    # For non-git repos, we can't enforce branch naming but still provide output
    if (-not $HasGit) {
        Write-Warning "[specify] Warning: Git repository not detected; skipped branch validation"
        return $true
    }

    $featureSegment = ($Branch -split '/')[-1]

    # Reject malformed timestamps (7-digit date or no trailing slug)
    $hasMalformedTimestamp = ($featureSegment -match '^[0-9]{7}-[0-9]{6}-') -or
                            ($featureSegment -match '^(?:\d{7}|\d{8})-\d{6}$')
    if ($hasMalformedTimestamp) {
        Write-Output "ERROR: Not on a feature branch. Current branch: $Branch"
        Write-Output "Feature branches should be named like: 001-feature-name, 20260319-143022-feature-name, or <namespace>/001-feature-name"
        return $false
    }

    # Accept sequential (>=3 digits followed by hyphen) or timestamp (YYYYMMDD-HHMMSS-*)
    $isSequential = ($featureSegment -match '^[0-9]{3,}-') -and (-not $hasMalformedTimestamp)
    $isTimestamp = $featureSegment -match '^\d{8}-\d{6}-'

    if ($isSequential -or $isTimestamp) {
        return $true
    }

    Write-Output "ERROR: Not on a feature branch. Current branch: $Branch"
    Write-Output "Feature branches should be named like: 001-feature-name, 20260319-143022-feature-name, or <namespace>/001-feature-name"
    return $false
}
