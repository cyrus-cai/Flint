<p align="center">
  <img src="Flint/Assets.xcassets/AppIcon.appiconset/容器 2@2x.png" width="128" height="128" alt="Flint icon">
</p>

<h1 align="center">Flint</h1>

<p align="center">
  A lightweight macOS note-taking app with MCP server for AI agents.
</p>

<p align="center">
  <b>macOS 14.6+</b> &nbsp;|&nbsp; Apple Silicon & Intel
</p>

<p align="center">
  <a href="https://github.com/cyrus-cai/Flint/releases">Download</a> &middot;
  <a href="#mcp-server">MCP</a> &middot;
  <a href="#building-from-source">Build</a> &middot;
  <a href="docs/release.md">Release</a>
</p>

---

## Features

- **Global Hotkey** — Capture a note from anywhere with a single keystroke
- **Double `Cmd+C`** — Auto-save clipboard content as a note
- **MCP Server** — Let AI agents (Claude Code, Cursor, etc.) read, create, search, and edit your notes
- **Local-Only** — All notes stored as plain text files on your machine. No account, no cloud

## Download

Get the latest release from [GitHub Releases](https://github.com/cyrus-cai/Flint/releases). Download `Flint.zip`, unzip, and drag to Applications.

Or install directly from the command line:

```bash
curl -fsSL https://raw.githubusercontent.com/cyrus-cai/Flint/main/scripts/install.sh | bash
```

Install the latest beta release:

```bash
curl -fsSL https://raw.githubusercontent.com/cyrus-cai/Flint/main/scripts/install.sh | bash -s -- --beta
```

## MCP Server

Flint ships with an MCP server (`FlintMCP/`) that exposes your notes to any MCP-compatible AI client.

**Available tools:** `list_notes` · `search_notes` · `read_note` · `create_note` · `edit_note` · `delete_note` · `get_status`

To connect, add the MCP server config in your AI client (Claude Code, Cursor, etc.) — see [MCP documentation](https://modelcontextprotocol.io) for details.

## Building from Source

```bash
git clone https://github.com/cyrus-cai/Flint.git
cd Flint
open Flint.xcodeproj
```

Select your development team under **Signing & Capabilities**, then build and run (`Cmd+R`).

**Requirements:** Xcode 16+

## License

[MIT](LICENSE)
