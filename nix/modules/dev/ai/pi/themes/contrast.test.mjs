import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const theme = JSON.parse(
  readFileSync(new URL("./github-dark-default.json", import.meta.url), "utf8"),
);

function color(token) {
  let value = theme.colors[token];
  const seen = new Set();
  while (Object.hasOwn(theme.vars, value)) {
    assert.ok(!seen.has(value), `Cyclic color variable: ${value}`);
    seen.add(value);
    value = theme.vars[value];
  }
  assert.match(
    value,
    /^#[0-9a-f]{6}$/i,
    `${token} must resolve to explicit RGB`,
  );
  return value;
}

function luminance(hex) {
  const rgb = [1, 3, 5].map(
    (offset) => parseInt(hex.slice(offset, offset + 2), 16) / 255,
  );
  const linear = rgb.map((v) =>
    v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4,
  );
  return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722;
}

function contrast(a, b) {
  const [low, high] = [luminance(a), luminance(b)].sort((x, y) => x - y);
  return (high + 0.05) / (low + 0.05);
}

// A conservative light patch of the user's dark wallpaper, not a guarantee
// for arbitrary wallpapers. Text must remain readable without an opaque panel.
const wallpaper = "#404044";
const decoration = new Set([
  "border",
  "borderAccent",
  "borderMuted",
  "mdQuoteBorder",
  "mdHr",
]);
for (const token of Object.keys(theme.colors)) {
  if (token.endsWith("Bg") || token === "scrollbarThumb") continue;
  test(`${token} stays visible over the transparent terminal`, () => {
    const minimum = decoration.has(token) ? 3 : 4.5;
    const ratio = contrast(color(token), wallpaper);
    assert.ok(
      ratio >= minimum,
      `${token}: ${ratio.toFixed(2)}:1, expected ${minimum}:1`,
    );
  });
}

for (const [foreground, background] of [
  ["userMessageText", "userMessageBg"],
  ["customMessageText", "customMessageBg"],
  ["toolOutput", "toolPendingBg"],
  ["toolOutput", "toolSuccessBg"],
  ["toolOutput", "toolErrorBg"],
  ["text", "selectedBg"],
  ["searchMatchText", "searchMatchBg"],
]) {
  test(`${foreground} is readable on ${background}`, () => {
    assert.ok(contrast(color(foreground), color(background)) >= 7);
  });
}

test("user messages have a separate panel from tool and extension messages", () => {
  for (const token of ["toolPendingBg", "toolSuccessBg", "customMessageBg"]) {
    assert.ok(contrast(color("userMessageBg"), color(token)) >= 1.5);
  }
});
