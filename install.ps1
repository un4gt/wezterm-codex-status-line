[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$Uninstall,
  [switch]$EnableCodexTitleBridge,
  [string]$UserHome,
  [string]$CodexHome,
  [string]$WezTermModuleDir,
  [string]$SourceBaseUrl = 'https://raw.githubusercontent.com/un4gt/wezterm-codex-status-line/main',
  [string]$PackageName = 'wezterm-codex-status-line',
  [string]$PackageVersion = '0.1.2',
  [string]$InstallerRunner = 'powershell'
)

$ErrorActionPreference = 'Stop'

$LuaAssets = @(
  'codex_statusline.lua',
  'codex_statusline_core.lua',
  'codex_statusline/version.lua',
  'codex_statusline/domain/common.lua',
  'codex_statusline/domain/process.lua',
  'codex_statusline/domain/session.lua',
  'codex_statusline/domain/prices.lua',
  'codex_statusline/domain/pricing.lua',
  'codex_statusline/domain/render.lua',
  'codex_statusline/util.lua',
  'codex_statusline/config.lua',
  'codex_statusline/session_index.lua',
  'codex_statusline/rollout.lua',
  'codex_statusline/git.lua',
  'codex_statusline/process.lua',
  'codex_statusline/formatting.lua',
  'codex_statusline/legacy_renderer.lua',
  'codex_statusline/renderer.lua',
  'codex_statusline/layout.lua',
  'codex_statusline/state.lua',
  'codex_statusline/wezterm_adapter.lua',
  'codex_statusline/lifecycle.lua'
)
$LuaInstallAssets = @($LuaAssets | Where-Object { $_ -ne 'codex_statusline.lua' }) + @('codex_statusline.lua')
$BridgeAssets = @(
  'codex_statusline_bridge.ps1',
  'codex_statusline_bridge.py',
  'codex_statusline_bridge.js'
)
$CodexTitleKeyPath = 'tui.terminal_title'
$CodexTitleInstalledValue = @('app-name', 'model', 'reasoning', 'project-name')

