[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$Uninstall,
  [string]$CodexHome,
  [string]$WezTermModuleDir,
  [string]$SourceBaseUrl = 'https://raw.githubusercontent.com/un4gt/wezterm-codex-status-line/main'
)

$ErrorActionPreference = 'Stop'

$LuaAssets = @(
  'codex_statusline.lua',
  'codex_statusline_core.lua'
)
$BridgeAssets = @(
  'codex_statusline_bridge.ps1',
  'codex_statusline_bridge.py'
)

function Get-UserHome {
  if ($env:USERPROFILE) {
    return [System.IO.Path]::GetFullPath($env:USERPROFILE)
  }
  return [System.IO.Path]::GetFullPath($HOME)
}

function Get-CodexHome {
  if ($CodexHome) {
    return [System.IO.Path]::GetFullPath($CodexHome)
  }
  if ($env:CODEX_HOME) {
    return [System.IO.Path]::GetFullPath($env:CODEX_HOME)
  }
  return [System.IO.Path]::Combine((Get-UserHome), '.codex')
}

function Get-WezTermModuleDir {
  if ($WezTermModuleDir) {
    return [System.IO.Path]::GetFullPath($WezTermModuleDir)
  }
  return [System.IO.Path]::Combine((Get-UserHome), '.config', 'wezterm')
}

function Write-Utf8JsonAtomic {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)]$Value
  )

  $directory = [System.IO.Path]::GetDirectoryName($Path)
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  $temp = "$Path.$PID.$([guid]::NewGuid().ToString('N')).tmp"
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  $json = $Value | ConvertTo-Json -Depth 40
  [System.IO.File]::WriteAllText($temp, $json + [Environment]::NewLine, $utf8)
  try {
    Move-Item -LiteralPath $temp -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temp) {
      Remove-Item -LiteralPath $temp -Force
    }
  }
}

function Install-Asset {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  $destinationPath = [System.IO.Path]::GetFullPath($Destination)
  $destinationDir = [System.IO.Path]::GetDirectoryName($destinationPath)
  [System.IO.Directory]::CreateDirectory($destinationDir) | Out-Null

  $localSource = $null
  if ($PSScriptRoot) {
    $candidate = Join-Path $PSScriptRoot $Name
    if (Test-Path -LiteralPath $candidate) {
      $localSource = [System.IO.Path]::GetFullPath($candidate)
    }
  }

  if ($localSource -and $localSource -eq $destinationPath) {
    return
  }

  $temp = "$destinationPath.$PID.$([guid]::NewGuid().ToString('N')).tmp"
  try {
    if ($localSource) {
      Copy-Item -LiteralPath $localSource -Destination $temp
    } else {
      $baseUrl = $SourceBaseUrl.TrimEnd('/')
      if (-not $baseUrl) {
        throw "Cannot locate $Name locally and SourceBaseUrl is empty."
      }
      Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/$Name" -OutFile $temp
    }
    Move-Item -LiteralPath $temp -Destination $destinationPath -Force
  } finally {
    if (Test-Path -LiteralPath $temp) {
      Remove-Item -LiteralPath $temp -Force
    }
  }
}

function Invoke-BridgeInstaller {
  param(
    [Parameter(Mandatory = $true)][string]$BridgePath,
    [Parameter(Mandatory = $true)][string]$HomePath,
    [Parameter(Mandatory = $true)][ValidateSet('Install', 'Uninstall')][string]$Action
  )

  $actionArg = "-$Action"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BridgePath $actionArg -CodexHome $HomePath
  if ($LASTEXITCODE -ne 0) {
    throw "Bridge $Action failed with exit code $LASTEXITCODE."
  }
}

function Update-InstallManifest {
  param(
    [Parameter(Mandatory = $true)][string]$HomePath,
    [Parameter(Mandatory = $true)][string]$ModuleDir,
    [Parameter(Mandatory = $true)][string]$BridgeBin
  )

  $manifestPath = Join-Path (Join-Path $HomePath 'wezterm-statusline') 'bridge.json'
  $manifest = if (Test-Path -LiteralPath $manifestPath) {
    Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
  } else {
    [pscustomobject]@{}
  }
  $manifest | Add-Member -MemberType NoteProperty -Name schema -Value 2 -Force
  $manifest | Add-Member -MemberType NoteProperty -Name wezterm_module_dir -Value $ModuleDir -Force
  $manifest | Add-Member -MemberType NoteProperty -Name lua_modules -Value @(
    (Join-Path $ModuleDir 'codex_statusline.lua'),
    (Join-Path $ModuleDir 'codex_statusline_core.lua')
  ) -Force
  $manifest | Add-Member -MemberType NoteProperty -Name bridge_bin -Value $BridgeBin -Force
  $manifest | Add-Member -MemberType NoteProperty -Name source_base_url -Value $SourceBaseUrl -Force
  Write-Utf8JsonAtomic -Path $manifestPath -Value $manifest
}

