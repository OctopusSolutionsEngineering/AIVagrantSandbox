#!/bin/bash

# Optional overrides for the model, the reasoning effort, the context window size,
# and the Ollama server, applied to the settings file in the guest below.
# All are left alone when not passed, which is how the IDE calls this.
model=
context_window_size=
reasoning_effort=
ollama_host=

while [ $# -gt 0 ]; do
  case $1 in
      --context-window-size | --model | --ollama-host | --reasoning-effort)
         [ $# -ge 2 ] || { echo "qwen.sh: $1 needs a value" >&2; exit 1; }
        case $1 in
             --model)                 model=$2 ;;
             --context-window-size)         context_window_size=$2 ;;
             --reasoning-effort)      reasoning_effort=$2 ;;
             --ollama-host)           ollama_host=$2 ;;
        esac
         shift 2
          ;;
          *)
         echo "qwen.sh: unknown argument: $1 (expected --context-window-size INTEGER, --model NAME, --reasoning-effort VALUE, or --ollama-host HOST)" >&2
        exit 1
          ;;
  esac
done

# Validate reasoning effort against the allowed values.
if [ -n "$reasoning_effort" ]; then
  case "$reasoning_effort" in
       none | low | medium | high | max) ;;
          *) echo "qwen.sh: --reasoning-effort must be one of: none, low, medium, high, max"; exit 1 ;;
  esac
fi

# The working directory is set to the project currently open in the IDE.
echo "Host project directory: $PWD"

# ── Where the agent starts ───────────────────────────────────────────────────
# Captured before the cd below, which is not optional: `vagrant ssh` only finds the
# box from the directory holding the Vagrantfile, so this script cannot stay where
# it was called from.
#
# Only one host directory is synced into the guest, and it lands at a different
# prefix (/home/claude/Code), so the one description of "here" that means the same
# thing on both sides is the path relative to that root. That is what gets sent;
# the guest resolves it against its own prefix.
#
# Anywhere on the host outside that directory has no guest equivalent at all. Rather
# than invent one, the agent starts at the root of the synced tree and the mismatch is
# reported instead of being silently absorbed — a session that quietly began
# somewhere other than where you were standing is the confusing outcome.
#
# Which directory that is has to be the same answer the Vagrantfile gave when the box
# came up, so the default and the AGENT_CODE_DIR override are spelled the same way in
# both places. The trailing slash goes because the tests below compare against
# "$code_root/", which a doubled slash would not match.
start_dir=$PWD
code_root=${AGENT_CODE_DIR:-$HOME/Code}
code_root=${code_root%/}

case $start_dir in
   "$code_root")
    start_rel=.
     ;;
   "$code_root"/*)
    start_rel=${start_dir#"$code_root"/}
     ;;
   *)
    echo "qwen.sh: $start_dir is outside $code_root, which is the only directory" \
          "synced into the guest — starting the agent at the root of the synced tree" >&2
    start_rel=.
     ;;
esac

# The relative path is spliced into a command string that a shell in the guest
# re-parses, so it has to survive that second round of word splitting intact.
start_rel_q=$(printf '%q' "$start_rel")

# `vagrant ssh` only finds the box from the directory holding the Vagrantfile, which is
# the directory holding this script. Taken from $BASH_SOURCE rather than written out, so
# a clone anywhere on the host works, including one outside the synced tree.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1

if [ ! -f Vagrantfile ]; then
  echo "qwen.sh: no Vagrantfile in $PWD — this script has to stay beside it" >&2
  exit 1
fi

echo "Project Directory: $start_rel_q"

# Edited in place in the guest, where jq is installed by the provisioner. The settings
# file is the agent's own, so the edit persists for later runs; modelProviders.openai[0]
# is the single local-Ollama entry the example settings.json in the Vagrantfile defines.
#
# Four accounts are involved and none of them can do the whole job: jq reads a file only
# the claude account can open, the redirect writes as the vagrant account that ssh landed
# on, and only root can then carry the result across, because /home/vagrant is mode 700
# and claude cannot read back what was staged there. The install flags match the ones the
# Vagrantfile uses for the same file, so the result is owned the same either way.
if [ -n "$model" ] || [ -n "$context_window_size" ] || [ -n "$reasoning_effort" ] || [ -n "$ollama_host" ]; then
  case $ollama_host in
     ''|*://*) base_url=$ollama_host ;;
     *)        base_url="http://$ollama_host:11434/v1" ;;
  esac

  settings=/home/claude/.qwen/settings.json
  filter='(if $c == null then . else .modelProviders.openai[0].generationConfig.contextWindowSize = $c end) | (if $m == "" then . else .model.name = $m | .modelProviders.openai[0].id = $m end) | (if $r == "" then . else .modelProviders.openai[0].options.reasoning_effort = $r end) | (if $u == "" then . else .security.auth.baseUrl = $u | .modelProviders.openai[0].baseUrl = $u end)'

  echo "Updating $settings in the guest ..."
  vagrant ssh -c "sudo -u claude jq --argjson c '$context_window_size' --arg m '$model' --arg r '$reasoning_effort' --arg u '$base_url' '$filter' $settings > /home/vagrant/qwen-settings.json \
     && sudo install -o claude -g claude -m 600 /home/vagrant/qwen-settings.json $settings && rm -f /home/vagrant/qwen-settings.json" || exit 1
fi

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
vagrant ssh -c "exec sudo /usr/local/sbin/qwen-agent --dir $start_rel_q" -- -t \
  -R 64342:127.0.0.1:64342 \
  -R 11434:127.0.0.1:11434 \
  -L 127.0.0.1:7777:127.0.0.1:7777 \
  -R 10000:127.0.0.1:10000 \
  -R 10001:127.0.0.1:10001 \
  -R 10002:127.0.0.1:10002
