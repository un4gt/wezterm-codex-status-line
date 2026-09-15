[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$Uninstall,
  [string]$CodexHome
)

$ErrorActionPreference = 'Stop'

function Get-CodexHome {
  if ($CodexHome) {
    return [System.IO.Path]::GetFullPath($CodexHome)
  }
  if ($env:CODEX_HOME) {
    return [System.IO.Path]::GetFullPath($env:CODEX_HOME)
  }
  $homePath = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
  return [System.IO.Path]::Combine($homePath, '.codex')
}

function Write-Utf8JsonAtomic {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)]$Value
  )

  $directory = [System.IO.Path]::GetDirectoryName($Path)
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  $json = $Value | ConvertTo-Json -Depth 40
  $temp = "$Path.$PID.$([guid]::NewGuid().ToString('N')).tmp"
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($temp, $json + [Environment]::NewLine, $utf8)
  try {
    if ([System.IO.File]::Exists($Path)) {
      try {
        [System.IO.File]::Replace($temp, $Path, $null, $true)
      } catch {
        Move-Item -LiteralPath $temp -Destination $Path -Force
      }
    } else {
      [System.IO.File]::Move($temp, $Path)
    }
  } finally {
    if ([System.IO.File]::Exists($temp)) {
      Remove-Item -LiteralPath $temp -Force
    }
  }
}

function Backup-HooksFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }
  $stamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff')
  $backupPath = "$Path.bak-$stamp"
  if (Test-Path -LiteralPath $backupPath) {
    $backupPath = "$backupPath-$([guid]::NewGuid().ToString('N'))"
  }
  Copy-Item -LiteralPath $Path -Destination $backupPath
}

function New-HookHandler {
  $psPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'codex_statusline_bridge.ps1'))
  $pyPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'codex_statusline_bridge.py'))
  return [pscustomobject][ordered]@{
    type = 'command'
    command = 'python3 "' + $pyPath.Replace('\\', '/') + '"'
    commandWindows = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $psPath + '"'
    timeout = 5
  }
}

function Test-IsOurHandler {
  param($Handler)
  if ($null -eq $Handler) {
    return $false
  }
  $command = [string]$Handler.command
  $windowsCommand = [string]$Handler.commandWindows
  return $command.Contains('codex_statusline_bridge.py') `
    -or $command.Contains('codex_statusline_bridge.js') `
    -or $windowsCommand.Contains('codex_statusline_bridge.ps1')
}

function Test-HookHandlerCurrent {
  param(
    $Handler,
    $Expected
  )

  if ($null -eq $Handler -or $null -eq $Expected) {
    return $false
  }
  return (
    [string]$Handler.type -eq [string]$Expected.type -and
    [string]$Handler.command -eq [string]$Expected.command -and
    [string]$Handler.commandWindows -eq [string]$Expected.commandWindows -and
    [int]$Handler.timeout -eq [int]$Expected.timeout
  )
}

function Get-HooksDocument {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return [pscustomobject][ordered]@{
      description = 'Hooks used by the WezTerm Codex statusline bridge.'
      hooks = [pscustomobject]@{}
    }
  }
  $raw = [System.IO.File]::ReadAllText($Path)
  $document = $raw | ConvertFrom-Json
  if ($null -eq $document) {
    throw "Invalid empty hooks document: $Path"
  }
  if (-not ($document.PSObject.Properties.Name -contains 'hooks')) {
    $document | Add-Member -MemberType NoteProperty -Name hooks -Value ([pscustomobject]@{})
  }
  return $document
}

function Install-Bridge {
  $homePath = Get-CodexHome
  [System.IO.Directory]::CreateDirectory($homePath) | Out-Null
  $hooksPath = Join-Path $homePath 'hooks.json'
  $document = Get-HooksDocument $hooksPath
  if (-not ($document.hooks.PSObject.Properties.Name -contains 'SessionStart')) {
    $document.hooks | Add-Member -MemberType NoteProperty -Name SessionStart -Value @()
  }

  $groups = @($document.hooks.SessionStart)
  $expectedHandler = New-HookHandler
  $found = $false
  $changed = $false
  foreach ($group in $groups) {
    if ($null -eq $group -or -not ($group.PSObject.Properties.Name -contains 'hooks')) {
      continue
    }
    $updatedHandlers = @()
    foreach ($handler in @($group.hooks)) {
      if (Test-IsOurHandler $handler) {
        if (-not $found) {
          $found = $true
          if (Test-HookHandlerCurrent -Handler $handler -Expected $expectedHandler) {
            $updatedHandlers += $handler
          } else {
            $updatedHandlers += $expectedHandler
            $changed = $true
          }
        } else {
          $changed = $true
        }
      } else {
        $updatedHandlers += $handler
      }
    }
    $group.hooks = $updatedHandlers
  }

  if (-not $found) {
    $groups += [pscustomobject][ordered]@{ hooks = @($expectedHandler) }
    $changed = $true
  }

  if ($changed) {
    $document.hooks.SessionStart = $groups
    Backup-HooksFile -Path $hooksPath
    Write-Utf8JsonAtomic -Path $hooksPath -Value $document
  }

  $bridgeRoot = Join-Path $homePath 'wezterm-statusline'
  $manifest = [pscustomobject][ordered]@{
    schema = 1
    installed_at_unix_ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    powershell_bridge = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'codex_statusline_bridge.ps1'))
    python_bridge = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'codex_statusline_bridge.py'))
    javascript_bridge = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'codex_statusline_bridge.js'))
  }
  Write-Utf8JsonAtomic -Path (Join-Path $bridgeRoot 'bridge.json') -Value $manifest
  Write-Host "Codex statusline bridge installed in $hooksPath"
}

