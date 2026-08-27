#!/usr/bin/env pwsh
# Git extension: create-new-feature.ps1
# Adapted from core scripts/powershell/create-new-feature.ps1 for extension layout.
# Sources common.ps1 from the project's installed scripts, falling back to
# git-common.ps1 for minimal git helpers.
[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$AllowExistingBranch,
    [switch]$DryRun,
    [string]$ShortName,
    [Parameter()]
    [long]$Number = 0,
    [switch]$Timestamp,
    [switch]$Help,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$FeatureDescription
)
$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host "Usage: ./create-new-feature.ps1 [-Json] [-DryRun] [-AllowExistingBranch] [-ShortName <name>] [-Number N] [-Timestamp] <feature description>"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Json               Output in JSON format"
    Write-Host "  -DryRun             Compute branch name without creating the branch"
    Write-Host "  -AllowExistingBranch  Switch to branch if it already exists instead of failing"
    Write-Host "  -ShortName <name>   Provide a custom short name (2-4 words) for the branch"
    Write-Host "  -Number N           Specify branch number manually (overrides auto-detection)"
    Write-Host "  -Timestamp          Use timestamp prefix (YYYYMMDD-HHMMSS) instead of sequential numbering"
    Write-Host "  -Help               Show this help message"
    Write-Host ""
    Write-Host "Environment variables:"
    Write-Host "  GIT_BRANCH_NAME     Use this exact branch name, bypassing all prefix/suffix generation"
    Write-Host "  SPECKIT_GIT_BRANCH_TEMPLATE  Override branch_template"
    Write-Host "  SPECKIT_GIT_BRANCH_PREFIX    Override branch_prefix"
    Write-Host ""
    Write-Host "Configuration:"
    Write-Host "  branch_template     Optional template with {author}, {app}, {number}, {slug}"
    Write-Host "  branch_prefix       Optional namespace prepended to branch_template"
    Write-Host ""
    exit 0
}

if (-not $FeatureDescription -or $FeatureDescription.Count -eq 0) {
    Write-Error "Usage: ./create-new-feature.ps1 [-Json] [-DryRun] [-AllowExistingBranch] [-ShortName <name>] [-Number N] [-Timestamp] <feature description>"
    exit 1
}

$featureDesc = ($FeatureDescription -join ' ').Trim()

if ([string]::IsNullOrWhiteSpace($featureDesc)) {
    Write-Error "Error: Feature description cannot be empty or contain only whitespace"
    exit 1
}

function Get-HighestNumberFromSpecs {
    param([string]$SpecsDir)

    [long]$highest = 0
    if (Test-Path $SpecsDir) {
        Get-ChildItem -Path $SpecsDir -Directory | ForEach-Object {
            if ($_.Name -match '^(\d{3,})-' -and $_.Name -notmatch '^\d{8}-\d{6}-') {
                [long]$num = 0
                if ([long]::TryParse($matches[1], [ref]$num) -and $num -gt $highest) {
                    $highest = $num
                }
            }
        }
    }
    return $highest
}

function Get-HighestNumberFromNames {
    param(
        [string[]]$Names,
        [string]$ScopePrefix = ''
    )

    [long]$highest = 0
    foreach ($name in $Names) {
        if ($ScopePrefix -and -not $name.StartsWith($ScopePrefix, [System.StringComparison]::Ordinal)) {
            continue
        }
        if ($ScopePrefix) {
            $name = $name.Substring($ScopePrefix.Length)
        }
        $name = ($name -split '/')[-1]
        $hasTimestampPrefix = $name -match '^\d{8}-\d{6}-'
        $hasMalformedTimestamp = ($name -match '^\d{7}-\d{6}-') -or ($name -match '^(?:\d{7}|\d{8})-\d{6}$')
        if ($name -match '^(\d{3,})-' -and -not $hasTimestampPrefix -and -not $hasMalformedTimestamp) {
            [long]$num = 0
            if ([long]::TryParse($matches[1], [ref]$num) -and $num -gt $highest) {
                $highest = $num
            }
        }
    }
    return $highest
}

