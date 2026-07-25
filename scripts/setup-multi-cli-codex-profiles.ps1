[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Manifest,

    # Families to sync from the shared Desktop store. Defaults to every
    # non-personal family in the manifest (all work/company profiles);
    # personal profiles always remain isolated. Pass one or more family
    # names to restrict syncing to specific companies.
    [string[]]$Family = @(),

    [string]$MultiCliHome = (Join-Path $env:USERPROFILE "MultiCliProfiles"),

    [string]$SharedCodexHome = (Join-Path $env:USERPROFILE ".codex")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
    throw "OpenAI profile manifest not found: $Manifest"
}
if (-not (Test-Path -LiteralPath $SharedCodexHome -PathType Container)) {
    throw "Desktop Codex home not found: $SharedCodexHome"
}

$profiles = (Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json).profiles
$codexProfiles = Join-Path $MultiCliHome "codex"
New-Item -ItemType Directory -Path $codexProfiles -Force | Out-Null

function Test-ReparsePoint {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return [bool]((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Set-SharedDirectoryLink {
    param([string]$ProfileDir, [string]$Name)
    $source = Join-Path $SharedCodexHome $Name
    $link = Join-Path $ProfileDir $Name
    New-Item -ItemType Directory -Path $source -Force | Out-Null

    if (Test-ReparsePoint $link) {
        $actual = (Get-Item -LiteralPath $link -Force).Target
        if ($actual -eq $source) { return }
        throw "Existing link targets another location: $link -> $actual"
    }
    if (Test-Path -LiteralPath $link) {
        throw "Existing profile history must be migrated before linking: $link"
    }
    New-Item -ItemType Junction -Path $link -Target $source | Out-Null
}

function Set-SharedFileLink {
    param([string]$ProfileDir, [string]$Name)
    $source = Join-Path $SharedCodexHome $Name
    $link = Join-Path $ProfileDir $Name
    if (-not (Test-Path -LiteralPath $source)) {
        New-Item -ItemType File -Path $source -Force | Out-Null
    }

    if (Test-Path -LiteralPath $link) {
        $item = Get-Item -LiteralPath $link -Force
        if ($item.LinkType -eq "HardLink" -and @($item.Target) -contains $source) { return }
        throw "Existing profile history must be migrated before linking: $link"
    }
    # NTFS hard links require no elevation and keep both paths on the same
    # underlying append-only JSONL file.
    New-Item -ItemType HardLink -Path $link -Target $source | Out-Null
}

foreach ($profile in $profiles) {
    # Company/work identities share Desktop conversation history within their
    # family. Every personal profile has a unique family and remains fully
    # isolated.
    if ($Family.Count -gt 0) {
        if ($Family -notcontains $profile.family) { continue }
    } elseif ($profile.family -eq "personal") {
        continue
    }

    $profileDir = Join-Path $codexProfiles $profile.name
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    foreach ($name in @("sessions", "archived_sessions")) {
        Set-SharedDirectoryLink -ProfileDir $profileDir -Name $name
    }
    foreach ($name in @("history.jsonl", "session_index.jsonl")) {
        Set-SharedFileLink -ProfileDir $profileDir -Name $name
    }

    $metadata = [ordered]@{
        name = $profile.name
        email = $profile.email
        family = $profile.family
        aliases = @($profile.aliases)
        managedBy = "workBenches"
    } | ConvertTo-Json -Depth 4
    Set-Content -LiteralPath (Join-Path $profileDir ".profile.json") -Value $metadata -Encoding utf8
}

Write-Host "Multi-CLI Codex profiles synchronized under $codexProfiles"
Write-Host "Synced company profiles share history from $SharedCodexHome"
Write-Host "Credential files were not copied or linked."