function Get-UserHome {
  if ($UserHome) {
    return [System.IO.Path]::GetFullPath($UserHome)
  }
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

function Test-ObjectProperty {
  param(
    $Value,
    [Parameter(Mandatory = $true)][string]$Name
  )
  return $null -ne $Value -and $null -ne $Value.PSObject.Properties[$Name]
}

function ConvertTo-ComparableJson {
  param($Value)
  if ($null -eq $Value) {
    return 'null'
  }
  return ($Value | ConvertTo-Json -Compress -Depth 40)
}

function Get-Sha256Hex {
  param([Parameter(Mandatory = $true)][string]$Path)
  $stream = [System.IO.File]::OpenRead($Path)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = $sha.ComputeHash($stream)
    return ([System.BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
    $stream.Dispose()
  }
}

function Test-JsonValueEqual {
  param($Left, $Right)
  return (ConvertTo-ComparableJson $Left) -ceq (ConvertTo-ComparableJson $Right)
}

function Get-InstallManifest {
  param([Parameter(Mandatory = $true)][string]$HomePath)
  $path = Join-Path (Join-Path $HomePath 'wezterm-statusline') 'bridge.json'
  if (-not (Test-Path -LiteralPath $path)) {
    return $null
  }
  return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function New-StagedAsset {
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
    return [pscustomobject][ordered]@{
      name = $Name
      destination = $destinationPath
      temp_path = $null
    }
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
  } catch {
    if (Test-Path -LiteralPath $temp) {
      Remove-Item -LiteralPath $temp -Force
    }
    throw
  }

  return [pscustomobject][ordered]@{
    name = $Name
    destination = $destinationPath
    temp_path = $temp
  }
}

function Install-AssetBatch {
  param(
    [Parameter(Mandatory = $true)][object[]]$Assets
  )

  $staged = @()
  try {
    foreach ($asset in $Assets) {
      $staged += New-StagedAsset -Name $asset.name -Destination $asset.destination
    }
    foreach ($asset in $staged) {
      if (-not $asset.temp_path) {
        continue
      }
      Move-Item -LiteralPath $asset.temp_path -Destination $asset.destination -Force
      $asset.temp_path = $null
    }
  } finally {
    foreach ($asset in $staged) {
      if ($asset.temp_path -and (Test-Path -LiteralPath $asset.temp_path)) {
        Remove-Item -LiteralPath $asset.temp_path -Force
      }
    }
  }
}

function Get-CodexCommandPath {
  if ($env:CODEX_STATUSLINE_CODEX_COMMAND) {
    return [System.IO.Path]::GetFullPath($env:CODEX_STATUSLINE_CODEX_COMMAND)
  }
  $command = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $command) {
    $command = Get-Command codex -CommandType ExternalScript -ErrorAction Stop | Select-Object -First 1
  }
  if (-not $command -or -not $command.Source) {
    throw 'Codex CLI was not found in PATH.'
  }
  return [System.IO.Path]::GetFullPath($command.Source)
}

function Send-CodexRpcMessage {
  param(
    [Parameter(Mandatory = $true)]$Client,
    [Parameter(Mandatory = $true)]$Message
  )
  $payload = $Message | ConvertTo-Json -Compress -Depth 40
  $Client.Input.WriteLine($payload)
  $Client.Input.Flush()
}

function Read-CodexRpcResponse {
  param(
    [Parameter(Mandatory = $true)]$Client,
    [Parameter(Mandatory = $true)][int]$Id,
    [int]$TimeoutMilliseconds = 10000
  )

  $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    $remaining = [int][Math]::Max(1, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)
    $task = $Client.Output.ReadLineAsync()
    if (-not $task.Wait($remaining)) {
      throw "Timed out waiting for Codex app-server response id $Id."
    }
    $line = $task.Result
    if ($null -eq $line) {
      throw "Codex app-server exited before responding to request id $Id."
    }
    if (-not $line.Trim()) {
      continue
    }

    try {
      $message = $line | ConvertFrom-Json
    } catch {
      continue
    }
    if (-not (Test-ObjectProperty -Value $message -Name 'id') -or [int]$message.id -ne $Id) {
      continue
    }
    if (Test-ObjectProperty -Value $message -Name 'error') {
      $details = $message.error | ConvertTo-Json -Compress -Depth 20
      throw "Codex app-server request failed: $details"
    }
    return $message.result
  }
  throw "Timed out waiting for Codex app-server response id $Id."
}

function Invoke-CodexRpcRequest {
  param(
    [Parameter(Mandatory = $true)]$Client,
    [Parameter(Mandatory = $true)][string]$Method,
    $Params
  )
  $id = [int]$Client.NextId
  $Client.NextId = $id + 1
  $message = [pscustomobject][ordered]@{
    id = $id
    method = $Method
    params = $Params
  }
  Send-CodexRpcMessage -Client $Client -Message $message
  return Read-CodexRpcResponse -Client $Client -Id $id
}