function Uninstall-Bridge {
  $homePath = Get-CodexHome
  $hooksPath = Join-Path $homePath 'hooks.json'
  if (Test-Path -LiteralPath $hooksPath) {
    $document = Get-HooksDocument $hooksPath
    if ($document.hooks.PSObject.Properties.Name -contains 'SessionStart') {
      $keptGroups = @()
      $changed = $false
      foreach ($group in @($document.hooks.SessionStart)) {
        $keptHandlers = @($group.hooks | Where-Object { -not (Test-IsOurHandler $_) })
        if ($keptHandlers.Count -ne @($group.hooks).Count) {
          $changed = $true
        }
        if ($keptHandlers.Count -gt 0) {
          $group.hooks = $keptHandlers
          $keptGroups += $group
        }
      }
      if ($changed) {
        Backup-HooksFile -Path $hooksPath
        $document.hooks.SessionStart = $keptGroups
        Write-Utf8JsonAtomic -Path $hooksPath -Value $document
      }
    }
  }

  $manifestPath = Join-Path (Join-Path $homePath 'wezterm-statusline') 'bridge.json'
  if (Test-Path -LiteralPath $manifestPath) {
    $preserveManifest = $false
    try {
      $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
      $preserveManifest = [int]$manifest.schema -ge 3 -and (
        $manifest.PSObject.Properties.Name -contains 'codex_title_bridge'
      )
    } catch {}
    if ($preserveManifest) {
      Write-Warning 'Terminal title restore metadata was preserved. Run install.ps1 -Uninstall for a complete uninstall.'
    } else {
      Remove-Item -LiteralPath $manifestPath -Force
    }
  }
  Write-Host 'Codex statusline bridge uninstalled.'
}

function Invoke-SessionStartBridge {
  $paneId = [string]$env:WEZTERM_PANE
  if (-not $paneId -or $paneId -notmatch '^\d+$') {
    return
  }

  $raw = [Console]::In.ReadToEnd()
  if (-not $raw) {
    return
  }
  $payload = $raw | ConvertFrom-Json
  $sessionId = [string]$payload.session_id
  if ($sessionId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    throw 'SessionStart payload has an invalid session_id.'
  }

  $rolloutPath = if ($payload.transcript_path -is [string]) { $payload.transcript_path } else { $null }
  $threadId = $sessionId
  if ($rolloutPath -and (Test-Path -LiteralPath $rolloutPath)) {
    foreach ($line in @(Get-Content -LiteralPath $rolloutPath -TotalCount 20)) {
      try {
        $item = $line | ConvertFrom-Json
        if ($item.type -eq 'session_meta' -and $item.payload.id) {
          $candidate = [string]$item.payload.id
          if ($candidate -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            $threadId = $candidate
            break
          }
        }
      } catch {
        continue
      }
    }
  }
  $mapping = [pscustomobject][ordered]@{
    schema = 1
    pane_id = $paneId
    thread_id = $threadId.ToLowerInvariant()
    session_id = $sessionId.ToLowerInvariant()
    rollout_path = $rolloutPath
    cwd = [string]$payload.cwd
    source = [string]$payload.source
    generation = [guid]::NewGuid().ToString()
    written_at_unix_ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  }

  $bridgeRoot = Join-Path (Get-CodexHome) 'wezterm-statusline'
  $mappingPath = Join-Path (Join-Path $bridgeRoot 'panes') "$paneId.json"
  Write-Utf8JsonAtomic -Path $mappingPath -Value $mapping
}

if ($Install) {
  Install-Bridge
} elseif ($Uninstall) {
  Uninstall-Bridge
} else {
  Invoke-SessionStartBridge
}