function Get-HighestNumberFromBranches {
    param([string]$ScopePrefix = '')

    try {
        $branches = git branch -a 2>$null
        if ($LASTEXITCODE -eq 0 -and $branches) {
            $cleanNames = $branches | ForEach-Object {
                $_.Trim() -replace '^[+*]?\s+', '' -replace '^remotes/[^/]+/', ''
            }
            return Get-HighestNumberFromNames -Names $cleanNames -ScopePrefix $ScopePrefix
        }
    } catch {
        Write-Verbose "Could not check Git branches: $_"
    }
    return 0
}

function Get-HighestNumberFromRemoteRefs {
    param([string]$ScopePrefix = '')

    [long]$highest = 0
    try {
        $remotes = git remote 2>$null
        if ($remotes) {
            foreach ($remote in $remotes) {
                $env:GIT_TERMINAL_PROMPT = '0'
                $refs = git ls-remote --heads $remote 2>$null
                $env:GIT_TERMINAL_PROMPT = $null
                if ($LASTEXITCODE -eq 0 -and $refs) {
                    $refNames = $refs | ForEach-Object {
                        if ($_ -match 'refs/heads/(.+)$') { $matches[1] }
                    } | Where-Object { $_ }
                    $remoteHighest = Get-HighestNumberFromNames -Names $refNames -ScopePrefix $ScopePrefix
                    if ($remoteHighest -gt $highest) { $highest = $remoteHighest }
                }
            }
        }
    } catch {
        Write-Verbose "Could not query remote refs: $_"
    }
    return $highest
}

function Get-NextBranchNumber {
    param(
        [string]$SpecsDir,
        [switch]$SkipFetch,
        [string]$ScopePrefix = ''
    )

    if ($SkipFetch) {
        $highestBranch = Get-HighestNumberFromBranches -ScopePrefix $ScopePrefix
        $highestRemote = Get-HighestNumberFromRemoteRefs -ScopePrefix $ScopePrefix
        $highestBranch = [Math]::Max($highestBranch, $highestRemote)
    } else {
        try {
            git fetch --all --prune 2>$null | Out-Null
        } catch { }
        $highestBranch = Get-HighestNumberFromBranches -ScopePrefix $ScopePrefix
    }

    $highestSpec = if ($ScopePrefix) { 0 } else { Get-HighestNumberFromSpecs -SpecsDir $SpecsDir }
    $maxNum = [Math]::Max($highestBranch, $highestSpec)
    return $maxNum + 1
}

function ConvertTo-CleanBranchName {
    param([string]$Name)
    return $Name.ToLower() -replace '[^a-z0-9]', '-' -replace '-{2,}', '-' -replace '^-', '' -replace '-$', ''
}

# ---------------------------------------------------------------------------
# Source common.ps1 from the project's installed scripts.
# Search locations in priority order:
#  1. .specify/scripts/powershell/common.ps1 under the project root
#  2. scripts/powershell/common.ps1 under the project root (source checkout)
#  3. git-common.ps1 next to this script (minimal fallback)
# ---------------------------------------------------------------------------
function Find-ProjectRoot {
    param([string]$StartDir)
    $current = Resolve-Path $StartDir
    while ($true) {
        foreach ($marker in @('.specify', '.git')) {
            if (Test-Path (Join-Path $current $marker)) {
                return $current
            }
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) { return $null }
        $current = $parent
    }
}

$projectRoot = Find-ProjectRoot -StartDir $PSScriptRoot
$commonLoaded = $false

if ($projectRoot) {
    $candidates = @(
        (Join-Path $projectRoot ".specify/scripts/powershell/common.ps1"),
        (Join-Path $projectRoot "scripts/powershell/common.ps1")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            . $candidate
            $commonLoaded = $true
            break
        }
    }
}

