An example AI agent sandbox built with Vagrant.

[Sandboxing local AI Agents](https://octopus.com/blog/local-ai-agent-sandboxes)

# Host environment variables

Credentials are read from the environment of the shell that runs `vagrant up` and written
into the guest as root-owned files under `/etc`, refreshed on every boot.

| Variable | Required | Guest file |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | yes — `vagrant up` fails without it | `/etc/anthropic_api_key.env` |
| `AZURE_STORAGE_ACCOUNT_KEY` | no | `/etc/azure_storage_account_key.env` |
| `OCTOPUS_API_KEY` | no | `/etc/octopus_api_key.env` |

```bash
export ANTHROPIC_API_KEY='your-key-here'
export AZURE_STORAGE_ACCOUNT_KEY='your-key-here'
export OCTOPUS_API_KEY='your-key-here'
vagrant up
```

The optional ones are reported and skipped if unset, so the box still comes up without
them. A key that was provisioned earlier is left in place rather than deleted when it is
missing from the host environment; `vagrant up` says so, and the file can be removed in
the guest to revoke it.

The files are root-owned and mode 600, so the `claude` account cannot read them itself.
They are picked up by the root-owned launchers — `/usr/local/sbin/claude-agent` and
`/usr/local/sbin/qwen-agent` — which forward them into the agent's environment and then
drop to that account. Both launchers forward the optional credentials; only
`claude-agent` forwards `ANTHROPIC_API_KEY`, since Qwen has no use for it.

`ANTHROPIC_API_KEY` is additionally denied to Claude Code's own sandboxed Bash tool by
`/etc/claude-code/managed-settings.json`, so a command the agent runs cannot read or leak
it. The optional credentials carry no such rule and are readable by commands the agent
runs — which is what makes them usable from `az` or `octo`, and what to weigh before
adding a key here.

# Running Claude Code in a JetBrains IDE

The `claude.sh` or `claude.ps1` script is expected to be called by the IDE when launching Claude Code.

# Updating Claude Code

Update Claude Code with:

```bash
vagrant ssh
sudo npm update -g @anthropic-ai/claude-code
```

# Running QWEN

Run `qwen.sh` or `qwen.ps1` to launch QWEN Code.

# Configuring IDE MCP server

> [!WARNING]
> The port that the IntelliJ MCP server listens on is unique to each host. The port in `claude.sh` or `claude.ps1` must be updated to match the port that the MCP server is listening on.

In InteliJ IDEA and other JetBrains IDEs, you can configure the script to be called by navigating to Tools > Claude Code > Claude Command.

![Claude launch command](launch.png)

Enable the MCP server by navigating to Tools > MCP Server.

![MCP Server](mcp.png)
