---
name: verify
summary: Verify niri-ctx session restoration through the installed CLI
---

# Verify niri-ctx

1. Build the installed target: `cargo build --release --manifest-path rust/niri-ctx/Cargo.toml` (`~/.local/bin/niri-ctx` links to it).
2. Before driving a context, capture its Herdr workspace/tab IDs, labels, ordering, and focus through `HERDR_SOCKET_PATH=~/.config/herdr/sessions/<Ctx>-work/herdr.sock herdr workspace list` plus `herdr tab list --workspace <id>`.
3. Run `~/.local/bin/niri-ctx open <Ctx>` and assert the exact snapshot is unchanged. Repeat once or concurrently to probe idempotence.
4. For a stopped persisted session, capture `session.json`, run an explicit role such as `open <Ctx> agents`, wait for the socket, and verify restoration followed by focus on only the requested existing tab. Never stop/delete a user session to manufacture this state.
5. Verify tmux fallback with an isolated server by placing a wrapper `tmux` in a temporary `PATH` that executes the real binary with `-L niri-ctx-verify`; inspect windows with the real binary and kill only that isolated server afterward.

Do not automatically clean duplicate Herdr workspaces/tabs. The live convergence harness moves real Niri windows and focus; run it only when that disruption is acceptable.
