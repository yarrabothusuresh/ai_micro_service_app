[CmdletBinding()]
param([switch]$SkipBuild, [switch]$Verify, [switch]$NoBrowser)
& (Join-Path (Split-Path -Parent $PSScriptRoot) 'start.ps1') -SkipBuild:$SkipBuild -Verify:$Verify -NoBrowser:$NoBrowser
