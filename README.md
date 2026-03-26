<p align="center">
  <img src="icon.png" width="128" height="128" alt="Flint icon">
</p>

<h1 align="center">Flint</h1>

<p align="center">
  <b>Opensource alternative to Raycast Note, for humans, for agents.</b>
</p>

Flint lives in the background until you need it. Hit a shortcut and a note appears — type, dismiss, done. If you copy something twice with `Cmd+C`, it becomes a note automatically. Every note is a plain text file on your machine, no account, no cloud. And because Flint speaks MCP, your AI agent — Claude Code, Cursor, whatever you use — can read, search, and create notes just like you do.

<p align="center">
  <img src="screenshot.png" width="720" alt="Flint screenshot">
</p>

## Download

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

**Requirements:** macOS 15+ · Apple Silicon · Xcode 16+

## License

[MIT](LICENSE)