if (-not $commonLoaded -and (Test-Path "$PSScriptRoot/git-common.ps1")) {
    . "$PSScriptRoot/git-common.ps1"
    $commonLoaded = $true
}

if (-not $commonLoaded) {
    throw "Unable to locate common script file. Please ensure the Specify core scripts are installed."
}

# Resolve repository root
if (Get-Command Get-RepoRoot -ErrorAction SilentlyContinue) {
    $repoRoot = Get-RepoRoot
} elseif ($projectRoot) {
    $repoRoot = $projectRoot
} else {
    throw "Could not determine repository root."
}

try {
    git -C $repoRoot rev-parse --is-inside-work-tree 2>$null | Out-Null
    $hasGit = ($LASTEXITCODE -eq 0)
} catch {
    $hasGit = $false
}

$configFile = Join-Path $repoRoot '.specify/extensions/git/git-config.yml'

function Get-GitExtensionConfigValue {
    param(
        [string]$Key,
        [string]$DefaultValue,
        [string]$EnvOverrideName
    )

    if ($EnvOverrideName) {
        $overrideValue = [Environment]::GetEnvironmentVariable($EnvOverrideName)
        if (-not [string]::IsNullOrWhiteSpace($overrideValue)) {
            return $overrideValue.Trim()
        }
    }

    if (Test-Path $configFile) {
        $pattern = "^\s*$([regex]::Escape($Key))\s*:\s*(.+?)\s*$"
        $resolvedValue = $null
        foreach ($line in Get-Content $configFile) {
            if ($line -match $pattern) {
                $resolvedValue = $matches[1]
            }
        }
        if ($resolvedValue) {
            $resolvedValue = ($resolvedValue -replace '\s+#.*$', '').Trim()
            $resolvedValue = $resolvedValue.Trim("'")
            $resolvedValue = $resolvedValue.Trim('"')
            if (-not [string]::IsNullOrWhiteSpace($resolvedValue)) {
                return $resolvedValue
            }
        }
    }

    return $DefaultValue
}

function ConvertTo-BranchToken {
    param(
        [string]$Value,
        [string]$Fallback
    )

    $cleaned = ConvertTo-CleanBranchName -Name $Value
    if ($cleaned) { return $cleaned }
    return $Fallback
}

function Get-GitAuthorToken {
    $author = ''
    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            $author = (git config user.name 2>$null | Out-String).Trim()
        } catch {
            Write-Verbose "Could not read Git user.name: $_"
        }
        if (-not $author) {
            try {
                $email = (git config user.email 2>$null | Out-String).Trim()
                if ($email) { $author = ($email -split '@')[0] }
            } catch {
                Write-Verbose "Could not read Git user.email: $_"
            }
        }
    }
    if (-not $author) {
        $author = if ($env:USER) { $env:USER } elseif ($env:USERNAME) { $env:USERNAME } else { 'unknown' }
    }
    return ConvertTo-BranchToken -Value $author -Fallback 'unknown'
}

function Get-AppToken {
    return ConvertTo-BranchToken -Value (Split-Path $repoRoot -Leaf) -Fallback 'app'
}

function Resolve-BranchTemplate {
    param(
        [string]$Template,
        [string]$Prefix
    )

    $normalizedPrefix = $Prefix.TrimEnd('/')
    if (-not $normalizedPrefix) { return $Template }
    if ($Template -eq $normalizedPrefix -or $Template.StartsWith("$normalizedPrefix/", [System.StringComparison]::Ordinal)) {
        return $Template
    }
    return "$normalizedPrefix/$Template"
}

function Expand-BranchTemplate {
    param(
        [string]$Template,
        [string]$FeatureNum,
        [string]$BranchSuffix
    )

    $rendered = $Template.Replace('{author}', $authorToken)
    $rendered = $rendered.Replace('{app}', $appToken)
    $rendered = $rendered.Replace('{number}', $FeatureNum)
    $rendered = $rendered.Replace('{slug}', $BranchSuffix)
    return $rendered
}

