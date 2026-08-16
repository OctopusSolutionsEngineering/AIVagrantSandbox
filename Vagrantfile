require "shellwords"

AGENT_USER        = "claude"
AGENT_UID         = 1001
AGENT_HOME        = "/home/#{AGENT_USER}"
AGENT_RUNTIME_DIR = "/run/user/#{AGENT_UID}"

HOST_HOME = File.expand_path("~")

# Pinned rather than resolved to "latest" at provision time, so two boxes built a month
# apart get the same shell, and so the download can be checked against a digest that is
# known before the request is made. Bump this to upgrade.
PWSH_VERSION = "7.6.4"

# Credentials read from the host environment and pushed into the guest as root-owned
# files under /etc, one per variable. ANTHROPIC_API_KEY is handled on its own below
# because it is mandatory — without it there is no agent at all — whereas these are only
# wanted by some of the tools the agent can reach, so a host that has not exported them
# should still be able to bring the box up.
OPTIONAL_HOST_CREDENTIALS = %w[AZURE_STORAGE_ACCOUNT_KEY OCTOPUS_API_KEY].freeze

# One place to derive the file name from the variable name, so that the provisioner
# writing the file, the launcher sourcing it, and the sandbox rule denying reads of it
# cannot drift apart about where it lives.
def credential_env_file(name)
  "/etc/#{name.downcase}.env"
end

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"

  config.vm.provider "hyperv" do |hv, override|
    override.vm.box = "boxen/ubuntu-24.04"
  end

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

  config.vm.provider "hyperv" do |hv, override|
    override.vm.synced_folder File.expand_path("~/Code"), "#{AGENT_HOME}/Code",
    type: "smb",
    mount_options: ["rw", "uid=#{AGENT_UID}", "gid=#{AGENT_UID}", "mfsymlinks"]
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

  config.vm.provider "hyperv" do |hv|
    hv.maxmemory = 4096
    hv.cpus   = 6
  end

  anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY') do
    raise "ANTHROPIC_API_KEY is not set on the host. " \
          "Export it before running vagrant up:\n" \
          "  export ANTHROPIC_API_KEY='your-key-here'"
  end

  # Reported rather than raised, for the reason given at OPTIONAL_HOST_CREDENTIALS. Each
  # value is read once, here, so the script generated below is built from one snapshot of
  # the host environment instead of consulting it again further down.
  optional_credentials = OPTIONAL_HOST_CREDENTIALS.map do |name|
    value = ENV[name]
    if value.nil? || value.empty?
      warn "#{name} is not set on the host, so the guest will not receive it. " \
           "Export it before running vagrant up if the agent needs it."
      nil
    else
      [name, value]
    end
  end.compact

  # Quoted by Ruby rather than by hand, so that a key containing a space or a quote
  # cannot arrive in the guest as shell syntax instead of as the key.
  write_optional_credentials = optional_credentials.map do |name, value|
    file = credential_env_file(name)
    line = "export #{name}=#{Shellwords.escape(value)}"
    "    install -o root -g root -m 600 /dev/null #{file}\n" \
    "    printf '%s\\n' #{Shellwords.escape(line)} > #{file}\n"
  end.join

  # A key provisioned earlier and absent from the host environment now is left in place:
  # this provisioner cannot tell a revoked key from a vagrant up run in a shell that
  # happened not to export it, and deleting one on the strength of that guess costs more
  # than keeping it. It does say so, though — a guest still running on a credential the
  # host no longer has is worth hearing about.
  report_stale_credentials =
    (OPTIONAL_HOST_CREDENTIALS - optional_credentials.map(&:first)).map do |name|
      file = credential_env_file(name)
      "    if [ -e #{file} ]; then\n" \
      "      echo \"#{name} is unset on the host, but #{file} from an earlier provision " \
      "is still in place and will still be used; delete it in the guest to revoke it.\" >&2\n" \
      "    fi\n"
    end.join

  config.vm.provision "shell",
    run: "always",
    upload_path: "/home/vagrant/vagrant-shell",
    inline: <<-SHELL
