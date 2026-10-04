import assert from "node:assert/strict";
import test from "node:test";
import type {
  ExtensionAPI,
  ExtensionContext,
  ToolDefinition,
} from "@earendil-works/pi-coding-agent";
import { Check } from "typebox/value";
import subagentsExtension from "./index.ts";

const codingModel = "openai-codex/gpt-5.6-sol";
const generalModel = "openai-codex/gpt-6-astra";

function registerExtension() {
  const tools = new Map<string, ToolDefinition>();
  let shutdown = async () => {};
  // SAFETY: This inert host implements every API used during registration and
  // failed spawns. No session_start hooks or interactive UI are invoked.
  subagentsExtension({
    on: (event: string, handler: () => Promise<void>) => {
      if (event === "session_shutdown") shutdown = handler;
    },
    registerTool: (tool: ToolDefinition) => tools.set(tool.name, tool),
    registerCommand: () => {},
    registerMessageRenderer: () => {},
    registerEntryRenderer: () => {},
    getThinkingLevel: () => "high",
  } as unknown as ExtensionAPI);
  const spawn = tools.get("subagent_spawn");
  assert.ok(spawn);
  return { spawn, close: () => shutdown() };
}

test("spawn schema permits only Sol and Astra and preserves legacy Pi arguments", () => {
  const { spawn } = registerExtension();
  assert.ok(spawn.prepareArguments);
  for (const model of [undefined, codingModel, generalModel]) {
    const args = { prompt: "task", title: "child", harness: "pi", model };
    const prepared = spawn.prepareArguments(args);
    assert.deepEqual(prepared, { prompt: "task", name: "child", model });
    assert.equal(Check(spawn.parameters, prepared), true);
  }
  for (const model of [
    "openai-codex/gpt-5.5",
    "anthropic/claude-opus",
    "",
    42,
    null,
  ]) {
    const prepared = spawn.prepareArguments({
      prompt: "task",
      name: "child",
      model,
    });
    assert.equal(Check(spawn.parameters, prepared), false);
  }
  assert.throws(
    () =>
      spawn.prepareArguments?.({
        prompt: "task",
        name: "child",
        harness: "codex",
      }),
    /Only the pi harness is supported/,
  );
});

for (const model of [undefined, codingModel, generalModel]) {
  test(`spawn forwards ${model ?? "the Sol default"} to the Pi backend`, async (t) => {
    const { spawn, close } = registerExtension();
    t.after(close);
    const lookups: string[] = [];
    // SAFETY: These are the context methods used before model resolution.
    // The empty registry deliberately fails before creating sessions or using
    // credentials, so this test exercises the real tool, manager, and backend
    // without starting an external model request.
    const ctx = {
      cwd: process.cwd(),
      sessionManager: { getEntries: () => [] },
      isProjectTrusted: () => false,
      modelRegistry: {
        find: (provider: string, id: string) => {
          lookups.push(`${provider}/${id}`);
          return undefined;
        },
      },
    } as unknown as ExtensionContext;
    await assert.rejects(
      spawn.execute(
        "spawn-test",
        { prompt: "task", name: "child", model },
        undefined,
        undefined,
        ctx,
      ),
      { message: `Unknown model "${model ?? codingModel}".` },
    );
    assert.deepEqual(lookups, [model ?? codingModel]);
  });
}