function Test-WezTermConfig {
  param([Parameter(Mandatory = $true)][string]$ModuleDir)

  $candidates = @(
    (Join-Path (Get-UserHome) '.wezterm.lua'),
    (Join-Path $ModuleDir 'wezterm.lua')
  )
  foreach ($configPath in $candidates) {
    if (-not (Test-Path -LiteralPath $configPath)) {
      continue
    }
    $raw = [System.IO.File]::ReadAllText($configPath)
    if ($raw -match 'require\s*\(\s*["'']codex_statusline["'']\s*\)') {
      Write-Host "WezTerm config already loads codex_statusline: $configPath"
      return
    }
    Write-Warning "Add require(`"codex_statusline`").setup() before the final return in $configPath"
    return
  }
  Write-Warning 'No WezTerm config was found. Create ~/.wezterm.lua and call require("codex_statusline").setup().'
}

function Remove-FileIfPresent {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Force
  }
}

function Remove-DirectoryIfEmpty {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ((Test-Path -LiteralPath $Path) -and @(Get-ChildItem -Force -LiteralPath $Path).Count -eq 0) {
    Remove-Item -LiteralPath $Path -Force
  }
}

function Install-Statusline {
  $homePath = Get-CodexHome
  $moduleDir = Get-WezTermModuleDir
  $bridgeRoot = Join-Path $homePath 'wezterm-statusline'
  $bridgeBin = Join-Path $bridgeRoot 'bin'

  foreach ($asset in $LuaAssets) {
    Install-Asset -Name $asset -Destination (Join-Path $moduleDir $asset)
  }
  foreach ($asset in $BridgeAssets) {
    Install-Asset -Name $asset -Destination (Join-Path $bridgeBin $asset)
  }

  $installedBridge = Join-Path $bridgeBin 'codex_statusline_bridge.ps1'
  Invoke-BridgeInstaller -BridgePath $installedBridge -HomePath $homePath -Action Install
  Update-InstallManifest -HomePath $homePath -ModuleDir $moduleDir -BridgeBin $bridgeBin
  Test-WezTermConfig -ModuleDir $moduleDir
  Write-Host "WezTerm Codex statusline installed in $moduleDir"
}

function Uninstall-Statusline {
  $homePath = Get-CodexHome
  $moduleDir = Get-WezTermModuleDir
  $bridgeRoot = Join-Path $homePath 'wezterm-statusline'
  $bridgeBin = Join-Path $bridgeRoot 'bin'
  $installedBridge = Join-Path $bridgeBin 'codex_statusline_bridge.ps1'
  $localBridge = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'codex_statusline_bridge.ps1' } else { $null }

  if (Test-Path -LiteralPath $installedBridge) {
    Invoke-BridgeInstaller -BridgePath $installedBridge -HomePath $homePath -Action Uninstall
  } elseif ($localBridge -and (Test-Path -LiteralPath $localBridge)) {
    Invoke-BridgeInstaller -BridgePath $localBridge -HomePath $homePath -Action Uninstall
  } else {
    Write-Warning 'Bridge script is unavailable; the Codex hook could not be removed automatically.'
  }

  foreach ($asset in $LuaAssets) {
    Remove-FileIfPresent -Path (Join-Path $moduleDir $asset)
  }
  foreach ($asset in $BridgeAssets) {
    Remove-FileIfPresent -Path (Join-Path $bridgeBin $asset)
  }
  Remove-DirectoryIfEmpty -Path $bridgeBin
  Remove-DirectoryIfEmpty -Path $bridgeRoot
  Write-Host 'WezTerm Codex statusline uninstalled.'
}

if ($Install -and $Uninstall) {
  throw 'Choose either -Install or -Uninstall.'
}
if ($Uninstall) {
  Uninstall-Statusline
} else {
  Install-Statusline
}
