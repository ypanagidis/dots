import { keyHint, type Theme } from "@earendil-works/pi-coding-agent";
import {
  Box,
  Container,
  Spacer,
  Text,
  type Component,
} from "@earendil-works/pi-tui";
import type { SubagentCommunication } from "../domain.ts";
import { sanitizeText } from "./transcript.ts";

function communicationLabel(message: SubagentCommunication): string {
  switch (message.kind) {
    case "guidance":
      return "guidance from teamlead";
    case "reply":
      return `teamlead reply${message.requestId ? ` · ${message.requestId}` : ""}`;
    case "question":
      return `question to teamlead${message.requestId ? ` · ${message.requestId}` : ""}`;
    case "resolution":
      return `teamlead question closed${message.requestId ? ` · ${message.requestId}` : ""}`;
    case "update":
      return "update to teamlead";
  }
}

/** A distinct transcript card for every message crossing the teamlead boundary. */
export function renderCommunicationCard(
  message: SubagentCommunication,
  theme: Theme,
): Component {
  const incoming = message.kind === "guidance" || message.kind === "reply";
  const color =
    message.kind === "question"
      ? "warning"
      : message.kind === "resolution"
        ? "muted"
        : incoming
          ? "success"
          : "accent";
  const arrow = incoming ? "↓" : message.kind === "resolution" ? "×" : "↑";
  const box = new Box(
    1,
    0,
    (text) => theme.bg("customMessageBg", text),
  );
  box.addChild(
    new Text(
      theme.fg(color, `${arrow} ${theme.bold(communicationLabel(message))}`),
      0,
      0,
    ),
  );
  box.addChild(
    new Text(
      theme.fg("customMessageText", sanitizeText(message.text)),
      0,
      0,
    ),
  );
  return box;
}

export function renderCommunicationToolCall(
  options: {
    readonly id?: string;
    readonly requestId?: string;
    readonly kind: "guidance" | "reply";
  },
  theme: Theme,
): Component {
  const suffix =
    options.kind === "reply" && options.requestId
      ? ` · reply · ${options.requestId}`
      : ` · ${options.kind}`;
  return new Text(
    theme.fg("accent", "→ ") +
      theme.fg(
        "toolTitle",
        theme.bold(`subagent ${options.id ?? "?"}`),
      ) +
      theme.fg("muted", suffix),
    0,
    0,
  );
}

export function renderCommunicationToolResult(
  options: {
    readonly summary: string;
    readonly message?: string;
    readonly expanded: boolean;
    readonly isPartial: boolean;
    readonly isError: boolean;
  },
  theme: Theme,
): Component {
  const summary = sanitizeText(options.summary).trim() || "(no result)";
  if (options.isPartial) {
    return new Text(theme.fg("warning", summary), 0, 0);
  }

  const status = new Text(
    theme.fg(options.isError ? "error" : "success", summary) +
      (!options.expanded && options.message
        ? theme.fg("dim", ` (${keyHint("app.tools.expand", "to show message")})`)
        : ""),
    0,
    0,
  );
  if (!options.expanded || !options.message) return status;

  const container = new Container();
  container.addChild(status);
  container.addChild(new Spacer(1));
  container.addChild(new Text(theme.fg("muted", theme.bold("Message")), 0, 0));
  container.addChild(
    new Text(
      theme.fg("toolOutput", sanitizeText(options.message)),
      0,
      0,
    ),
  );
  return container;
}
