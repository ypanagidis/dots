import assert from "node:assert/strict";
import test from "node:test";
import {
  SUBAGENT_CHILD_LIFECYCLE_GUIDANCE,
  SUBAGENT_REPLY_PARAMETER_DESCRIPTIONS,
  SUBAGENT_REPLY_TOOL_DESCRIPTION,
  SUBAGENT_SEND_PARAMETER_DESCRIPTIONS,
  SUBAGENT_SEND_TOOL_DESCRIPTION,
  SUBAGENT_SPAWN_PROMPT_GUIDELINES,
  SUBAGENT_SPAWN_TOOL_DESCRIPTION,
  SUBAGENT_WAIT_TOOL_DESCRIPTION,
  TEAMLEAD_ASK_PARAMETER_DESCRIPTIONS,
  TEAMLEAD_ASK_TOOL_DESCRIPTION,
  TEAMLEAD_SEND_PARAMETER_DESCRIPTIONS,
  TEAMLEAD_SEND_TOOL_DESCRIPTION,
  buildSubagentSpawnResult,
} from "./src/prompt.ts";

const joined = (...parts: ReadonlyArray<string | ReadonlyArray<string>>) =>
  parts.flat().join(" ");

const assertMentions = (text: string, patterns: ReadonlyArray<RegExp>) => {
  for (const pattern of patterns) {
    assert.match(text, pattern);
  }
};

test("wait guidance is nonblocking, non-polling, and preserves individual callbacks", () => {
  const spawnResult = buildSubagentSpawnResult({
    id: "sa-7",
    title: "inspect prompts",
    harness: "pi",
    modelLabel: "openai-codex/gpt-5.6-sol",
    cwd: "/repo",
    allowedSubagentsDepth: 0,
  });
  const guidance = joined(
    SUBAGENT_WAIT_TOOL_DESCRIPTION,
    SUBAGENT_SPAWN_TOOL_DESCRIPTION,
    SUBAGENT_SPAWN_PROMPT_GUIDELINES,
    spawnResult,
  );

  assertMentions(guidance, [
    /(?:return|respond).{0,30}immediate|nonblocking|asynchronous/i,
    /(?:each|every).{0,40}(?:separate|individual).{0,30}(?:final|callback|message)|(?:final|callback|message).{0,30}(?:separate|individual)/i,
    /(?:do not|don['’]t|never).{0,20}poll/i,
    /continue.{0,30}(?:useful|independent).{0,20}work/i,
    /concise.{0,30}(?:interim|delegation).{0,30}(?:update|message)/i,
    /end (?:this|the) turn/i,
  ]);

  assert.doesNotMatch(guidance, /block until all|wait until all/i);
  assert.doesNotMatch(guidance, /wait repeatedly/i);
});

test("spawn guidance documents bounded recursive delegation", () => {
  const guidance = joined(
    SUBAGENT_SPAWN_TOOL_DESCRIPTION,
    SUBAGENT_SPAWN_PROMPT_GUIDELINES,
  );

  assertMentions(guidance, [
    /allowed_subagents_depth/i,
    /default.{0,10}0|0.{0,20}default/i,
    /1.{0,30}(?:leaf|generation)/i,
    /(?:decrease|less)/i,
  ]);
});

test("spawn guidance requires the child's delivered final answer to stand alone", () => {
  const guidance = joined(
    SUBAGENT_SPAWN_TOOL_DESCRIPTION,
    SUBAGENT_SPAWN_PROMPT_GUIDELINES,
  );

  assertMentions(guidance, [
    /final (?:answer|response|message|output)/i,
    /self-contained/i,
    /findings/i,
    /changed files/i,
    /verification/i,
    /blockers/i,
    /(?:teamlead|parent).{0,30}(?:receive|deliver)|(?:receive|deliver).{0,30}(?:teamlead|parent)/i,
  ]);
});

test("parent communication prompts describe asynchronous send and correlated reply", () => {
  assertMentions(SUBAGENT_SEND_TOOL_DESCRIPTION, [
    /running/i,
    /(?:next safe|safe .{0,15}boundar|queue)/i,
    /settled/i,
    /(?:new|another) (?:turn|run)/i,
    /(?:accept|enqueue|queue).{0,30}(?:not|rather than).{0,20}(?:process|complete|finish)|returns?.{0,20}(?:before|without waiting)/i,
  ]);
  assertMentions(SUBAGENT_SEND_PARAMETER_DESCRIPTIONS.id, [/subagent/i]);
  assertMentions(SUBAGENT_SEND_PARAMETER_DESCRIPTIONS.message, [/message/i]);

  assertMentions(SUBAGENT_REPLY_TOOL_DESCRIPTION, [
    /(?:exactly one|one outstanding|specific outstanding)/i,
    /(?:question|teamlead_ask)/i,
    /request.{0,5}id/i,
  ]);
  assertMentions(SUBAGENT_REPLY_PARAMETER_DESCRIPTIONS.id, [/subagent/i]);
  assertMentions(SUBAGENT_REPLY_PARAMETER_DESCRIPTIONS.requestId, [/request.{0,5}id/i]);
  assertMentions(SUBAGENT_REPLY_PARAMETER_DESCRIPTIONS.message, [/repl|message/i]);
});

test("child lifecycle keeps callback-enabled background work in the managed run", () => {
  assertMentions(SUBAGENT_CHILD_LIFECYCLE_GUIDANCE, [
    /managed background subagent/i,
    /background-task/i,
    /callback/i,
    /do not claim.{0,40}complete/i,
    /teamlead_send/i,
    /after all.{0,40}background work.{0,30}(?:finish|complete)/i,
  ]);
});

test("child communication prompts distinguish updates from blocking questions", () => {
  assertMentions(TEAMLEAD_SEND_TOOL_DESCRIPTION, [
    /(?:material|important|significant).{0,20}(?:update|message)|update.{0,20}(?:material|important|significant)/i,
    /asynchronous|immediate/i,
    /continue/i,
    /sparingly|not.{0,20}(?:routine|narration)/i,
  ]);
  assertMentions(TEAMLEAD_SEND_PARAMETER_DESCRIPTIONS.message, [/message|update/i]);

  assertMentions(TEAMLEAD_ASK_TOOL_DESCRIPTION, [
    /question/i,
    /(?:wait|pending|reply)/i,
    /teamlead|parent/i,
  ]);
  assertMentions(TEAMLEAD_ASK_PARAMETER_DESCRIPTIONS.question, [/question/i]);
});