function Start-CodexRpcClient {
  param([Parameter(Mandatory = $true)][string]$HomePath)

  [System.IO.Directory]::CreateDirectory($HomePath) | Out-Null
  $commandPath = Get-CodexCommandPath
  $extension = [System.IO.Path]::GetExtension($commandPath).ToLowerInvariant()
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardInput = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.WorkingDirectory = $HomePath
  $startInfo.EnvironmentVariables['CODEX_HOME'] = $HomePath

  if ($extension -eq '.cmd' -or $extension -eq '.bat') {
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = '/d /s /c ""' + $commandPath + '" app-server --stdio"'
  } elseif ($extension -eq '.ps1') {
    $startInfo.FileName = (Get-Process -Id $PID).Path
    $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $commandPath + '" app-server --stdio'
  } else {
    $startInfo.FileName = $commandPath
    $startInfo.Arguments = 'app-server --stdio'
  }

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  $previousInputEncoding = [Console]::InputEncoding
  $previousOutputEncoding = [Console]::OutputEncoding
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  try {
    # .NET Framework otherwise writes a UTF-8 BOM to redirected stdin, which
    # makes the first JSON-RPC line invalid for Codex app-server.
    [Console]::InputEncoding = $utf8
    [Console]::OutputEncoding = $utf8
    if (-not $process.Start()) {
      throw 'Failed to start Codex app-server.'
    }
    $inputWriter = $process.StandardInput
    $outputReader = $process.StandardOutput
    $errorReader = $process.StandardError
  } finally {
    [Console]::InputEncoding = $previousInputEncoding
    [Console]::OutputEncoding = $previousOutputEncoding
  }
  $stderrTask = $errorReader.ReadToEndAsync()
  $client = [pscustomobject]@{
    Process = $process
    Input = $inputWriter
    Output = $outputReader
    StderrTask = $stderrTask
    NextId = 1
  }

  try {
    $initialize = [pscustomobject][ordered]@{
      clientInfo = [pscustomobject][ordered]@{
        name = 'wezterm-codex-status-line-installer'
        version = '1.0.0'
      }
      capabilities = [pscustomobject][ordered]@{
        experimentalApi = $true
      }
    }
    $null = Invoke-CodexRpcRequest -Client $client -Method 'initialize' -Params $initialize
    Send-CodexRpcMessage -Client $client -Message ([pscustomobject][ordered]@{ method = 'initialized' })
    return $client
  } catch {
    Stop-CodexRpcClient -Client $client
    throw
  }
}

function Stop-CodexRpcClient {
  param($Client)
  if (-not $Client -or -not $Client.Process) {
    return
  }
  try {
    $Client.Input.Close()
  } catch {}
  try {
    if (-not $Client.Process.WaitForExit(1000)) {
      $Client.Process.Kill()
      $Client.Process.WaitForExit()
    }
  } catch {}
  $Client.Process.Dispose()
}

function Get-CodexTitleState {
  param(
    [Parameter(Mandatory = $true)]$Client,
    [Parameter(Mandatory = $true)][string]$HomePath
  )

  $read = Invoke-CodexRpcRequest -Client $Client -Method 'config/read' -Params ([pscustomobject][ordered]@{
    includeLayers = $true
  })
  if (-not (Test-ObjectProperty -Value $read -Name 'layers')) {
    throw 'Codex config/read did not return configuration layers; terminal title bridge is unsupported.'
  }

  $userLayer = @($read.layers | Where-Object {
    $_.name -and $_.name.type -eq 'user' -and (
      -not (Test-ObjectProperty -Value $_.name -Name 'profile') -or $null -eq $_.name.profile
    )
  } | Select-Object -First 1)
  if ($userLayer.Count -gt 0) {
    $userLayer = $userLayer[0]
  } else {
    $userLayer = $null
  }

  $present = $false
  $value = $null
  $hasUserTui = $userLayer -and $userLayer.config -and (Test-ObjectProperty -Value $userLayer.config -Name 'tui')
  if ($hasUserTui -and $userLayer.config.tui -and (Test-ObjectProperty -Value $userLayer.config.tui -Name 'terminal_title')) {
    $present = $true
    $value = $userLayer.config.tui.terminal_title
  }

  $effectiveValue = $null
  $hasEffectiveTui = $read.config -and (Test-ObjectProperty -Value $read.config -Name 'tui')
  if ($hasEffectiveTui -and $read.config.tui -and (Test-ObjectProperty -Value $read.config.tui -Name 'terminal_title')) {
    $effectiveValue = $read.config.tui.terminal_title
  }

  $configFile = Join-Path $HomePath 'config.toml'
  $version = $null
  if ($userLayer) {
    if ($userLayer.name.file) {
      $configFile = [string]$userLayer.name.file
    }
    $version = [string]$userLayer.version
  }

  return [pscustomobject][ordered]@{
    Present = $present
    Value = $value
    EffectiveValue = $effectiveValue
    Version = $version
    ConfigFile = $configFile
  }
}

