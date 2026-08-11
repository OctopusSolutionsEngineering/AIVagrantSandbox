require "shellwords"

AGENT_USER        = "claude"
AGENT_UID         = 1001
AGENT_HOME        = "/home/#{AGENT_USER}"
AGENT_RUNTIME_DIR = "/run/user/#{AGENT_UID}"

HOST_HOME = File.expand_path("~")

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"

  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.synced_folder File.expand_path("~/Code"), "#{AGENT_HOME}/Code",
    type: "nfs",
    nfs_version: 3,
    nfs_udp: false,
    mount_options: ["actimeo=1", "nolock", "tcp", "rw", "fsc"]

  config.vm.provider "parallels" do |prl, override|
    override.vm.synced_folder File.expand_path("~/Code"), "#{AGENT_HOME}/Code",
    type: nil,
    mount_options: ["share", "rw"]
  end

  config.vm.provider "hyperv" do |prl, override|
    override.vm.box = "generic/ubuntu2204"
    override.vm.synced_folder File.expand_path("~/Code"), "#{AGENT_HOME}/Code",
    type: nil,
    mount_options: ["share", "rw"]
  end

  config.vm.provider "parallels" do |prl|
    prl.memory = 4096
    prl.cpus   = 6
  end

  config.vm.provider "libvirt" do |lv|
    lv.memory = 4096
    lv.cpus   = 6
  end

  config.vm.provider "virtualbox" do |vb|
    vb.memory = 4096
    vb.cpus   = 6
  end

  config.vm.provider "hyperv" do |vb|
    vb.memory = 4096
    vb.cpus   = 6
  end

  anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY') do
    raise "ANTHROPIC_API_KEY is not set on the host. " \
          "Export it before running vagrant up:\n" \
          "  export ANTHROPIC_API_KEY='your-key-here'"
  end

  config.vm.provision "shell",
    run: "always",
    upload_path: "/home/vagrant/vagrant-shell",
    inline: <<-SHELL
    set -euo pipefail
    install -o root -g root -m 600 /dev/null /etc/anthropic_api_key.env
    echo "export ANTHROPIC_API_KEY='#{anthropic_api_key}'" > /etc/anthropic_api_key.env
  SHELL

  config.vm.provision "file",
    source: "~/.claude.json",
    destination: "/home/vagrant/claude.json.upload"

  config.vm.provision "shell",
    upload_path: "/home/vagrant/vagrant-shell",
    inline: <<-SHELL
    set -euo pipefail

    useradd \
      --uid #{AGENT_UID} \
      --home-dir #{AGENT_HOME} \
      --shell /bin/bash \
      -M #{AGENT_USER}

    install -d -o #{AGENT_USER} -g #{AGENT_USER} -m 750 #{AGENT_HOME}

    cat > /usr/local/sbin/claude-agent <<'LAUNCHER'
#!/bin/bash
set -euo pipefail

. /etc/anthropic_api_key.env

# --dir is the directory the agent should start in, given relative to the synced
# tree. claude.sh sends the directory it was called from on the host, which is the
# same tree under a different prefix, so the relative path is all that travels.
# Optional: without it the agent starts at the root, which is what a bare
# `sudo /usr/local/sbin/claude-agent` in the guest still does. Anything left on the
# command line afterwards is passed through to claude untouched.
code_root=#{AGENT_HOME}/Code
target=$code_root
rel=

if [ "${1:-}" = --dir ]; then
  if [ "$#" -lt 2 ]; then
    echo "claude-agent: --dir needs a value" >&2
    exit 2
  fi
  rel=$2
  shift 2
fi