#!/bin/bash
    set -euo pipefail
    install -o root -g root -m 600 /dev/null /etc/anthropic_api_key.env
    echo "export ANTHROPIC_API_KEY='#{anthropic_api_key}'" > /etc/anthropic_api_key.env

    # The optional host credentials get the same treatment: one root-owned, mode 600 file
    # each, rewritten from the host environment on every boot because this provisioner
    # runs always. Lines below are generated, so nothing appears here for a key the host
    # did not export.
#{write_optional_credentials}#{report_stale_credentials}
    # This is a dummy environment variable used by QWEN Code when running against
    # a local Ollama server.
    #
    # This is an example ~/.qwen/settings.json file, assuming Ollama is running on 192.168.1.1:
    # {
    #   "security": {
    #     "auth": {
    #       "selectedType": "openai",
    #       "apiKey": "sk-12345-dummy-password-ollama",
    #       "baseUrl": "http://192.168.1.1:11434/v1"
    #     }
    #   },
    #   "model": {
    #     "name": "qwen3.6:35b-a3b"
    #   },
    #   "modelProviders": {
    #     "openai": [
    #       {
    #         "id": "qwen3.6:35b-a3b",
    #         "name": "Qwen (Local)",
    #         "baseUrl": "http://192.168.1.1:11434/v1",
    #         "envKey": "OLLAMA_DUMMY_KEY"
    #       }
    #     ]
    #   },
    #   "$version": 4,
    #   "tools": {
    # 	  "approvalMode": "yolo"
    #   },
    #   "mcpServers": {
    # 	  "idea":  {
    # 	    "type": "sse",
    # 		"url": "http://127.0.0.1:64342/sse"
    # 	  }
    #   },
    #   "mcp": {
    #     "excluded": []
    #   }
    # }
    grep -q '^OLLAMA_DUMMY_KEY=' /etc/environment || echo 'OLLAMA_DUMMY_KEY=dummy' >> /etc/environment
  SHELL

  config.vm.provision "file",
    source: "~/.claude.json",
    destination: "/home/vagrant/claude.json.upload"

  # Copy QWEN settings if they exist
  qwen_settings_source = File.join(HOST_HOME, ".qwen", "settings.json")
  if File.file?(qwen_settings_source)
    config.vm.provision "file",
      source: qwen_settings_source,
      destination: "/home/vagrant/qwen-settings.json.upload"
  end

  config.vm.provision "shell",
    upload_path: "/home/vagrant/vagrant-shell",
    inline: <<-SHELL
#!/bin/bash
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

