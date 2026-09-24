#!/bin/bash

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
    echo "claude.sh: $start_dir is outside $code_root, which is the only directory" \
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
  echo "claude.sh: no Vagrantfile in $PWD — this script has to stay beside it" >&2
  exit 1
fi

echo "Project Directory: $start_rel_q"

vagrant ssh -c "exec sudo /usr/local/sbin/claude-agent --dir $start_rel_q" -- -t -R 64342:127.0.0.1:64342 -R 127.0.0.1:10000:127.0.0.1:10000 -R 127.0.0.1:10001:127.0.0.1:10001 -R 127.0.0.1:10002:127.0.0.1:10002
