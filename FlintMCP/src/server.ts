import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const SERVER_NAME = "flint-notes";
const SERVER_VERSION = "0.9.7";

type ToolArgs = {
    week?: string;
    limit?: number;
    query?: string;
    title_only?: boolean;
    identifier?: string;
    content?: string;
    append?: string;
    confirm?: boolean;
};

const FLINT_BIN = (() => {
    const candidates = [
        join(homedir(), ".local", "bin", "flint"),
        "/usr/local/bin/flint",
    ];

    for (const candidate of candidates) {
        if (existsSync(candidate)) {
            return candidate;
        }
    }

    return "flint";
})();

const tools = [
    {
        name: "list_notes",
        description:
            "List notes from Flint. Returns title, path, modified (ISO date), preview, source, and type for each note.",
        inputSchema: {
            type: "object",
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
        description: "Full-text search across all Flint notes.",
        inputSchema: {
            type: "object",
            properties: {
                query: {
                    type: "string",
                    description: "Search query.",
                },
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
            type: "object",
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
        description: "Create a new Flint note in the current ISO week folder.",
        inputSchema: {
            type: "object",
            properties: {
                content: {
                    type: "string",
                    description: "Markdown content.",
                },
            },
            required: ["content"],
        },
    },
    {
        name: "edit_note",
        description:
            "Edit an existing Flint note. Provide exactly one of content (full replacement) or append (add to end).",
        inputSchema: {
            type: "object",
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
            type: "object",
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
        description: "Get Flint status: notes directory, current week, note counts.",
        inputSchema: {
            type: "object",
            properties: {},
        },
    },
];

function runFlint(args: string[], input?: string): string {
    return execFileSync(FLINT_BIN, args, {
        encoding: "utf8",
        timeout: 15_000,
        maxBuffer: 10 * 1024 * 1024,
        input,
    }).trim();
}

function ok(text: string) {
    return {
        content: [{ type: "text" as const, text }],
    };
}

function err(text: string) {
    return {
        content: [{ type: "text" as const, text }],
        isError: true,
    };
}

const server = new Server(
    { name: SERVER_NAME, version: SERVER_VERSION },
    { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools }));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name } = request.params;
    const args = request.params.arguments as ToolArgs | undefined;

    try {
        switch (name) {
        case "list_notes": {
            const flintArgs = ["list", "--json"];
            if (args?.week) flintArgs.push("--week", String(args.week));
            if (args?.limit != null) flintArgs.push("--limit", String(args.limit));
            return ok(runFlint(flintArgs));
        }
        case "search_notes": {
            if (!args?.query) return err("query is required.");
            const flintArgs = ["search", "--json"];
            if (args.title_only) flintArgs.push("--title");
            flintArgs.push("--", String(args.query));
            return ok(runFlint(flintArgs));
        }
        case "read_note":
            if (!args?.identifier) return err("identifier is required.");
            return ok(runFlint(["read", "--", String(args.identifier)]));
        case "create_note":
            if (!args?.content) return err("content is required.");
            return ok(runFlint(["create", "--stdin"], String(args.content)));
        case "edit_note": {
            if (!args?.identifier) return err("identifier is required.");

            const hasContent = args.content !== undefined;
            const hasAppend = args.append !== undefined;
            if (!hasContent && !hasAppend) {
                return err("Either content or append is required.");
            }
            if (hasContent && hasAppend) {
                return err("Provide content or append, not both.");
            }

            const flintArgs = ["edit", "--stdin"];
            if (hasAppend) flintArgs.push("--append");
            flintArgs.push("--", String(args.identifier));

            return ok(
                runFlint(
                    flintArgs,
                    String(hasContent ? args.content : args.append)
                )
            );
        }
        case "delete_note":
            if (args?.confirm !== true) return err("confirm must be true to delete.");
            if (!args?.identifier) return err("identifier is required.");
            return ok(runFlint(["rm", "--force", "--", String(args.identifier)]));
        case "get_status":
            return ok(runFlint(["status"]));
        default:
            return err(`Unknown tool: ${name}`);
        }
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return err(message);
    }
});

async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
}

main().catch((error) => {
    console.error("Flint MCP server error:", error);
    process.exit(1);
});
