<p align="center">
  <img src="icon.png" width="128" height="128" alt="Flint icon">
</p>

<h1 align="center">Flint</h1>
<p align="center">
  <b>Opensource alternative to Raycast Note, for humans, for agents.</b>
</p>
<p align="center">
  <a href="https://github.com/cyrus-cai/Flint/releases/latest"><img src="https://img.shields.io/github/v/release/cyrus-cai/Flint?include_prereleases&label=version" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/cyrus-cai/Flint" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-blue" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Apple_Silicon-required-blue" alt="Apple Silicon">
  <a href="https://github.com/cyrus-cai/Flint/stargazers"><img src="https://img.shields.io/github/stars/cyrus-cai/Flint?style=social" alt="GitHub stars"></a>
</p>

Flint lives in the background until you need it. Hit a shortcut and a note appears — type, dismiss, done. Copy something twice with `Cmd+C` and it becomes a note automatically. Every note is a plain Markdown file on your machine, no account, no cloud. And because Flint speaks [MCP](https://modelcontextprotocol.io), your AI agent — Claude Code, Cursor, whatever you use — can read, search, and create notes just like you do.

## Features

<table>
<tr>
<td width="50%">

### AI Capture
Press `Cmd+C` — AI decides if it's worth keeping, generates a title, and saves it as a note.

</td>
<td width="50%">
<img src="feature-history.png" width="400" alt="Note history with AI titles">
</td>
</tr>
<tr>
<td width="50%">
<img src="feature-ai.png" width="400" alt="AI settings and MCP server">
</td>
<td width="50%">

### AI + MCP Native
Ships with an MCP server — Claude Code, Cursor, and other AI tools can read, search, and create your notes.

</td>
</tr>
<tr>
<td width="50%">

### Keyboard-First
Every action has a shortcut. Quick wake-up, new note, copy all, navigate — no mouse needed.

</td>
<td width="50%">
<img src="feature-shortcuts.png" width="400" alt="Keyboard shortcuts settings">
</td>
</tr>
<tr>
<td width="50%">
<img src="feature-personal.png" width="400" alt="Theme and editor personalization">
</td>
<td width="50%">

### Make It Yours
Light, Dark, or Liquid Glass. Four fonts. Notes live in a folder you choose — works as an Obsidian vault.

</td>
</tr>
</table>

## Install

**Claude Code:**
```
Install Flint — https://github.com/cyrus-cai/Flint/releases/latest
```

**Homebrew:**
```bash
brew install --cask https://raw.githubusercontent.com/cyrus-cai/Flint/main/homebrew/Casks/flint.rb
```

**Shell:**
```bash
curl -fsSL https://raw.githubusercontent.com/cyrus-cai/Flint/main/scripts/install.sh | bash -s -- --beta
```

## MCP Server

```bash
claude mcp add flint-notes -- node /Applications/Flint.app/Contents/Resources/FlintMCP/dist/server.mjs
```

**Tools:** `list_notes` · `search_notes` · `read_note` · `create_note` · `edit_note` · `delete_note` · `get_status`

For Cursor / Windsurf / other MCP clients, use the same command in your MCP config.

## Build from Source

```bash
git clone https://github.com/cyrus-cai/Flint.git && cd Flint && open Flint.xcodeproj
```

Requires macOS 15+, Apple Silicon, Xcode 16+.

## [Contributing](CONTRIBUTING.md) · [License (MIT)](LICENSE)