# The optional credentials, as name:file pairs so this script never has to re-derive one
# from the other. Each file is root-owned and mode 600, readable only here, in the
# launcher, which is the last thing to run as root before the agent is dropped to its own
# account; whatever is present is forwarded into that account's environment and whatever
# the host did not provide is simply not forwarded.
agent_env=(ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY")

for entry in #{OPTIONAL_HOST_CREDENTIALS.map { |name| "#{name}:#{credential_env_file(name)}" }.join(" ")}; do
  name=${entry%%:*}
  file=${entry#*:}
  [ -r "$file" ] || continue
  . "$file"
  agent_env+=("$name=${!name-}")
done

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
exec sudo -u #{AGENT_USER} -H env "${agent_env[@]}" \
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

    # Only copy qwen settings if they were uploaded from the host.
    if [ -s /home/vagrant/qwen-settings.json.upload ]; then
      install -d -o #{AGENT_USER} -g #{AGENT_USER} -m 700 "#{AGENT_HOME}/.qwen"
      install -o #{AGENT_USER} -g #{AGENT_USER} -m 600 \
        /home/vagrant/qwen-settings.json.upload "#{AGENT_HOME}/.qwen/settings.json"
    fi
    rm -f /home/vagrant/qwen-settings.json.upload

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
        "#{AGENT_HOME}/.agents/AGENTS.md",
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

## Exception: JetBrains IDE tools (`mcp__idea__*`)

These MCP tools address the user's IDE, not the sandbox filesystem, and the IDE
works in host paths. Their path arguments — `projectPath`, `filePath`, and the
like — take the **host** prefix, which inverts the rule above:

- `projectPath` for a project inside the synced tree: `#{HOST_HOME}/Code/<project>`.
- If you are about to hand an `#{AGENT_HOME}/Code/...` path to an IDE MCP
  argument, you are on the wrong side of the mapping — rewrite it to the host
  prefix first.

If such a call fails with "`projectPath` ... doesn't correspond to any open
project", the error includes the IDE's currently open projects — retry with one
of those paths rather than the one you just passed.

## Translating back

Use guest paths for every filesystem tool call — the JetBrains IDE tools above
are the exception — and when you quote a path in your answer.
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

    # Agents that read AGENTS.md rather than CLAUDE.md get the same briefing. The
    # copy is taken here, immediately after the heredoc, so the two files cannot
    # drift: both are rewritten from the same source on every provision.
    mkdir -p #{AGENT_HOME}/.agents
    cp #{AGENT_HOME}/.claude/CLAUDE.md #{AGENT_HOME}/.agents/AGENTS.md

    chown -R #{AGENT_USER}:#{AGENT_USER} #{AGENT_HOME}/.claude #{AGENT_HOME}/.agents
    chown root:root #{AGENT_HOME}/.claude/settings.json #{AGENT_HOME}/.claude/CLAUDE.md #{AGENT_HOME}/.agents/AGENTS.md
    chmod 444 #{AGENT_HOME}/.claude/settings.json
    chmod 444 #{AGENT_HOME}/.claude/CLAUDE.md
    chmod 444 #{AGENT_HOME}/.agents/AGENTS.md

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
      ruby-full \
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

    # qwen-code-no-telemetry — pinned to a no-telemetry fork version.
    # Bump QWEN_VERSION here to upgrade; the script skips gracefully if
    # the exact version is already present.
    QWEN_VERSION="v0.21.11-no-telemetry"
    if sudo -u #{AGENT_USER} -H env QWEN_VERSION="$QWEN_VERSION" bash -lc \
      'npm list -g qwen-code 2>/dev/null | grep -q "$QWEN_VERSION"'; then
      echo "qwen-code $QWEN_VERSION is already installed"
    else
      echo "installing qwen-code $QWEN_VERSION ..."
      sudo -u #{AGENT_USER} -H env QWEN_VERSION="$QWEN_VERSION" bash -lc \
        'curl -fsSL https://raw.githubusercontent.com/undici77/qwen-code-no-telemetry/v0.21.11-no-telemetry/install.sh | bash -s "$QWEN_VERSION"'
    fi
  SHELL

  # PowerShell is installed from the tar.gz binary archive rather than from Microsoft's
  # apt repository, because that repository publishes the package for amd64 only: on an
  # Arm host `apt-get install powershell` finds nothing and the box comes up without a
  # shell it was asked for. The binary archive is published for both instruction sets,
  # so the architecture is detected here and the matching file is fetched.
  config.vm.provision "powershell",
    type: "shell",
    upload_path: "/home/vagrant/vagrant-shell",
    inline: <<-SHELL
#!/bin/bash
    set -euo pipefail

    command -v curl >/dev/null || { echo "curl is not installed yet; run the main provisioner first"; exit 1; }

    version=#{PWSH_VERSION}
    install_dir=/opt/microsoft/powershell/7

    # pwsh creates $XDG_CACHE_HOME/powershell before it does anything else, and aborts
    # with an unhandled TypeInitializationException if that mkdir fails. The agent runs
    # its commands inside a sandbox that only allows writes to a short list of paths, so
    # the mkdir is denied there and pwsh dies before printing its banner. Creating the
    # directory here — as the account that will use it — is enough: pwsh is happy once
    # the path exists and does not write into it on startup.
    #
    # Ahead of the already-installed check below, so that a box provisioned before this
    # directory was part of the recipe still gets it.
    install -d -o #{AGENT_USER} -g #{AGENT_USER} -m 700 \\
      #{AGENT_HOME}/.cache #{AGENT_HOME}/.cache/powershell

    # dpkg's architecture is the thing to branch on rather than `uname -m`, because it
    # names the userland that is actually installed instead of the CPU underneath it: a
    # 64-bit Arm kernel can carry a 32-bit userland, and there uname reports aarch64
    # while every binary on the box is armhf. The release assets spell the names
    # differently again — amd64 is x64 there — hence the mapping rather than reuse.
    deb_arch=$(dpkg --print-architecture)
    case $deb_arch in
      amd64) arch=x64   ;;
      arm64) arch=arm64 ;;
      *)
        echo "PowerShell publishes no Linux binary archive for $deb_arch" >&2
        exit 1
        ;;
    esac

    if [ -x "$install_dir/pwsh" ] &&
       "$install_dir/pwsh" --version 2>/dev/null | grep -qx "PowerShell $version"; then
      echo "PowerShell $version ($arch) is already installed"
      exit 0
    fi

    tarball=powershell-$version-linux-$arch.tar.gz
    release=https://github.com/PowerShell/PowerShell/releases/download/v$version

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    echo "fetching $tarball for $deb_arch"
    curl -fsSL -o "$tmp/$tarball" "$release/$tarball"

    # A single hashes.sha256 covers every artifact in the release, so the line for this
    # exact filename is selected before checking. Handing the whole file to sha256sum
    # would let a wrong-architecture download pass by matching another asset's digest.
    #
    # That file is generated on Windows and published as UTF-16 with a byte order mark
    # and CRLF endings, so it has to be decoded before anything compares bytes with it:
    # awk sees a NUL between every character of the filename and matches no ASCII
    # string. (GNU grep converts UTF-16 input silently, which makes this easy to miss
    # when probing by hand.) The BOM is tested rather than converted unconditionally, so
    # a release that switches to plain UTF-8 keeps working. -f UTF-16 rather than
    # UTF-16LE, because that spelling consumes the BOM instead of translating it into
    # the front of the first digest.
    curl -fsSL -o "$tmp/hashes.sha256" "$release/hashes.sha256"
    case $(head -c 2 "$tmp/hashes.sha256" | od -An -tx1 | tr -d ' \\n') in
      fffe|feff) iconv -f UTF-16 -t UTF-8 < "$tmp/hashes.sha256" ;;
      *)         cat "$tmp/hashes.sha256" ;;
    esac | tr -d '\\r' > "$tmp/hashes.txt"

    awk -v f="$tarball" '$2 == f || $2 == "*" f' "$tmp/hashes.txt" > "$tmp/expected"
    [ -s "$tmp/expected" ] || { echo "no published sha256 line for $tarball" >&2; exit 1; }
    ( cd "$tmp" && sha256sum -c expected )

    # Replaced outright rather than unpacked over the top, so that files belonging to a
    # previous version cannot survive an upgrade and shadow the new ones.
    rm -rf "$install_dir"
    mkdir -p "$install_dir"
    tar -xzf "$tmp/$tarball" -C "$install_dir"
    chmod +x "$install_dir/pwsh"
    ln -sf "$install_dir/pwsh" /usr/local/bin/pwsh

    pwsh --version
  SHELL

  config.vm.provision "claude-mcp-paths",
    type: "shell",
    run: "always",
    upload_path: "/home/vagrant/vagrant-shell",
    inline: <<-SHELL
#!/bin/bash
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
#!/bin/bash
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
#!/bin/bash
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
