#!/usr/bin/env pwsh

# Optional overrides for the model and the Ollama server, applied to the settings file
# in the guest below. Both are left alone when not passed, which is how the IDE calls this.
$model = ''
$ollamaHost = ''

$i = 0
while ($i -lt $args.Count) {
    $arg = [string] $args[$i]
    if ($arg -eq '--model' -or $arg -eq '--ollama-host') {
        if ($i + 1 -ge $args.Count) {
            [Console]::Error.WriteLine("qwen.ps1: $arg needs a value")
            exit 1
        }
        if ($arg -eq '--model') { $model = [string] $args[$i + 1] } else { $ollamaHost = [string] $args[$i + 1] }
        $i += 2
    }
    else {
        [Console]::Error.WriteLine("qwen.ps1: unknown argument: $arg (expected --model NAME or --ollama-host HOST)")
        exit 1
    }
}

# The working directory is set to the project currently open in the IDE.
Write-Host "Host project directory: $PWD"

# ── Where the agent starts ───────────────────────────────────────────────────
# Captured before the Set-Location below, which is not optional: `vagrant ssh` only
# finds the box from the directory holding the Vagrantfile, so this script cannot stay
# where it was called from.
#
# Only ~/Code is synced into the guest, and it lands at a different prefix
# (/home/claude/Code), so the one description of "here" that means the same thing
# on both sides is the path relative to that root. That is what gets sent; the
# guest resolves it against its own prefix.
#
# Anywhere on the host outside ~/Code has no guest equivalent at all. Rather than
# invent one, the agent starts at the root of the synced tree and the mismatch is
# reported instead of being silently absorbed — a session that quietly began
# somewhere other than where you were standing is the confusing outcome.
$startDir = (Get-Location).ProviderPath
$codeRoot = Join-Path $HOME 'Code'

# Normalise both sides before comparing: the IDE may hand over a path with a
# different case or trailing separator than the one Join-Path builds, and on
# Windows the separator itself differs from the one the guest expects.
function Get-NormalizedPath([string] $Path) {
    $resolved = try { (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath } catch { $Path }
    return $resolved.Replace('\', '/').TrimEnd('/')
}

$startNorm = Get-NormalizedPath $startDir
$rootNorm = Get-NormalizedPath $codeRoot

# Windows paths are case-insensitive; everywhere else pwsh runs they are not.
# $IsWindows only exists in PowerShell 6+, and the shell that lacks it (5.1) is
# Windows-only, so an unset value means Windows too.
$onWindows = $IsWindows -or ($null -eq $IsWindows)
$comparison = if ($onWindows) { 'OrdinalIgnoreCase' } else { 'Ordinal' }

if ($startNorm.Equals($rootNorm, $comparison)) {
    $startRel = '.'
}
elseif ($startNorm.StartsWith("$rootNorm/", $comparison)) {
    $startRel = $startNorm.Substring($rootNorm.Length + 1)
}
else {
    [Console]::Error.WriteLine("qwen.ps1: $startDir is outside $codeRoot, which is the only directory " +
                               'synced into the guest — starting the agent in ~/Code')
    $startRel = '.'
}

# The relative path is spliced into a command string that a shell in the guest
# re-parses, so it has to survive that second round of word splitting intact.
# Single quotes stop the guest shell from touching the contents; an embedded single
# quote is closed, escaped literally, and reopened.
$startRelQ = "'" + $startRel.Replace("'", "'\''") + "'"

# This assumes that ~/Code/AIVagrantSandbox is the directory containing the Vagrantfile.
# Update this path if your Vagrantfile is located elsewhere.
try {
    Set-Location -LiteralPath (Join-Path $codeRoot 'AIVagrantSandbox') -ErrorAction Stop
}
catch {
    [Console]::Error.WriteLine("qwen.ps1: $($_.Exception.Message)")
    exit 1
}

Write-Host "Project Directory: $startRelQ"

# Edited in place in the guest, where jq is installed by the provisioner. The settings
# file is the agent's own, so the edit persists for later runs; modelProviders.openai[0]
# is the single local-Ollama entry the example settings.json in the Vagrantfile defines.
#
# Three accounts are involved and none of them can do the whole job: jq reads a file only
# the claude account can open, the redirect writes as the vagrant account that ssh landed
# on, and only root can then carry the result across, because /home/vagrant is mode 700
# and claude cannot read back what was staged there. The install flags match the ones the
# Vagrantfile uses for the same file, so the result is owned the same either way.
if ($model -ne '' -or $ollamaHost -ne '') {
    $baseUrl =
        if ($ollamaHost -eq '' -or $ollamaHost -match '://') { $ollamaHost }
        else { "http://${ollamaHost}:11434/v1" }

    $settings = '/home/claude/.qwen/settings.json'
    # Single-quoted so that PowerShell leaves jq's own $m and $u alone.
    $filter = '(if $m == "" then . else .model.name = $m | .modelProviders.openai[0].id = $m end) | (if $u == "" then . else .security.auth.baseUrl = $u | .modelProviders.openai[0].baseUrl = $u end)'

    Write-Host "Updating $settings in the guest ..."
    vagrant ssh -c "sudo -u claude jq --arg m '$model' --arg u '$baseUrl' '$filter' $settings > /home/vagrant/qwen-settings.json && sudo install -o claude -g claude -m 600 /home/vagrant/qwen-settings.json $settings && rm -f /home/vagrant/qwen-settings.json"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# Handed to a root-owned launcher rather than to qwen directly, because the host
# credentials the agent may need live in root-owned files that the claude account cannot
# read: the launcher is what reads them, forwards them, and then drops to that account.
#
# Ollama listens on the host, not in the guest, so 11434 is a reverse forward like 64342
# rather than a route to the host's LAN address: -R makes 127.0.0.1:11434 *inside* the
# guest come out of the host's own loopback. A host Ollama left bound to localhost needs
# no rebinding to 0.0.0.0 and no firewall hole, and the guest-side address stays the same
# whatever the provider hands out for the host. Point the agent's baseUrl at
# http://127.0.0.1:11434/v1.
vagrant ssh -c "exec sudo /usr/local/sbin/qwen-agent --dir $startRelQ" -- -t -R 64342:127.0.0.1:64342 -R 11434:127.0.0.1:11434 -L 127.0.0.1:7777:127.0.0.1:7777
exit $LASTEXITCODE
