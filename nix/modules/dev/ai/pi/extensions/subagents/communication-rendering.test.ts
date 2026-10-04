import assert from "node:assert/strict";
import test from "node:test";
import {
  initTheme,
  type ExtensionAPI,
  type Theme,
} from "@earendil-works/pi-coding-agent";
import subagentsExtension from "./index.ts";
import {
  renderCommunicationCard,
  renderCommunicationToolCall,
  renderCommunicationToolResult,
} from "./src/ui/communication.ts";

const theme = {
  fg: (_color: string, text: string) => text,
  bg: (_color: string, text: string) => `[card]${text}[/card]`,
  bold: (text: string) => text,
} as unknown as Theme;

const rendered = (component: { render(width: number): string[] }) =>
  component.render(120).join("\n");

test("communication tool calls identify guidance and correlated replies", () => {
  assert.match(
    rendered(
      renderCommunicationToolCall(
        { id: "sa-7", kind: "guidance" },
        theme,
      ),
    ),
    /→ subagent sa-7 · guidance/,
  );
  assert.match(
    rendered(
      renderCommunicationToolCall(
        { id: "sa-7", requestId: "req-2", kind: "reply" },
        theme,
      ),
    ),
    /→ subagent sa-7 · reply · req-2/,
  );
});

test("expanded communication tool output reveals the full sent message", () => {
  initTheme("dark", false);
  const message = "Please inspect **both** failing tests.\n\nKeep the API stable.";
  const collapsed = rendered(
    renderCommunicationToolResult(
      {
        summary: "Message accepted for sa-7.",
        message,
        expanded: false,
        isPartial: false,
        isError: false,
      },
      theme,
    ),
  );
  assert.match(collapsed, /Message accepted for sa-7/);
  assert.doesNotMatch(collapsed, /Keep the API stable/);

  const expanded = rendered(
    renderCommunicationToolResult(
      {
        summary: "Message accepted for sa-7.",
        message,
        expanded: true,
        isPartial: false,
        isError: false,
      },
      theme,
    ),
  );
  assert.match(expanded, /Message/);
  assert.match(expanded, /Please inspect \*\*both\*\* failing tests/);
  assert.match(expanded, /Keep the API stable/);
});

test("registered send and reply tools expose message bodies when expanded", () => {
  initTheme("dark", false);
  const tools = new Map<string, Record<string, unknown>>();
  subagentsExtension({
    on: () => {},
    registerTool: (tool: { name: string }) => tools.set(tool.name, tool),
    registerCommand: () => {},
    registerMessageRenderer: () => {},
    registerEntryRenderer: () => {},
  } as unknown as ExtensionAPI);

  for (const [name, args, message] of [
    [
      "subagent_send",
      { id: "sa-3", message: "Exact guidance body" },
      "Exact guidance body",
    ],
    [
      "subagent_reply",
      { id: "sa-3", request_id: "req-4", message: "Exact reply body" },
      "Exact reply body",
    ],
  ] as const) {
    const tool = tools.get(name) as {
      renderResult: (
        result: unknown,
        options: unknown,
        theme: Theme,
        context: unknown,
      ) => { render(width: number): string[] };
    };
    assert.ok(tool.renderResult, `${name} should register renderResult`);
    const output = rendered(
      tool.renderResult(
        {
          content: [{ type: "text", text: "Accepted." }],
          details: { message: "stale detail must not replace tool args" },
          isError: false,
        },
        { expanded: true, isPartial: false },
        theme,
        { args, isError: false },
      ),
    );
    assert.match(output, new RegExp(message));
  }
});

test("registered spawn tool defaults recursive delegation depth to zero", () => {
  const tools = new Map<string, Record<string, unknown>>();
  subagentsExtension({
    on: () => {},
    registerTool: (tool: { name: string }) => tools.set(tool.name, tool),
    registerCommand: () => {},
    registerMessageRenderer: () => {},
    registerEntryRenderer: () => {},
  } as unknown as ExtensionAPI);

  const spawn = tools.get("subagent_spawn") as {
    parameters?: {
      properties?: {
        allowed_subagents_depth?: { default?: unknown; minimum?: unknown };
      };
    };
  };
  assert.equal(
    spawn.parameters?.properties?.allowed_subagents_depth?.default,
    0,
  );
  assert.equal(
    spawn.parameters?.properties?.allowed_subagents_depth?.minimum,
    0,
  );
});

test("received child updates render from structured communication details", () => {
  initTheme("dark", false);
  const renderers = new Map<string, (...args: any[]) => any>();
  subagentsExtension({
    on: () => {},
    registerTool: () => {},
    registerCommand: () => {},
    registerMessageRenderer: (
      customType: string,
      renderer: (...args: any[]) => any,
    ) => {
      renderers.set(customType, renderer);
    },
    registerEntryRenderer: () => {},
  } as unknown as ExtensionAPI);

  const renderer = renderers.get("subagent-message");
  assert.ok(renderer);
  const output = rendered(
    renderer(
      {
        customType: "subagent-message",
        content:
          "Subagent sa-2 sent an update:\n\nStructured body\n\nUse subagent_send(...)",
        display: true,
        details: {
          id: "sa-2",
          title: "review",
          kind: "update",
          text: "Structured body",
        },
      },
      { expanded: true, outputPad: 1 },
      theme,
    ),
  );
  assert.match(output, /\[card\]/);
  assert.match(output, /subagent sa-2/);
  assert.match(output, /Structured body/);
  assert.doesNotMatch(output, /Use subagent_send/);
});

test("teamlead guidance uses a distinct communication card", () => {
  const output = rendered(
    renderCommunicationCard(
      {
        messageId: "lead-msg-1",
        kind: "guidance",
        text: "Focus on the parser boundary.",
        createdAt: 1,
      },
      theme,
    ),
  );
  assert.match(output, /\[card\]/);
  assert.match(output, /↓ guidance from teamlead/);
  assert.match(output, /Focus on the parser boundary/);
});
