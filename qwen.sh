#!/bin/bash

# The working directory is set to the project currently open in the IDE.
echo "Host project directory: $PWD"

# ── Where the agent starts ───────────────────────────────────────────────────
# Captured before the cd below, which is not optional: `vagrant ssh` only finds the
# box from the directory holding the Vagrantfile, so this script cannot stay where
# it was called from.
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
start_dir=$PWD
code_root=$HOME/Code

case $start_dir in
  "$code_root")
    start_rel=.
    ;;
  "$code_root"/*)
    start_rel=${start_dir#"$code_root"/}
    ;;
  *)
    echo "qwen.sh: $start_dir is outside $code_root, which is the only directory" \
         "synced into the guest — starting the agent in ~/Code" >&2
    start_rel=.
    ;;
esac

# This assumes that ~/Code/AIVagrantSandbox is the directory containing the Vagrantfile.
# Update this path if your Vagrantfile is located elsewhere.
cd ~/Code/AIVagrantSandbox || exit 1

echo "Project Directory: $start_rel"

# Two shells get to re-parse this before qwen ever runs — the guest login shell
# that `vagrant ssh -c` hands the string to, and the `bash -c` that sudo starts as
# the claude user. Quoting once per layer, innermost first, is what keeps a project
# directory with a space in it from arriving as two arguments.
inner="cd /home/claude/Code/$(printf '%q' "$start_rel") && exec /home/claude/.npm-global/bin/qwen"
remote="exec sudo -u claude bash -c $(printf '%q' "$inner")"

vagrant ssh -c "$remote" -- -t -R 64342:127.0.0.1:64342
