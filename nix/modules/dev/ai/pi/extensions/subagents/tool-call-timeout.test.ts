import assert from "node:assert/strict";
import test from "node:test";
import type { ToolDefinition } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { createToolCallTimeoutGuard } from "./src/tool-call-timeout.ts";

function definition(name: string): ToolDefinition {
  return {
    name,
    label: name,
    description: name,
    parameters: Type.Object({}),
    async execute() {
      return { content: [{ type: "text", text: "ok" }], details: {} };
    },
  };
}

test("teamlead_ask can own its longer timeout while other child tools remain guarded", () => {
  const ask = definition("teamlead_ask");
  const bash = definition("bash");
  const definitions = new Map([
    [ask.name, ask],
    [bash.name, bash],
  ]);
  const registry = {
    getAllTools: () => [...definitions.keys()].map((name) => ({ name })),
    getToolDefinition: (name: string) => definitions.get(name),
  };
  const guard = createToolCallTimeoutGuard(10, {
    exclude: new Set(["teamlead_ask"]),
  });
  const askExecute = ask.execute;
  const bashExecute = bash.execute;

  guard.apply(registry);

  assert.equal(ask.execute, askExecute);
  assert.notEqual(bash.execute, bashExecute);
});