# Validated, but never fatal: a --dir that cannot be honoured should still get you a
# working agent at the root rather than no agent at all. The one thing worth being
# strict about is the shape — --dir names a location inside the synced tree by
# construction, so an absolute path or a .. component is a caller bug, and a caller
# bug that silently starts the agent somewhere outside the tree is worth refusing.
case $rel in
  ""|.)
    ;;
  /*)
    echo "claude-agent: --dir must be relative to $code_root, ignoring '$rel'" >&2
    ;;
  ..|../*|*/..|*/../*)
    echo "claude-agent: --dir must stay inside $code_root, ignoring '$rel'" >&2
    ;;
  *)
    if [ -d "$code_root/$rel" ]; then
      target=$code_root/$rel
    else
      echo "claude-agent: $code_root/$rel does not exist, starting in $code_root" >&2
    fi
    ;;
esac

# The target is handed to the inner shell as a positional argument rather than
# spliced into its script. That script is a single-quoted string, so a path pasted
# into it would be parsed by that shell as code.
exec sudo -u #{AGENT_USER} -H env ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  bash -lc 'cd "$1" || exit 1; shift; exec claude "$@"' claude "$target" "$@"
LAUNCHER

    chown root:root /usr/local/sbin/claude-agent
    chmod 755 /usr/local/sbin/claude-agent

    for skel in /etc/skel/.[!.]*; do
      [ -f "$skel" ] || continue
      install -o #{AGENT_USER} -g #{AGENT_USER} -m 644 \
        "$skel" "#{AGENT_HOME}/$(basename "$skel")"
    done

    install -o #{AGENT_USER} -g #{AGENT_USER} -m 600 \
      /home/vagrant/claude.json.upload #{AGENT_HOME}/.claude.json
    rm -f /home/vagrant/claude.json.upload

    mkdir -p /etc/claude-code
    chown root:root /etc/claude-code
    chmod 755 /etc/claude-code
    cat > /etc/claude-code/managed-settings.json <<'JSON'
{
  "permissions": {
    "deny": [
      "mcp__intellij__execute_terminal_command",
      "mcp__intellij__execute_run_configuration",
      "mcp__intellij__execute_tool",
      "mcp__intellij__build_project",
      "mcp__intellij__run_inspection_kts",
      "mcp__intellij__validate_inspection_kts",
      "mcp__intellij__execute_sql_query",
      "mcp__intellij__xdebug_start_debugger_session",
      "mcp__intellij__xdebug_control_session",
      "mcp__intellij__xdebug_evaluate_expression",
      "mcp__intellij__xdebug_set_variable",
      "mcp__intellij__xdebug_set_breakpoint",
      "mcp__intellij__xdebug_remove_breakpoint",
      "mcp__intellij__xdebug_run_to_line",

      "mcp__intellij__apply_patch",
      "mcp__intellij__create_new_file",
      "mcp__intellij__reformat_file",
      "mcp__intellij__rename_refactoring",

      "mcp__intellij__create_database_connection",
      "mcp__intellij__edit_database_connection",
      "mcp__intellij__test_database_connection",

      "Bash(git add)",
      "Bash(git add:*)",
      "Bash(git commit)",
      "Bash(git commit:*)"
    ]
  },
  "allowManagedPermissionRulesOnly": true,
  "allowManagedHooksOnly": true,
  "disableSideloadFlags": true,
  "env": {
    "CLAUDE_CODE_SUBPROCESS_ENV_SCRUB": "0"
  },
  "sandbox": {
    "enabled": true,
    "allowUnsandboxedCommands": false,
    "excludedCommands": [
      "docker *"
    ],
    "allowManagedReadPathsOnly": true,
    "filesystem": {
      "denyRead": [
        "/etc/*.env",
        "#{AGENT_HOME}/.claude.json"
      ],
      "denyWrite": [
        "#{AGENT_HOME}/.claude.json",
        "#{AGENT_HOME}/.claude/settings*.json",
        "#{AGENT_HOME}/.claude/CLAUDE.md",
        "#{AGENT_HOME}/Code/.claude/settings*.json"
      ]
    },
    "credentials": {
      "files": [
        { "path": "/etc/anthropic_api_key.env", "mode": "deny" },
        { "path": "/etc/github_copilot_token.env", "mode": "deny" },
        { "path": "#{AGENT_HOME}/.claude/settings.json", "mode": "deny" }
      ],
      "envVars": [
        { "name": "ANTHROPIC_API_KEY", "mode": "deny" }
      ]
    }
  }
}
JSON
    chown root:root /etc/claude-code/managed-settings.json
    chmod 444 /etc/claude-code/managed-settings.json

    mkdir -p #{AGENT_HOME}/.claude
    cat > #{AGENT_HOME}/.claude/settings.json <<'JSON'
{
  "skipDangerousModePermissionPrompt": true,
  "acceptEdits": true,
  "permissions": {
    "defaultMode": "bypassPermissions"
  },
  "sandbox": {
    "autoAllowBashIfSandboxed": true
  }
}
JSON

    cat > #{AGENT_HOME}/.claude/CLAUDE.md <<'MARKDOWN'
# Filesystem paths in this sandbox

You are running inside a Vagrant guest VM. The user, their IDE, and their
terminal are on the *host* machine. The host directory `#{HOST_HOME}/Code` is
synced to `#{AGENT_HOME}/Code` in this guest — same files, different prefix.

Any path that reaches you from the host side uses the host prefix and is NOT
valid here. This includes:

- the path of the file currently open in the user's IDE
- paths in IDE diagnostics, selections, or attached editor context
- paths the user types or pastes, and paths in output copied from the host

## Translate before every tool call

Rewrite the prefix, keep the rest of the path unchanged:

| Host path | Guest path to use |
| --- | --- |
| `#{HOST_HOME}/Code/<rest>` | `#{AGENT_HOME}/Code/<rest>` |
| `~/Code/<rest>` | `#{AGENT_HOME}/Code/<rest>` |
| `#{HOST_HOME}/<rest>` (outside `Code`) | not available in this sandbox |

For example, if the IDE reports the open file as
`#{HOST_HOME}/Code/MyProject/src/main.ts`, read and edit
`#{AGENT_HOME}/Code/MyProject/src/main.ts`.

Only `~/Code` is synced. If a host path falls outside it, do not invent a guest
equivalent and do not create the directory to make the path resolve — say the
file is not mounted into the sandbox and ask the user how to proceed.

## Translating back

Use guest paths for every tool call, and when you quote a path in your answer.
The exception is when you are telling the user which file to open on the host
(so their IDE can resolve it) — give the `#{HOST_HOME}/...` form there, and say
which side of the mapping the path belongs to.

The synced folder is mounted read-write, so edits you make under
`#{AGENT_HOME}/Code` appear on the host immediately. These are the user's real
working files, not a throwaway copy — treat them accordingly.

# The account you are running as

You are the `#{AGENT_USER}` user. It is unprivileged on purpose: it has no sudo, no
password, and no membership of the `sudo`, `docker`, `lxd` or `adm` groups. The
`vagrant` account, and its home directory, are not yours to read or write.

So: install nothing system-wide. `apt-get`, `npm install -g` and anything else
needing root will fail, and that is the configuration working, not a problem to
route around. Use a venv, `npm install` into the project, or the rootless Docker
daemon already running for you (`DOCKER_HOST` is set in your environment). If a
task genuinely needs root in this VM, say so and ask the user to run it from the
host with `vagrant ssh`.
MARKDOWN

    chown -R #{AGENT_USER}:#{AGENT_USER} #{AGENT_HOME}/.claude
    chown root:root #{AGENT_HOME}/.claude/settings.json #{AGENT_HOME}/.claude/CLAUDE.md
    chmod 444 #{AGENT_HOME}/.claude/settings.json
    chmod 444 #{AGENT_HOME}/.claude/CLAUDE.md

    touch /home/.mcp.json
    chown root:root /home/.mcp.json
    chmod 444 /home/.mcp.json

    apt-get update -y
    apt-get upgrade -y
    apt-get install -y \
      auditd \
      binfmt-support \
      build-essential \
      curl \
      dbus-user-session \
      fuse-overlayfs \
      git \
      jq \
      python3 \
      python3-pip \
      python3-venv \
      qemu-user-static \
      screen \
      slirp4netns \
      uidmap \
      unzip \
      ufw \
      btop \
      bubblewrap \
      socat

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | dd of=/etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras

    systemctl disable --now docker.service docker.socket containerd.service || true
    systemctl mask docker.service docker.socket
    rm -f /run/docker.sock

    grep -q "^#{AGENT_USER}:" /etc/subuid || usermod --add-subuids 165536-231071 #{AGENT_USER}
    grep -q "^#{AGENT_USER}:" /etc/subgid || usermod --add-subgids 165536-231071 #{AGENT_USER}

    loginctl enable-linger #{AGENT_USER}
    for _ in $(seq 1 30); do [ -d #{AGENT_RUNTIME_DIR} ] && break; sleep 1; done
    [ -d #{AGENT_RUNTIME_DIR} ] || { echo "XDG_RUNTIME_DIR for #{AGENT_USER} never appeared"; exit 1; }

    sudo -u #{AGENT_USER} -H env \
      XDG_RUNTIME_DIR=#{AGENT_RUNTIME_DIR} \
      DBUS_SESSION_BUS_ADDRESS=unix:path=#{AGENT_RUNTIME_DIR}/bus \
      PATH=/usr/bin:/usr/sbin:/bin:/sbin \
      dockerd-rootless-setuptool.sh install
    sudo -u #{AGENT_USER} -H env \
      XDG_RUNTIME_DIR=#{AGENT_RUNTIME_DIR} \
      DBUS_SESSION_BUS_ADDRESS=unix:path=#{AGENT_RUNTIME_DIR}/bus \
      systemctl --user enable --now docker

    cat > /etc/profile.d/docker-rootless.sh <<'PROFILE'
if [ "$(id -u)" = "#{AGENT_UID}" ]; then
  export XDG_RUNTIME_DIR=#{AGENT_RUNTIME_DIR}
  export DOCKER_HOST=unix://#{AGENT_RUNTIME_DIR}/docker.sock
fi
PROFILE
    chown root:root /etc/profile.d/docker-rootless.sh
    chmod 644 /etc/profile.d/docker-rootless.sh

    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs

    npm install -g @anthropic-ai/claude-code
  SHELL

  config.vm.provision "claude-mcp-paths",
    type: "shell",
    run: "always",
    upload_path: "/home/vagrant/vagrant-shell",
    inline: <<-SHELL
    set -euo pipefail

    command -v jq >/dev/null || { echo "jq is not installed yet; run the main provisioner first"; exit 1; }

    config=#{AGENT_HOME}/.claude.json
    host_prefix=#{Shellwords.escape("#{HOST_HOME}/Code")}
    guest_prefix=#{AGENT_HOME}/Code

    [ -s "$config" ] || { echo "no $config to rewrite"; exit 0; }
    jq -e . "$config" >/dev/null 2>&1 || { echo "$config is not valid JSON; leaving it alone"; exit 0; }

    tmp=$(mktemp "$config.XXXXXX")
    jq --arg host "$host_prefix" --arg guest "$guest_prefix" '
      def retarget: (. / $host) | join($guest);
      walk(if type == "string" then retarget else . end)
      | if (.projects | type) == "object" then
          .projects = reduce (.projects | to_entries[]) as $e ({};
            .[$e.key | retarget] = ((.[$e.key | retarget] // {}) + $e.value))
        else . end
    ' "$config" > "$tmp"
    chown #{AGENT_USER}:#{AGENT_USER} "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$config"

    echo "rewrote MCP host paths: $host_prefix -> $guest_prefix"
  SHELL

  config.vm.provision "claude-trust",
    type: "shell",
    run: "always",
    upload_path: "/home/vagrant/vagrant-shell",
    inline: <<-SHELL
    set -euo pipefail

    command -v jq >/dev/null || { echo "jq is not installed yet; run the main provisioner first"; exit 1; }

    config=#{AGENT_HOME}/.claude.json
    [ -s "$config" ] || install -o #{AGENT_USER} -g #{AGENT_USER} -m 600 /dev/null "$config"
    jq -e . "$config" >/dev/null 2>&1 || printf '{}' > "$config"

    tmp=$(mktemp "$config.XXXXXX")
    jq '.projects["#{AGENT_HOME}/Code"] =
          (.projects["#{AGENT_HOME}/Code"] // {}) + {"hasTrustDialogAccepted": true}' \
      "$config" > "$tmp"
    chown #{AGENT_USER}:#{AGENT_USER} "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$config"

    echo "trusted workspace: #{AGENT_HOME}/Code"
  SHELL

  config.vm.provision "apparmor-bwrap",
    type: "shell",
    run: "always",
    upload_path: "/home/vagrant/vagrant-shell",
    inline: <<-SHELL
    set -euo pipefail

    cat > /etc/apparmor.d/bwrap <<'PROFILE'
# This profile allows everything and only exists to give the
# application a name instead of having the label "unconfined"

abi <abi/4.0>,
include <tunables/global>

profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,

  # Site-specific additions and overrides. See local/README for details.
  include if exists <local/bwrap>
}
PROFILE
    chown root:root /etc/apparmor.d/bwrap
    chmod 644 /etc/apparmor.d/bwrap

    apparmor_parser -r -W /etc/apparmor.d/bwrap

    # Fail provisioning loudly if the sandbox still cannot start, rather than
    # leaving the agent with a Bash tool that errors on every command. Probed as the
    # account that will actually run bwrap; this provisioner is ordered after the main
    # one, which is what creates it.
    sudo -u #{AGENT_USER} bwrap --ro-bind / / --unshare-net --dev /dev true
    echo "bwrap sandbox: OK (user namespace + loopback)"
  SHELL
end