function Assert-BranchTemplateValid {
    param([string]$Template)

    $unsupported = $Template
    foreach ($token in @('{author}', '{app}', '{number}', '{slug}')) {
        $unsupported = $unsupported.Replace($token, '')
    }
    if ($unsupported.Contains('{') -or $unsupported.Contains('}')) {
        throw "branch_template contains an unsupported token; supported tokens are {author}, {app}, {number}, and {slug}."
    }
    if (-not $Template.Contains('{number}')) {
        throw "branch_template must include the {number} token so generated branches remain valid feature branches."
    }
    $numberIndex = $Template.IndexOf('{number}', [System.StringComparison]::Ordinal)
    $slugIndex = $Template.IndexOf('{slug}', [System.StringComparison]::Ordinal)
    if ($slugIndex -ge 0 -and $slugIndex -lt $numberIndex) {
        throw "branch_template must not place {slug} before {number}; use {slug} only in the final feature segment."
    }
    $featureSegment = ($Template -split '/')[-1]
    if (-not $featureSegment.StartsWith('{number}-', [System.StringComparison]::Ordinal)) {
        throw "branch_template must put {number}- at the start of the final path segment so generated branches remain valid feature branches."
    }
}

function New-BranchName {
    param(
        [string]$FeatureNum,
        [string]$BranchSuffix
    )

    return Expand-BranchTemplate -Template $branchTemplate -FeatureNum $FeatureNum -BranchSuffix $BranchSuffix
}

function Get-BranchScopePrefix {
    param(
        [string]$Template,
        [string]$BranchSuffix
    )

    $numberIndex = $Template.IndexOf('{number}', [System.StringComparison]::Ordinal)
    $slugIndex = $Template.IndexOf('{slug}', [System.StringComparison]::Ordinal)
    $indexes = @($numberIndex, $slugIndex) | Where-Object { $_ -ge 0 } | Sort-Object
    if (-not $indexes) { return '' }
    $prefix = $Template.Substring(0, $indexes[0])
    return Expand-BranchTemplate -Template $prefix -FeatureNum '' -BranchSuffix $BranchSuffix
}

function Get-FeatureNumberFromBranchName {
    param([string]$BranchName)

    $featureSegment = ($BranchName -split '/')[-1]
    if ($featureSegment -match '^(\d{8}-\d{6})-') {
        return $matches[1]
    }
    if ($featureSegment -match '^(\d+)-') {
        return $matches[1]
    }
    return $BranchName
}

function Resolve-PathFromRepoRoot {
    param([string]$RawPath)

    if ([System.IO.Path]::IsPathRooted($RawPath)) {
        return [System.IO.Path]::GetFullPath($RawPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $RawPath))
}

function Resolve-GitCommonDir {
    $commonDir = git rev-parse --git-common-dir 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commonDir)) {
        return $null
    }
    $commonDir = $commonDir.Trim()
    if ([System.IO.Path]::IsPathRooted($commonDir)) {
        return [System.IO.Path]::GetFullPath($commonDir)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $commonDir))
}

function Resolve-BaseRef {
    param([string]$BaseRef)

    try {
        git show-ref --verify --quiet "refs/heads/$BaseRef" 2>$null
        if ($LASTEXITCODE -eq 0) { return $BaseRef }
    } catch { }

    try {
        git rev-parse --verify --quiet "$BaseRef^{commit}" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $BaseRef }
    } catch { }

    try {
        git show-ref --verify --quiet "refs/remotes/origin/$BaseRef" 2>$null
        if ($LASTEXITCODE -eq 0) { return "origin/$BaseRef" }
    } catch { }

    return $null
}

function Find-WorktreePathForBranch {
    param([string]$BranchName)

    try {
        $currentWorktree = $null
        $lines = git worktree list --porcelain 2>$null
        foreach ($line in $lines) {
            if ($line -like 'worktree *') {
                $currentWorktree = $line.Substring(9)
            } elseif ($line -eq "branch refs/heads/$BranchName") {
                return $currentWorktree
            }
        }
    } catch { }

    return $null
}

