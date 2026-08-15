#!/usr/bin/env pwsh

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
function Get-BashSafe([string] $s) { "'" + $s.Replace("'", "'\''") + "'" }

# This assumes that ~/Code/AIVagrantSandbox is the directory containing the Vagrantfile.
# Update this path if your Vagrantfile is located elsewhere.
try {
    Set-Location -LiteralPath (Join-Path $codeRoot 'AIVagrantSandbox') -ErrorAction Stop
}
catch {
    [Console]::Error.WriteLine("qwen.ps1: $($_.Exception.Message)")
    exit 1
}

Write-Host "Project Directory: $startRel"

# Three shells get to re-parse this before qwen ever runs — the guest login shell
# that `vagrant ssh -c` hands the string to, the `bash -c` that sudo starts as the
# claude user, and the path `cd` consumes inside it. Quoting once per layer,
# innermost first, is what keeps a project directory with a space in it from
# arriving as two arguments.
$inner = "cd /home/claude/Code/$(Get-BashSafe $startRel) && exec /home/claude/.npm-global/bin/qwen"
$remote = "exec sudo -u claude bash -c $(Get-BashSafe $inner)"

vagrant ssh -c $remote -- -t -R 64342:127.0.0.1:64342
exit $LASTEXITCODE
