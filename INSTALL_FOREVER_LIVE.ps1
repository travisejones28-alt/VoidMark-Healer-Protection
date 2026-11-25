# Links this repository into WoW Forever as AddOns\VoidMarkHealer.
# The repo folder can live anywhere (e.g. C:\WoW Forever Addons\VoidMark-Healer).
# Saved settings live in WTF\...\SavedVariables and are never touched.
[CmdletBinding(SupportsShouldProcess = $true)]
param([string]$ClientRoot = 'C:\Program Files (x86)\World of Warcraft\_forever_')
$ErrorActionPreference = 'Stop'

$source = $PSScriptRoot
if (!(Test-Path -LiteralPath (Join-Path $source 'VoidMarkHealer.toc'))) {
    throw "VoidMarkHealer.toc not found next to this script. Pull the latest GitHub update first."
}
$addons = Join-Path $ClientRoot 'Interface\AddOns'
if (!(Test-Path -LiteralPath $addons)) { throw "AddOns folder not found: $addons" }
$target = Join-Path $addons 'VoidMarkHealer'
$existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue

if ($existing) {
    if ($existing.LinkType -eq 'Junction') {
        $current = [IO.Path]::GetFullPath([string]$existing.Target).TrimEnd('\')
        if ($current -ieq [IO.Path]::GetFullPath($source).TrimEnd('\')) {
            Write-Host "Already linked: $target -> $source" -ForegroundColor Green
            return
        }
        if ($PSCmdlet.ShouldProcess($target, 'Replace old junction')) { [IO.Directory]::Delete($target) }
    } else {
        $backup = Join-Path $ClientRoot ('VoidMarkHealer-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        if ($PSCmdlet.ShouldProcess($target, "Move old copy to $backup")) { Move-Item -LiteralPath $target -Destination $backup }
        Write-Host "Old copy moved to $backup" -ForegroundColor Yellow
    }
}
if ($PSCmdlet.ShouldProcess($target, "Link to $source")) {
    New-Item -ItemType Junction -Path $target -Target $source | Out-Null
    Write-Host "Linked $target -> $source" -ForegroundColor Green
    Write-Host "In game: /reload, then /vmh"
}
