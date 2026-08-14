An example AI agent sandbox built with Vagrant.

# Running Claude Code in a JetBrains IDE

The `claude.sh` or `claude.ps1` script is expected to be called by the IDE when launching Claude Code.

> [!WARNING]
> The port that the IntelliJ MCP server listens on is unique to each host. The port in `claude.sh` or `claude.ps1` must be updated to match the port that the MCP server is listening on.

In InteliJ IDEA and other JetBrains IDEs, you can configure the script to be called by navigating to Tools > Claude Code > Claude Command.

![Claude launch command](launch.png)

Enable the MCP server by navigating to Tools > MCP Server.

![MCP Server](mcp.png)

# Updating Claude Code

Update Claude Code with:

```bash
vagrant ssh
sudo npm update -g @anthropic-ai/claude-code
```