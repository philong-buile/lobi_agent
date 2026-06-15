#Requires -Version 5.1
<#
.SYNOPSIS
  Set up the Lobi bot (OpenClaw + Claude Code CLI + Telegram) on Windows.

.DESCRIPTION
  Checks prerequisites, installs OpenClaw if needed, writes ~/.openclaw/openclaw.json from
  openclaw.example.json (filling in your bot token + Telegram user ID and a random gateway token),
  validates it, then installs and starts the gateway as a Scheduled Task.

.EXAMPLE
  ./setup.ps1
  ./setup.ps1 -BotToken "123456:ABC-your-bot-token" -TelegramUserId "123456789"
#>
[CmdletBinding()]
param(
  [string]$BotToken,
  [string]$TelegramUserId,
  [string]$Model = "anthropic/claude-sonnet-4-6"
)

$ErrorActionPreference = "Stop"
function Info($m) { Write-Host "[lobi] $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[lobi] $m" -ForegroundColor Yellow }

# 1) Prerequisites -----------------------------------------------------------
Info "Checking prerequisites..."
foreach ($cmd in "node", "npm", "claude") {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "'$cmd' not found on PATH. Install it first ('claude' = Claude Code, and it must be logged in)."
  }
}
Info "node $(node --version) | npm $(npm --version) | claude present"

# 2) Install OpenClaw --------------------------------------------------------
if (-not (Get-Command openclaw -ErrorAction SilentlyContinue)) {
  Info "Installing OpenClaw globally (npm i -g openclaw)..."
  npm install -g openclaw
} else {
  Info "OpenClaw already installed: $(openclaw --version)"
}

# 3) Collect secrets ---------------------------------------------------------
if (-not $BotToken)       { $BotToken = Read-Host "Telegram bot token (from @BotFather)" }
if (-not $TelegramUserId) { $TelegramUserId = Read-Host "Your numeric Telegram user ID" }

# 4) Build config from the template -----------------------------------------
$cfgDir  = Join-Path $env:USERPROFILE ".openclaw"
$cfgPath = Join-Path $cfgDir "openclaw.json"
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null

$tpl = Join-Path $PSScriptRoot "openclaw.example.json"
if (-not (Test-Path $tpl)) { throw "Template not found: $tpl" }
$cfg = Get-Content $tpl -Raw | ConvertFrom-Json

# random 48-char hex gateway token
$gwToken = -join ((1..48) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })

$cfg.gateway.auth.token           = $gwToken
$cfg.agents.defaults.workspace    = (Join-Path $cfgDir "workspace")
$cfg.agents.defaults.model.primary = $Model
$cfg.channels.telegram.botToken   = $BotToken
$cfg.commands.ownerAllowFrom      = @("telegram:$TelegramUserId")

if (Test-Path $cfgPath) {
  $bak = "$cfgPath.bak.$(Get-Random)"
  Copy-Item $cfgPath $bak
  Warn "Existing config backed up to $bak"
}
($cfg | ConvertTo-Json -Depth 20) | Set-Content -Path $cfgPath -Encoding utf8
Info "Wrote $cfgPath"
openclaw config validate

# 5) Install + start the gateway --------------------------------------------
Info "Installing + starting the gateway..."
openclaw gateway install
openclaw gateway start
Start-Sleep -Seconds 5
openclaw gateway status

Info "Done. Now DM your bot once, then approve the pairing:"
Write-Host "  openclaw pairing list telegram"
Write-Host "  openclaw pairing approve telegram <CODE>"
