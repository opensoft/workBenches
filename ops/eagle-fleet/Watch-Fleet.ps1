param([Parameter(Mandatory=$true)][string]$Python)
$ErrorActionPreference='Stop'
Set-Location $PSScriptRoot
$watcher=[Threading.Mutex]::new($false,'Local\EagleFleetRunnerWatcher')
if(!$watcher.WaitOne(0)){exit 0}
try {
    while(!(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'STOP'))){
        $secure=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'service-auth.dpapi') -Raw | ConvertTo-SecureString
        try {
            $env:GH_TOKEN=[Net.NetworkCredential]::new('',$secure).Password
            & $Python (Join-Path $PSScriptRoot 'controller.py') 2>> (Join-Path $PSScriptRoot 'watcher-error.log')
        } finally {
            Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
            $secure.Dispose()
        }
        if(!(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'STOP'))){Start-Sleep -Seconds 15}
    }
} finally {$watcher.ReleaseMutex();$watcher.Dispose()}