function Write-LastWorktreeState {
    param(
        [string]$BranchName,
        [string]$WorktreePath,
        [string]$BaseBranch
    )

    $commonDir = Resolve-GitCommonDir
    if (-not $commonDir) {
        return
    }

    $stateFile = Join-Path $commonDir 'speckit-last-worktree.json'
    $payload = [ordered]@{
        BRANCH_NAME = $BranchName
        WORKTREE_PATH = $WorktreePath
        BASE_BRANCH = $BaseBranch
        REPO_ROOT = $repoRoot
        UPDATED_AT = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    [PSCustomObject]$payload | ConvertTo-Json -Compress | Set-Content -Path $stateFile -Encoding UTF8
}

Set-Location $repoRoot

$specsDir = Join-Path $repoRoot 'specs'
$defaultWorktreeRoot = "../$((Split-Path $repoRoot -Leaf))-worktrees"
$checkoutMode = (Get-GitExtensionConfigValue -Key 'checkout_mode' -DefaultValue 'branch' -EnvOverrideName 'SPECKIT_GIT_CHECKOUT_MODE').ToLowerInvariant()
$branchNumbering = (Get-GitExtensionConfigValue -Key 'branch_numbering' -DefaultValue 'sequential' -EnvOverrideName 'SPECKIT_GIT_BRANCH_NUMBERING').ToLowerInvariant()
$baseBranch = Get-GitExtensionConfigValue -Key 'base_branch' -DefaultValue 'main' -EnvOverrideName 'SPECKIT_GIT_BASE_BRANCH'
$worktreeRootRaw = Get-GitExtensionConfigValue -Key 'worktree_root' -DefaultValue $defaultWorktreeRoot -EnvOverrideName 'SPECKIT_GIT_WORKTREE_ROOT'
$worktreeRoot = Resolve-PathFromRepoRoot -RawPath $worktreeRootRaw
if ($checkoutMode -notin @('branch', 'worktree')) {
    throw "checkout_mode must be 'branch' or 'worktree' (got '$checkoutMode')"
}

if ($branchNumbering -notin @('sequential', 'timestamp')) {
    throw "branch_numbering must be 'sequential' or 'timestamp' (got '$branchNumbering')"
}

if ($branchNumbering -eq 'timestamp') {
    $Timestamp = $true
}

function Get-BranchName {
    param([string]$Description)

    $stopWords = @(
        'i', 'a', 'an', 'the', 'to', 'for', 'of', 'in', 'on', 'at', 'by', 'with', 'from',
        'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had',
        'do', 'does', 'did', 'will', 'would', 'should', 'could', 'can', 'may', 'might', 'must', 'shall',
        'this', 'that', 'these', 'those', 'my', 'your', 'our', 'their',
        'want', 'need', 'add', 'get', 'set'
    )

    $cleanName = $Description.ToLower() -replace '[^a-z0-9\s]', ' '
    $words = $cleanName -split '\s+' | Where-Object { $_ }

    $meaningfulWords = @()
    foreach ($word in $words) {
        if ($stopWords -contains $word) { continue }
        if ($word.Length -ge 3) {
            $meaningfulWords += $word
        } elseif ($Description -cmatch "\b$($word.ToUpper())\b") {
            $meaningfulWords += $word
        }
    }

    if ($meaningfulWords.Count -gt 0) {
        $maxWords = if ($meaningfulWords.Count -eq 4) { 4 } else { 3 }
        $result = ($meaningfulWords | Select-Object -First $maxWords) -join '-'
        return $result
    } else {
        $result = ConvertTo-CleanBranchName -Name $Description
        $fallbackWords = ($result -split '-') | Where-Object { $_ } | Select-Object -First 3
        return [string]::Join('-', $fallbackWords)
    }
}

# Check for GIT_BRANCH_NAME env var override (exact branch name, no prefix/suffix)
if ($env:GIT_BRANCH_NAME) {
    $branchName = $env:GIT_BRANCH_NAME
    # Check 244-byte limit (UTF-8) for override names
    $branchNameUtf8ByteCount = [System.Text.Encoding]::UTF8.GetByteCount($branchName)
    if ($branchNameUtf8ByteCount -gt 244) {
        throw "GIT_BRANCH_NAME must be 244 bytes or fewer in UTF-8. Provided value is $branchNameUtf8ByteCount bytes; please supply a shorter override branch name."
    }
    $featureNum = Get-FeatureNumberFromBranchName -BranchName $branchName
} else {
    $branchTemplateRaw = Get-GitExtensionConfigValue -Key 'branch_template' -DefaultValue '{number}-{slug}' -EnvOverrideName 'SPECKIT_GIT_BRANCH_TEMPLATE'
    $branchPrefix = Get-GitExtensionConfigValue -Key 'branch_prefix' -DefaultValue '' -EnvOverrideName 'SPECKIT_GIT_BRANCH_PREFIX'
    $authorToken = Get-GitAuthorToken
    $appToken = Get-AppToken
    $branchTemplate = Resolve-BranchTemplate -Template $branchTemplateRaw -Prefix $branchPrefix
    Assert-BranchTemplateValid -Template $branchTemplate

    if ($ShortName) {
        $branchSuffix = ConvertTo-CleanBranchName -Name $ShortName
    } else {
        $branchSuffix = Get-BranchName -Description $featureDesc
    }

    if ([string]::IsNullOrWhiteSpace($branchSuffix)) {
        Write-Error "Error: Feature branch name must include at least one alphanumeric slug word. Provide -ShortName with letters or digits."
        exit 1
    }

    if ($Timestamp -and $PSBoundParameters.ContainsKey('Number')) {
        Write-Warning "[specify] Warning: -Number is ignored when -Timestamp is used"
        $Number = 0
    }

    if ($Timestamp) {
        $featureNum = Get-Date -Format 'yyyyMMdd-HHmmss'
        $branchName = New-BranchName -FeatureNum $featureNum -BranchSuffix $branchSuffix
    } else {
        $branchScopePrefix = Get-BranchScopePrefix -Template $branchTemplate -BranchSuffix $branchSuffix
        if (-not $PSBoundParameters.ContainsKey('Number')) {
            if ($DryRun -and $hasGit) {
                $Number = Get-NextBranchNumber -SpecsDir $specsDir -SkipFetch -ScopePrefix $branchScopePrefix
            } elseif ($DryRun) {
                $Number = if ($branchScopePrefix) { 1 } else { (Get-HighestNumberFromSpecs -SpecsDir $specsDir) + 1 }
            } elseif ($hasGit) {
                $Number = Get-NextBranchNumber -SpecsDir $specsDir -SkipFetch -ScopePrefix $branchScopePrefix
            } else {
                $Number = if ($branchScopePrefix) { 1 } else { (Get-HighestNumberFromSpecs -SpecsDir $specsDir) + 1 }
            }
        }

        $featureNum = ('{0:000}' -f $Number)
        $branchName = New-BranchName -FeatureNum $featureNum -BranchSuffix $branchSuffix
    }
}

function Get-Utf8ByteCount {
    param([string]$Value)
    return [System.Text.Encoding]::UTF8.GetByteCount($Value)
}

function Remove-LastTextElement {
    param([string]$Value)

    $textElementStarts = [System.Globalization.StringInfo]::ParseCombiningCharacters($Value)
    if ($textElementStarts.Length -le 1) {
        return ''
    }
    return $Value.Substring(0, $textElementStarts[$textElementStarts.Length - 1])
}

$maxBranchLength = 244
$branchNameUtf8ByteCount = Get-Utf8ByteCount $branchName
if ($branchNameUtf8ByteCount -gt $maxBranchLength) {
    $originalBranchName = $branchName
    $truncatedSuffix = $branchSuffix
    while ((Get-Utf8ByteCount -Value $branchName) -gt $maxBranchLength -and $truncatedSuffix.Length -gt 0) {
        $truncatedSuffix = (Remove-LastTextElement -Value $truncatedSuffix) -replace '-$', ''
        $branchName = New-BranchName -FeatureNum $featureNum -BranchSuffix $truncatedSuffix
    }
    $featureSegment = ($branchName -split '/')[-1]
    if ([string]::IsNullOrWhiteSpace($truncatedSuffix)) {
        throw "Branch name truncation removed the feature slug; shorten branch_prefix or branch_template."
    }
    if ($featureSegment -eq "$featureNum-") {
        throw "Branch name truncation left the generated branch ending at the number separator; shorten branch_prefix or branch_template."
    }
    if ((Get-Utf8ByteCount -Value $branchName) -gt $maxBranchLength) {
        throw "Branch template prefix exceeds GitHub's 244-byte branch name limit."
    }

    Write-Warning "[specify] Branch name exceeded GitHub's 244-byte limit"
    Write-Warning "[specify] Original: $originalBranchName ($branchNameUtf8ByteCount bytes)"
    Write-Warning "[specify] Truncated to: $branchName ($(Get-Utf8ByteCount $branchName) bytes)"
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    git check-ref-format --branch $branchName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Invalid Git branch name: $branchName"
    }
}