function Write-CodexTitleValue {
  param(
    [Parameter(Mandatory = $true)]$Client,
    [Parameter(Mandatory = $true)]$State,
    $Value
  )

  $edit = [pscustomobject][ordered]@{
    keyPath = $CodexTitleKeyPath
    value = $Value
    mergeStrategy = 'replace'
  }
  $params = [pscustomobject][ordered]@{
    edits = @($edit)
    filePath = $State.ConfigFile
    expectedVersion = $State.Version
    reloadUserConfig = $false
  }
  return Invoke-CodexRpcRequest -Client $Client -Method 'config/batchWrite' -Params $params
}

function New-CodexTitleBridgeRecord {
  param(
    [Parameter(Mandatory = $true)][bool]$OriginalPresent,
    $OriginalValue,
    [string]$ConfigFile,
    [string]$VersionBefore,
    [string]$VersionAfter
  )
  return [pscustomobject][ordered]@{
    enabled = $true
    key_path = $CodexTitleKeyPath
    config_file = $ConfigFile
    original_present = $OriginalPresent
    original_value = $OriginalValue
    installed_value = @($CodexTitleInstalledValue)
    version_before = $VersionBefore
    version_after = $VersionAfter
  }
}

function Test-IsConfigVersionConflict {
  param([Parameter(Mandatory = $true)]$ErrorRecord)
  return [string]$ErrorRecord.Exception.Message -match 'ConfigVersionConflict|modified since last read'
}

