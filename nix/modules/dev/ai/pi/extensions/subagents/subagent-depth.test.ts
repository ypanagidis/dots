import assert from "node:assert/strict";
import test from "node:test";
import type { SessionEntry } from "@earendil-works/pi-coding-agent";
import {
  SUBAGENT_DEPTH_POLICY_ENTRY_TYPE,
  createSubagentDepthPolicy,
  parseSubagentDepthPolicy,
  resolveSubagentSessionDepth,
  subagentDepthLimitFromEntries,
  validateRequestedSubagentDepth,
} from "./src/subagent-depth.ts";

function marker(data: unknown): SessionEntry {
  return {
    type: "custom",
    customType: SUBAGENT_DEPTH_POLICY_ENTRY_TYPE,
    data,
    id: "depth-marker",
    parentId: null,
    timestamp: "2026-01-01T00:00:00.000Z",
  };
}

test("normal coordinator sessions have no inherited depth cap", () => {
  assert.equal(subagentDepthLimitFromEntries([]), undefined);
  assert.equal(validateRequestedSubagentDepth(100, undefined), 100);
});

test("a child may delegate only one fewer descendant generation", () => {
  const policy = createSubagentDepthPolicy(3);
  assert.deepEqual(parseSubagentDepthPolicy(policy), policy);
  assert.equal(subagentDepthLimitFromEntries([marker(policy)]), 3);
  assert.equal(validateRequestedSubagentDepth(0, 3), 0);
  assert.equal(validateRequestedSubagentDepth(2, 3), 2);
  assert.throws(
    () => validateRequestedSubagentDepth(3, 3),
    /at most 2/,
  );
});

test("recovery requires the parent checkpoint and child policy to agree", () => {
  assert.equal(
    resolveSubagentSessionDepth({
      requestedDepth: 2,
      persistedDepth: 2,
      resuming: true,
    }),
    2,
  );
  assert.equal(
    resolveSubagentSessionDepth({
      requestedDepth: 0,
      persistedDepth: undefined,
      resuming: true,
    }),
    0,
  );
  assert.throws(
    () =>
      resolveSubagentSessionDepth({
        requestedDepth: 2,
        persistedDepth: undefined,
        resuming: true,
      }),
    /policy mismatch.*no depth policy/i,
  );
  assert.throws(
    () =>
      resolveSubagentSessionDepth({
        requestedDepth: 2,
        persistedDepth: 3,
        resuming: true,
      }),
    /policy mismatch.*allows 2.*records 3/i,
  );
});

test("conflicting session-wide policies fail closed", () => {
  assert.equal(
    subagentDepthLimitFromEntries([
      marker(createSubagentDepthPolicy(3)),
      { ...marker(createSubagentDepthPolicy(2)), id: "conflict" },
    ]),
    0,
  );
});

test("zero and malformed child policies fail closed", () => {
  assert.equal(
    subagentDepthLimitFromEntries([marker(createSubagentDepthPolicy(0))]),
    0,
  );
  assert.throws(
    () => validateRequestedSubagentDepth(0, 0),
    /not allowed to spawn/,
  );
  assert.equal(
    subagentDepthLimitFromEntries([
      marker({ version: 1, allowedSubagentsDepth: -1 }),
    ]),
    0,
  );
});

test("depth values must be non-negative safe integers", () => {
  for (const value of [-1, 1.5, Number.MAX_SAFE_INTEGER + 1, Number.NaN]) {
    assert.equal(parseSubagentDepthPolicy({ version: 1, allowedSubagentsDepth: value }), undefined);
    assert.throws(
      () => validateRequestedSubagentDepth(value, undefined),
      /non-negative safe integer/,
    );
  }
});
