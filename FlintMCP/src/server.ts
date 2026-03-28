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
const SERVER_VERSION = "0.9.28";

type ToolArgs = {
    [key: string]: unknown;
};

const FLINT_BIN = (() => {
    if (process.env.FLINT_BIN) {
        return process.env.FLINT_BIN;
    }

    const candidates = [
        join(homedir(), ".local", "bin", "flint"),
        "/opt/homebrew/bin/flint",
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
                    type: "integer",
                    description: "Max notes to return. Must be a positive integer.",
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
    });
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

function normalizeArgs(args: unknown): ToolArgs {
    if (args == null) {
        return {};
    }

    if (typeof args !== "object" || Array.isArray(args)) {
        throw new Error("arguments must be an object.");
    }

    return args as ToolArgs;
}

function readOptionalString(args: ToolArgs, key: string): string | undefined {
    const value = args[key];
    if (value === undefined) {
        return undefined;
    }
    if (typeof value !== "string") {
        throw new Error(`${key} must be a string.`);
    }
    return value;
}

function readOptionalBoolean(args: ToolArgs, key: string): boolean | undefined {
    const value = args[key];
    if (value === undefined) {
        return undefined;
    }
    if (typeof value !== "boolean") {
        throw new Error(`${key} must be a boolean.`);
    }
    return value;
}

function readOptionalInteger(args: ToolArgs, key: string): number | undefined {
    const value = args[key];
    if (value === undefined) {
        return undefined;
    }
    if (typeof value !== "number" || !Number.isInteger(value)) {
        throw new Error(`${key} must be an integer.`);
    }
    return value;
}

function readOptionalPositiveInteger(args: ToolArgs, key: string): number | undefined {
    const value = readOptionalInteger(args, key);
    if (value === undefined) {
        return undefined;
    }
    if (value <= 0) {
        throw new Error(`${key} must be a positive integer.`);
    }
    return value;
}

const server = new Server(
    { name: SERVER_NAME, version: SERVER_VERSION },
    { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools }));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name } = request.params;

    try {
        const args = normalizeArgs(request.params.arguments);

        switch (name) {
        case "list_notes": {
            const week = readOptionalString(args, "week");
            const limit = readOptionalPositiveInteger(args, "limit");
            const flintArgs = ["list", "--json"];
            if (week) flintArgs.push("--week", week);
            if (limit != null) flintArgs.push("--limit", String(limit));
            return ok(runFlint(flintArgs));
        }
        case "search_notes": {
            const query = readOptionalString(args, "query");
            const titleOnly = readOptionalBoolean(args, "title_only");
            if (!query) return err("query is required.");
            const flintArgs = ["search", "--json"];
            if (titleOnly) flintArgs.push("--title");
            flintArgs.push("--", query);
            return ok(runFlint(flintArgs));
        }
        case "read_note": {
            const identifier = readOptionalString(args, "identifier");
            if (!identifier) return err("identifier is required.");
            return ok(runFlint(["read", "--", identifier]));
        }
        case "create_note": {
            const content = readOptionalString(args, "content");
            if (!content) return err("content is required.");
            return ok(runFlint(["create", "--stdin"], content));
        }
        case "edit_note": {
            const identifier = readOptionalString(args, "identifier");
            const content = readOptionalString(args, "content");
            const append = readOptionalString(args, "append");
            if (!identifier) return err("identifier is required.");

            const hasContent = content !== undefined;
            const hasAppend = append !== undefined;
            if (!hasContent && !hasAppend) {
                return err("Either content or append is required.");
            }
            if (hasContent && hasAppend) {
                return err("Provide content or append, not both.");
            }

            const flintArgs = ["edit", "--stdin"];
            if (hasAppend) flintArgs.push("--append");
            flintArgs.push("--", identifier);

            return ok(
                runFlint(
                    flintArgs,
                    hasContent ? content : append
                )
            );
        }
        case "delete_note": {
            const confirm = readOptionalBoolean(args, "confirm");
            const identifier = readOptionalString(args, "identifier");
            if (confirm !== true) return err("confirm must be true to delete.");
            if (!identifier) return err("identifier is required.");
            return ok(runFlint(["rm", "--force", "--", identifier]));
        }
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

let isShuttingDown = false;

function registerShutdownHandlers() {
    const shutdownSignals: NodeJS.Signals[] = ["SIGINT", "SIGTERM"];

    for (const signal of shutdownSignals) {
        process.on(signal, () => {
            if (isShuttingDown) {
                return;
            }

            isShuttingDown = true;

            void (async () => {
                console.error(`Received ${signal}, shutting down Flint MCP server...`);
                try {
                    await server.close();
                    console.error("Flint MCP server shutdown complete.");
                    process.exit(0);
                } catch (error) {
                    console.error("Flint MCP server shutdown failed:", error);
                    process.exit(1);
                }
            })();
        });
    }
}

async function main() {
    registerShutdownHandlers();
    const transport = new StdioServerTransport();
    await server.connect(transport);
}

main().catch((error) => {
    console.error("Flint MCP server error:", error);
    process.exit(1);
});