function Enable-CodexTitleBridgeConfig {
  param(
    [Parameter(Mandatory = $true)][string]$HomePath,
    $ExistingRecord
  )

  $originalCaptured = $false
  $originalPresent = $false
  $originalValue = $null
  $versionBefore = $null
  for ($attempt = 0; $attempt -lt 2; $attempt++) {
    $client = $null
    try {
      $client = Start-CodexRpcClient -HomePath $HomePath
      $state = Get-CodexTitleState -Client $client -HomePath $HomePath

      if ($ExistingRecord -and $ExistingRecord.enabled) {
        $expectedInstalled = $ExistingRecord.installed_value
        if (-not $state.Present -or -not (Test-JsonValueEqual $state.Value $expectedInstalled)) {
          throw 'tui.terminal_title changed after installation; refusing to overwrite the user value.'
        }
        if (-not (Test-JsonValueEqual $state.EffectiveValue $expectedInstalled)) {
          throw 'tui.terminal_title is overridden by another Codex configuration layer.'
        }
        $originalCaptured = $true
        $originalPresent = [bool]$ExistingRecord.original_present
        $originalValue = $ExistingRecord.original_value
        $versionBefore = [string]$ExistingRecord.version_before
      } elseif (-not $originalCaptured) {
        $originalCaptured = $true
        $originalPresent = [bool]$state.Present
        $originalValue = $state.Value
        $versionBefore = $state.Version
      } elseif ($state.Present -ne $originalPresent -or ($state.Present -and -not (Test-JsonValueEqual $state.Value $originalValue))) {
        throw 'tui.terminal_title changed during installation; refusing to overwrite it.'
      }

      if (-not $state.Present -or -not (Test-JsonValueEqual $state.Value $CodexTitleInstalledValue)) {
        $null = Write-CodexTitleValue -Client $client -State $state -Value $CodexTitleInstalledValue
      }
      $verified = Get-CodexTitleState -Client $client -HomePath $HomePath
      if (-not $verified.Present -or -not (Test-JsonValueEqual $verified.Value $CodexTitleInstalledValue)) {
        throw 'Codex did not persist tui.terminal_title as requested.'
      }
      if (-not (Test-JsonValueEqual $verified.EffectiveValue $CodexTitleInstalledValue)) {
        $restoreValue = $null
        if ($state.Present) {
          $restoreValue = $state.Value
        }
        $null = Write-CodexTitleValue -Client $client -State $verified -Value $restoreValue
        throw 'tui.terminal_title is overridden by another Codex configuration layer.'
      }

      $record = New-CodexTitleBridgeRecord `
        -OriginalPresent $originalPresent `
        -OriginalValue $originalValue `
        -ConfigFile $verified.ConfigFile `
        -VersionBefore $versionBefore `
        -VersionAfter $verified.Version
      return $record
    } catch {
      if ($attempt -eq 0 -and (Test-IsConfigVersionConflict $_)) {
        continue
      }
      throw
    } finally {
      Stop-CodexRpcClient -Client $client
    }
  }
  throw 'Unable to configure the Codex terminal title bridge.'
}

function Restore-CodexTitleBridgeConfig {
  param(
    [Parameter(Mandatory = $true)][string]$HomePath,
    [Parameter(Mandatory = $true)]$Record
  )

  $installedValue = $Record.installed_value
  for ($attempt = 0; $attempt -lt 2; $attempt++) {
    $client = $null
    try {
      $client = Start-CodexRpcClient -HomePath $HomePath
      $state = Get-CodexTitleState -Client $client -HomePath $HomePath
      if (-not $state.Present -or -not (Test-JsonValueEqual $state.Value $installedValue)) {
        Write-Warning 'tui.terminal_title was changed after installation; keeping the current user value.'
        return
      }

      $restoreValue = $null
      if ([bool]$Record.original_present) {
        $restoreValue = $Record.original_value
      }
      $null = Write-CodexTitleValue -Client $client -State $state -Value $restoreValue
      $verified = Get-CodexTitleState -Client $client -HomePath $HomePath
      if ([bool]$Record.original_present) {
        if (-not $verified.Present -or -not (Test-JsonValueEqual $verified.Value $Record.original_value)) {
          throw 'Failed to restore the original tui.terminal_title value.'
        }
      } elseif ($verified.Present) {
        throw 'Failed to remove the terminal title value added by the installer.'
      }
      return
    } catch {
      if ($attempt -eq 0 -and (Test-IsConfigVersionConflict $_)) {
        continue
      }
      throw
    } finally {
      Stop-CodexRpcClient -Client $client
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
    [Parameter(Mandatory = $true)][string]$BridgeBin,
    $TitleBridgeRecord
  )

  $manifestPath = Join-Path (Join-Path $HomePath 'wezterm-statusline') 'bridge.json'
  $manifest = if (Test-Path -LiteralPath $manifestPath) {
    Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
  } else {
    [pscustomobject]@{}
  }
  $manifest | Add-Member -MemberType NoteProperty -Name schema -Value 4 -Force
  $manifest | Add-Member -MemberType NoteProperty -Name package -Value ([pscustomobject][ordered]@{
    name = $PackageName
    version = $PackageVersion
    runner = $InstallerRunner
    installed_at_unix_ms = [long](([DateTime]::UtcNow - [DateTime]'1970-01-01').TotalMilliseconds)
  }) -Force
  $manifest | Add-Member -MemberType NoteProperty -Name wezterm_module_dir -Value $ModuleDir -Force
  $manifest | Add-Member -MemberType NoteProperty -Name config_path -Value (Join-Path $ModuleDir 'codex_statusline_config.json') -Force
  $manifest | Add-Member -MemberType NoteProperty -Name lua_modules -Value @(
    $LuaAssets | ForEach-Object { Join-Path $ModuleDir $_ }
  ) -Force
  $manifest | Add-Member -MemberType NoteProperty -Name bridge_bin -Value $BridgeBin -Force
  $manifest | Add-Member -MemberType NoteProperty -Name bridge_runtime -Value 'powershell.exe' -Force
  $manifest | Add-Member -MemberType NoteProperty -Name source_base_url -Value $SourceBaseUrl -Force
  $assetHashes = [ordered]@{}
  foreach ($assetPath in @(
    $LuaAssets | ForEach-Object { Join-Path $ModuleDir $_ }
    $BridgeAssets | ForEach-Object { Join-Path $BridgeBin $_ }
  )) {
    if (Test-Path -LiteralPath $assetPath) {
      $assetHashes[$assetPath] = Get-Sha256Hex -Path $assetPath
    }
  }
  $manifest | Add-Member -MemberType NoteProperty -Name assets -Value ([pscustomobject]$assetHashes) -Force
  if ($TitleBridgeRecord) {
    $manifest | Add-Member -MemberType NoteProperty -Name codex_title_bridge -Value $TitleBridgeRecord -Force
  } elseif (Test-ObjectProperty -Value $manifest -Name 'codex_title_bridge') {
    $manifest.PSObject.Properties.Remove('codex_title_bridge')
  }
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

function Get-WezTermConfigLoadingStatusline {
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
      return $configPath
    }
  }
  return $null
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
  $existingManifest = Get-InstallManifest -HomePath $homePath
  $titleBridgeRecord = $null
  if ($existingManifest -and (Test-ObjectProperty -Value $existingManifest -Name 'codex_title_bridge')) {
    $titleBridgeRecord = $existingManifest.codex_title_bridge
  }

  if ($EnableCodexTitleBridge) {
    $titleBridgeRecord = Enable-CodexTitleBridgeConfig -HomePath $homePath -ExistingRecord $titleBridgeRecord
  }

  $shouldWriteManifest = $false
  try {
    $installPlan = @()
    foreach ($asset in $BridgeAssets) {
      $installPlan += [pscustomobject][ordered]@{
        name = $asset
        destination = Join-Path $bridgeBin $asset
      }
    }
    foreach ($asset in $LuaInstallAssets) {
      $installPlan += [pscustomobject][ordered]@{
        name = $asset
        destination = Join-Path $moduleDir $asset
      }
    }
    Install-AssetBatch -Assets $installPlan

    $installedBridge = Join-Path $bridgeBin 'codex_statusline_bridge.ps1'
    Invoke-BridgeInstaller -BridgePath $installedBridge -HomePath $homePath -Action Install
    $shouldWriteManifest = $true
  } finally {
    if ($shouldWriteManifest -or $titleBridgeRecord) {
      Update-InstallManifest `
        -HomePath $homePath `
        -ModuleDir $moduleDir `
        -BridgeBin $bridgeBin `
        -TitleBridgeRecord $titleBridgeRecord
    }
  }
  Test-WezTermConfig -ModuleDir $moduleDir
  if ($EnableCodexTitleBridge) {
    Write-Host 'Codex terminal title bridge configured; it will apply to new Codex sessions.'
  }
  Write-Host "WezTerm Codex statusline installed in $moduleDir"
}

function Uninstall-Statusline {
  $homePath = Get-CodexHome
  $moduleDir = Get-WezTermModuleDir
  $bridgeRoot = Join-Path $homePath 'wezterm-statusline'
  $bridgeBin = Join-Path $bridgeRoot 'bin'
  $installedBridge = Join-Path $bridgeBin 'codex_statusline_bridge.ps1'
  $localBridge = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'codex_statusline_bridge.ps1' } else { $null }
  $manifest = Get-InstallManifest -HomePath $homePath

  if ($manifest -and (Test-ObjectProperty -Value $manifest -Name 'codex_title_bridge')) {
    $titleRecord = $manifest.codex_title_bridge
    if ($titleRecord -and $titleRecord.enabled) {
      Restore-CodexTitleBridgeConfig -HomePath $homePath -Record $titleRecord
    }
  }
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
  Remove-FileIfPresent -Path (Join-Path $bridgeRoot 'bridge.json')
  Remove-DirectoryIfEmpty -Path $bridgeBin
  Remove-DirectoryIfEmpty -Path $bridgeRoot
  Write-Host 'WezTerm Codex statusline uninstalled.'
}

if ($Install -and $Uninstall) {
  throw 'Choose either -Install or -Uninstall.'
}
if ($Uninstall -and $EnableCodexTitleBridge) {
  throw '-EnableCodexTitleBridge can only be used with installation.'
}
if ($Uninstall) {
  $activeConfig = Get-WezTermConfigLoadingStatusline -ModuleDir (Get-WezTermModuleDir)
  if ($activeConfig) {
    [Console]::Error.WriteLine("Remove require(`"codex_statusline`") from $activeConfig, then run uninstall again.")
    exit 3
  }
  Uninstall-Statusline
} else {
  Install-Statusline
}