$worktreePath = $null
if ($checkoutMode -eq 'worktree') {
    $worktreePath = Join-Path $worktreeRoot $branchName
}

if (-not $DryRun) {
    if ($hasGit) {
        if ($checkoutMode -eq 'worktree') {
            $existingWorktree = Find-WorktreePathForBranch -BranchName $branchName
            if ($existingWorktree) {
                if ($AllowExistingBranch) {
                    $worktreePath = $existingWorktree
                } elseif ($Timestamp) {
                    Write-Error "Error: Branch '$branchName' already exists in worktree '$existingWorktree'. Rerun to get a new timestamp or use a different -ShortName."
                    exit 1
                } else {
                    Write-Error "Error: Branch '$branchName' is already checked out in worktree '$existingWorktree'."
                    exit 1
                }
            } else {
                $existingBranch = git branch --list $branchName 2>$null
                if ($existingBranch) {
                    if ($AllowExistingBranch) {
                        if (Test-Path $worktreePath) {
                            Write-Error "Error: Worktree path '$worktreePath' already exists. Please remove it or configure a different worktree_root."
                            exit 1
                        }
                        New-Item -ItemType Directory -Force -Path (Split-Path $worktreePath -Parent) | Out-Null
                        $worktreeCreateError = git worktree add $worktreePath $branchName 2>&1 | Out-String
                        if ($LASTEXITCODE -ne 0) {
                            Write-Error "Error: Failed to add worktree '$worktreePath' for existing branch '$branchName'.`n$($worktreeCreateError.Trim())"
                            exit 1
                        }
                    } elseif ($Timestamp) {
                        Write-Error "Error: Branch '$branchName' already exists. Rerun to get a new timestamp or use a different -ShortName."
                        exit 1
                    } else {
                        Write-Error "Error: Branch '$branchName' already exists. Please use a different feature name or specify a different number with -Number."
                        exit 1
                    }
                } else {
                    $resolvedBaseRef = Resolve-BaseRef -BaseRef $baseBranch
                    if (-not $resolvedBaseRef) {
                        Write-Error "Error: Base branch '$baseBranch' does not exist locally or on origin."
                        exit 1
                    }
                    if (Test-Path $worktreePath) {
                        Write-Error "Error: Worktree path '$worktreePath' already exists. Please remove it or configure a different worktree_root."
                        exit 1
                    }
                    New-Item -ItemType Directory -Force -Path (Split-Path $worktreePath -Parent) | Out-Null
                    $worktreeCreateError = git worktree add -b $branchName $worktreePath $resolvedBaseRef 2>&1 | Out-String
                    if ($LASTEXITCODE -ne 0) {
                        Write-Error "Error: Failed to create feature worktree '$worktreePath' from '$resolvedBaseRef'.`n$($worktreeCreateError.Trim())"
                        exit 1
                    }
                }
            }
        } else {
            $branchCreated = $false
            $branchCreateError = ''
            try {
                $branchCreateError = git checkout -q -b $branchName 2>&1 | Out-String
                if ($LASTEXITCODE -eq 0) {
                    $branchCreated = $true
                }
            } catch {
                $branchCreateError = $_.Exception.Message
            }

            if (-not $branchCreated) {
                $currentBranch = ''
                try { $currentBranch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim() } catch {}
                $existingBranch = git branch --list $branchName 2>$null
                if ($existingBranch) {
                    if ($AllowExistingBranch) {
                        if ($currentBranch -eq $branchName) {
                            # Already on the target branch
                        } else {
                            $switchBranchError = git checkout -q $branchName 2>&1 | Out-String
                            if ($LASTEXITCODE -ne 0) {
                                if ($switchBranchError) {
                                    Write-Error "Error: Branch '$branchName' exists but could not be checked out.`n$($switchBranchError.Trim())"
                                } else {
                                    Write-Error "Error: Branch '$branchName' exists but could not be checked out. Resolve any uncommitted changes or conflicts and try again."
                                }
                                exit 1
                            }
                        }
                    } elseif ($Timestamp) {
                        Write-Error "Error: Branch '$branchName' already exists. Rerun to get a new timestamp or use a different -ShortName."
                        exit 1
                    } else {
                        Write-Error "Error: Branch '$branchName' already exists. Please use a different feature name or specify a different number with -Number."
                        exit 1
                    }
                } else {
                    if ($branchCreateError) {
                        Write-Error "Error: Failed to create git branch '$branchName'.`n$($branchCreateError.Trim())"
                    } else {
                        Write-Error "Error: Failed to create git branch '$branchName'. Please check your git configuration and try again."
                    }
                    exit 1
                }
            }
        }
    } else {
        if ($Json) {
            [Console]::Error.WriteLine("[specify] Warning: Git repository not detected; skipped $checkoutMode creation for $branchName")
        } else {
            Write-Warning "[specify] Warning: Git repository not detected; skipped $checkoutMode creation for $branchName"
        }
    }

    $env:SPECIFY_FEATURE = $branchName
    if ($checkoutMode -eq 'worktree' -and $worktreePath) {
        $env:SPECIFY_FEATURE_WORKTREE = $worktreePath
        Write-LastWorktreeState -BranchName $branchName -WorktreePath $worktreePath -BaseBranch $baseBranch
    }
}

if ($Json) {
    $obj = [ordered]@{
        BRANCH_NAME = $branchName
        FEATURE_NUM = $featureNum
        CHECKOUT_MODE = $checkoutMode
        HAS_GIT = $hasGit
    }
    if ($checkoutMode -eq 'worktree') {
        $obj['BASE_BRANCH'] = $baseBranch
        $obj['WORKTREE_PATH'] = $worktreePath
    }
    if ($DryRun) {
        $obj['DRY_RUN'] = $true
    }
    [PSCustomObject]$obj | ConvertTo-Json -Compress
} else {
    Write-Output "BRANCH_NAME: $branchName"
    Write-Output "FEATURE_NUM: $featureNum"
    Write-Output "CHECKOUT_MODE: $checkoutMode"
    Write-Output "HAS_GIT: $hasGit"
    if ($checkoutMode -eq 'worktree') {
        Write-Output "BASE_BRANCH: $baseBranch"
        Write-Output "WORKTREE_PATH: $worktreePath"
    }
    if (-not $DryRun) {
        Write-Output "SPECIFY_FEATURE environment variable set to: $branchName"
    }
}
