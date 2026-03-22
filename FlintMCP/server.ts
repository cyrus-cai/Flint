#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { execFileSync } from "node:child_process";
import { homedir } from "node:os";
import { existsSync } from "node:fs";
import { join } from "node:path";

// ---------------------------------------------------------------------------
// CLI helper — all logic lives in `flint` CLI, MCP is just an adapter
// ---------------------------------------------------------------------------

// Resolve flint binary — Claude Code's MCP env may not include ~/.local/bin
const FLINT_BIN: string = (() => {
  const candidates = [
    join(homedir(), ".local", "bin", "flint"),
    "/usr/local/bin/flint",
  ];
  for (const p of candidates) {
    if (existsSync(p)) return p;
  }
  return "flint"; // fall back to PATH lookup
})();

function flint(args: string[], input?: string): string {
  return execFileSync(FLINT_BIN, args, {
    encoding: "utf8",
    timeout: 15_000,
    maxBuffer: 10 * 1024 * 1024,
    input,
  }).trim();
}

function ok(text: string) {
  return { content: [{ type: "text" as const, text }] };
}

function err(text: string) {
  return { content: [{ type: "text" as const, text }], isError: true as const };
}

// ---------------------------------------------------------------------------
// MCP Server
// ---------------------------------------------------------------------------

const server = new Server(
  { name: "flint-notes", version: "0.9.7" },
  { capabilities: { tools: {} } },
);

// ---------------------------------------------------------------------------
// Tool definitions
// ---------------------------------------------------------------------------

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "list_notes",
      description:
        "List notes from Flint. Returns title, path, modified (ISO date), preview, source, and type for each note.",
      inputSchema: {
        type: "object" as const,
        properties: {
          week: {
            type: "string",
            description: 'Filter by ISO week, e.g. "2026W12".',
          },
          limit: {
            type: "number",
            description: "Max notes to return.",
          },
        },
      },
    },
    {
      name: "search_notes",
      description:
        "Full-text search across all Flint notes.",
      inputSchema: {
        type: "object" as const,
        properties: {
          query: { type: "string", description: "Search query." },
          title_only: {
            type: "boolean",
            description: "Search titles only (default false).",
          },
        },
        required: ["query"],
      },
    },
    {
      name: "read_note",
      description: "Read the full content of a Flint note by title or path.",
      inputSchema: {
        type: "object" as const,
        properties: {
          identifier: {
            type: "string",
            description: "Note title (without .md) or absolute file path.",
          },
        },
        required: ["identifier"],
      },
    },
    {
      name: "create_note",
      description:
        "Create a new Flint note in the current ISO week folder.",
      inputSchema: {
        type: "object" as const,
        properties: {
          content: { type: "string", description: "Markdown content." },
        },
        required: ["content"],
      },
    },
    {
      name: "edit_note",
      description:
        "Edit an existing Flint note. Provide exactly one of content (full replacement) or append (add to end).",
      inputSchema: {
        type: "object" as const,
        properties: {
          identifier: {
            type: "string",
            description: "Note title or path.",
          },
          content: {
            type: "string",
            description: "New full content (replaces existing).",
          },
          append: {
            type: "string",
            description: "Text to append to the end.",
          },
        },
        required: ["identifier"],
      },
    },
    {
      name: "delete_note",
      description: "Delete a Flint note. confirm must be true.",
      inputSchema: {
        type: "object" as const,
        properties: {
          identifier: {
            type: "string",
            description: "Note title or path.",
          },
          confirm: {
            type: "boolean",
            description: "Must be true to confirm deletion.",
          },
        },
        required: ["identifier", "confirm"],
      },
    },
    {
      name: "get_status",
      description:
        "Get Flint status: notes directory, current week, note counts.",
      inputSchema: { type: "object" as const, properties: {} },
    },
  ],
}));

// ---------------------------------------------------------------------------
// Tool handlers — each maps directly to a `flint` CLI command
// ---------------------------------------------------------------------------

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "list_notes": {
        const a = ["list", "--json"];
        if (args?.week) a.push("--week", String(args.week));
        if (args?.limit) a.push("--limit", String(args.limit));
        return ok(flint(a));
      }

      case "search_notes": {
        if (!args?.query) return err("query is required.");
        const a = ["search", "--json"];
        if (args?.title_only) a.push("--title");
        a.push("--", String(args.query));
        return ok(flint(a));
      }

      case "read_note": {
        if (!args?.identifier) return err("identifier is required.");
        return ok(flint(["read", "--", String(args.identifier)]));
      }

      case "create_note": {
        if (!args?.content) return err("content is required.");
        return ok(flint(["create", "--stdin"], String(args.content)));
      }

      case "edit_note": {
        if (!args?.identifier) return err("identifier is required.");
        const hasContent = args?.content !== undefined;
        const hasAppend = args?.append !== undefined;
        if (!hasContent && !hasAppend)
          return err("Either content or append is required.");
        if (hasContent && hasAppend)
          return err("Provide content or append, not both.");

        const a = ["edit", "--stdin"];
        if (hasAppend) a.push("--append");
        a.push("--", String(args.identifier));
        return ok(flint(a, String(hasContent ? args.content : args.append)));
      }

      case "delete_note": {
        if (args?.confirm !== true)
          return err("confirm must be true to delete.");
        if (!args?.identifier) return err("identifier is required.");
        return ok(flint(["rm", "--force", "--", String(args.identifier)]));
      }

      case "get_status":
        return ok(flint(["status"]));

      default:
        return err(`Unknown tool: ${name}`);
    }
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    return err(msg);
  }
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

await server.connect(new StdioServerTransport());
