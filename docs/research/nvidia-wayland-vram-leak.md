# NVIDIA / Wayland VRAM accumulation: niri bug or driver behavior?

Research date: 2026-08-06. Context: niri v26.04 + quickshell (noctalia) on RTX 5060,
driver 610.43.02, 5K display, CachyOS. After 2 days uptime: niri 1.26 GB VRAM,
quickshell 1.12 GB. All claims below traced to primary sources (issue trackers,
NVIDIA developer forum, driver profile files on this machine).

## Verdict

**Both theories are true, and both are multi-source corroborated.** This is not
"one person's unreproduced issue":

1. **niri/smithay had real, maintainer-confirmed VRAM leaks** — the headline one
   (dead-surface dmabuf hooks keeping GPU buffers alive after window close) was
   diagnosed and fixed by smithay maintainer cmeissl in niri PR #3404 (merged
   2026-02-10, **shipped in v26.04** — the version running here). Two further
   leak classes are **not yet in any release**: the monitors-off redraw-loop leak
   (PR #3910, open, reproduced on Intel/AMD/NVIDIA) and five smithay GPU-memory
   leaks fixed upstream in Smithay/smithay#2080 (merged 2026-07-16, after
   v26.04 was cut).
2. **NVIDIA's proprietary driver has a separately acknowledged behavior + at
   least one open leak.** An NVIDIA employee (cubanismo) confirmed the
   "compositors hold ~10% of VRAM in a free-buffer pool" behavior as "well
   understood", shipped the `GLVidHeapReuseRatio` / "No VidMem Reuse"
   application-profile workaround in driver 565, and said the underlying
   heuristic fix was still pending. As of driver 610.43.02 (verified locally)
   the built-in profile list covers KWin/mutter/wlroots/Hyprland/cosmic-comp
   **but not niri and not quickshell (`qs`)**. Separately, an unfixed driver
   leak (VRAM never reclaimed for sampled cross-process dmabuf imports) is
   reproduced by a standalone C program with no compositor code, on 595.71.05
   and 610.43.03.

The original claim chain was half-wrong, though: **niri #4071 is a system-RAM
leak on an Intel iGPU**, not an NVIDIA VRAM leak — citing it for this problem
was a category error. The real evidence lives in #1869/#3404, #3295/#3910,
Smithay #1562/#2080, and the NVIDIA egl-wayland/forum threads.

For this machine specifically: v26.04 already contains the #3404 fix and
`/etc/nvidia/nvidia-application-profiles-rc.d/limit-vram-usage` already applies
"No VidMem Reuse" to `niri` — so the remaining 1.26 GB growth most plausibly
comes from (a) the monitors-off leak (#3910 fix unreleased; 2 days uptime means
many display-sleep cycles), (b) the smithay #2080 leaks (unreleased), and (c)
the driver's cross-process dmabuf leak (unfixed). quickshell's 1.12 GB is
**not covered by any profile** (`qs` missing from both the built-in and the
local custom profile) and has no acknowledged upstream VRAM leak — driver
buffer pooling on a 5K framebuffer is the leading explanation there.

---

## Claim 1: niri / smithay VRAM leak — CONFIRMED (multiple leaks, partially fixed)

### #4071 — the issue that started this — is NOT NVIDIA VRAM

- https://github.com/niri-wm/niri/issues/4071 — "Memory leak with very high
  memory usage", opened by neon-mmd, 2026-05-18. **System RAM** growth on an
  **Intel CometLake-U iGPU**. Closed, labeled `kind:leak`. No maintainer
  confirmation of an NVIDIA VRAM connection. The user's skepticism about this
  citation was justified.
- https://github.com/niri-wm/niri/issues/4072 — "memory leak on AMD GPU",
  closed. Also not NVIDIA.

### The real, confirmed leak: dead-surface dmabuf hooks (FIXED in v26.04)

- Issue: https://github.com/niri-wm/niri/issues/1869 — "Video memory not
  released after closing certain apps", Nthomasee, 2025-06-21. GTX 1660 Super,
  driver 575.64, niri 25.05.1. "Consistent and repeatable", video evidence.
- Discussion: https://github.com/niri-wm/niri/discussions/3146 — nickjj,
  2025-12-30, GTX 750 Ti / 580.119.02. Independent confirmations in-thread:
  jadegong (RTX 4060 Ti, 880 MB niri after 3–4 days), thegabriele97 (~6 MB per
  app open/close on cosmic-comp), nickjj also reproduced the slow climb **on an
  AMD system** — i.e. cross-vendor, so not purely driver.
- Upstream: https://github.com/Smithay/smithay/issues/1562 — "Closing windows
  causes VRAM memory leak", GallowsDove, 2024-10-15. Reproduced on **NVIDIA RTX
  3070 and AMD RX 9070 XT**; affects smithay compositors (niri, COSMIC) but not
  wlroots ones (river, Hyprland, sway). Assigned to smithay maintainer cmeissl.
- Fix: https://github.com/niri-wm/niri/pull/3404 — "Fix dead surface hook",
  authored by **cmeissl**, merged **2026-02-10** by YaLTeR, who verified "the
  dmabuf count seems to be stable now". Mechanism: niri registered dmabuf
  pre-commit hooks on already-destroyed surfaces; the strong surface reference
  kept the GPU buffer alive forever. **Released in v26.04 (2026-04-25)** —
  release notes: "@cmeissl fixed a VRAM leak that occurred on some systems
  after closing certain apps."

Verdict: real, multi-user (4+ independent reporters), cross-vendor,
maintainer-confirmed and fixed. Present in ≤25.11, absent in 26.04.

### Still-open leak: monitors powered off (NOT in any release)

- https://github.com/niri-wm/niri/issues/3295 — "Video memory/GTT climbs when
  screens powered off" (open). Related: #1457 (displays enabled/disabled
  repeatedly, open), #2725 (power-save reconnect loop → memory pressure crash).
- Fix PR: https://github.com/niri-wm/niri/pull/3910 — "Fix VRAM leak when
  monitors are off", phuongdpham, opened 2026-04-26, **still open** (YaLTeR:
  needs careful review). Root cause: with monitors off, frame callbacks and
  animation timers kept inviting clients to commit buffers that were never
  presented. Independently reproduced and fix-verified by **sys-rq (Intel
  i915/T490** — +2 GiB shared per 15 min with monitors off**)**, **as3ii (AMD
  iGPU)**, **profanum429 (RX 9070 XT)**. Cross-vendor again.
- Highly relevant here: 2 days uptime with display power-off cycles is exactly
  this leak's trigger, and **v26.04 does not contain the fix**.

### Extra smithay GPU leaks fixed upstream (NOT in any niri release)

- https://github.com/Smithay/smithay/pull/2080 — "fix: GPU-memory leaks in the
  allocator, GLES renderer, and multi-GPU paths", minyek, merged **2026-07-16**.
  Five fixes found chasing steady VRAM climb in multi-output cosmic-comp on
  NVIDIA; headline: thread-affine UserData cache leaking exported dmabufs.
  Explicitly notes one **residual leak that is NVIDIA's**: "VRAM not reclaimed
  for sampled, cross-process dmabuf imports … reproduces with a standalone
  program containing no smithay code, so it is an NVIDIA driver issue."
- Related merged smithay work: #1929 (WeakWindow to prevent VRAM leaks from
  stale handles), #1925 (buffer reference released after image-copy capture).

### Unrelated but noteworthy: #4113 was a niri regression, now fixed

- https://github.com/niri-wm/niri/issues/4113 — post-26.04 regression (commit
  9bd6c2c, 10-bit color-format selection in multi-GPU paths) made niri balloon
  to fill all VRAM with a blank external display. Diagnosed by my4ng, fixed
  2026-07-08. Only affects post-26.04 git builds with iGPU+dGPU setups — not
  the stable 26.04 running here.

## Claim 2: NVIDIA driver free-buffer-pool behavior — CONFIRMED BY NVIDIA

### The vendor acknowledgment (strongest single piece of evidence)

- https://github.com/NVIDIA/egl-wayland/issues/126 — opened by shelterx,
  2024-08-11 (Xwayland/compositor VRAM growth on resize). **cubanismo (James
  Jones, NVIDIA)**, 2024-09-27: compositor VRAM consumption "is well
  understood. We do not need additional information or reports…". 2024-12-05,
  after driver 565 shipped the new profile key: "the suggested workaround has
  been incorporated into the application profiles shipped with the driver…
  However, **work continues on fixing the underlying driver logic** to avoid
  the need for application-specific overrides."
- Driver 565 release note (via https://www.nvidia.com/en-us/drivers/details/237587/,
  quoted in-thread): "Added a new application profile key,
  'GLVidHeapReuseRatio', to control the amount of memory OpenGL may hold for
  later reuse, as well as some application profiles for several Wayland
  compositors…"

### The forum thread

- https://forums.developer.nvidia.com/t/multiple-wayland-compositors-not-freeing-vram-after-resizing-windows/307939
  — kelvie, 2024-09-26. Window resizing grows compositor VRAM until ~10% of
  total VRAM (2.4 GB on a 24 GB 4090), never freed. Affects kwin_wayland, sway,
  weston, gnome-shell. **Four independent confirmers** in-thread (kelvie,
  shelter, thesword53, maxim.egorushkin) across drivers 550.78–560.35. No
  NVIDIA staff reply in this thread — the staff engagement happened in
  egl-wayland#126 above.

### What the workaround actually does, and its limits

- `GLVidHeapReuseRatio` caps the per-process pool of freed video memory OpenGL
  keeps for reuse (driver key docs: value 10 = 1% of VRAM; profile "No VidMem
  Reuse" sets it to 0). An NVIDIA-side suggestion originally used 1; the
  shipped profile uses 0 (difference negligible per key semantics).
- **Verified locally on this machine** (driver 610.43.02,
  `/usr/share/nvidia/nvidia-application-profiles-610.43.02-rc`): built-in "No
  VidMem Reuse" rules cover plasmashell, cosmic-comp, Hyprland, Xwayland,
  libkwin, libmutter, libwlroots, libweston — **`niri` and `qs` are absent**.
  PandorasFox (egl-wayland#126, 2025-07-14): "notably, all smithay-based
  compositors are absent from the list. the underlying heuristic needs to be
  fixed…"
- niri documents the manual profile: https://github.com/niri-wm/niri/wiki/Nvidia
  (origin traced in https://github.com/niri-wm/niri/issues/1962, PandorasFox,
  2025-07-05: 2.5 GB → 168 MB; workaround sourced from egl-wayland#126).
- Limits: nickjj (egl-wayland#126, 2025-12-31): "setting GLVidHeapReuseRatio
  to 0 didn't affect the slow climb issue but protected against a huge initial
  amount" — i.e. the profile addresses the pool behavior, not the (since-fixed)
  smithay leak, and not the dmabuf-import leak below.
- The profile is not a panacea: https://github.com/niri-wm/niri/issues/2208
  (emilyhorsman, 2025-08-09) hit 12 GB niri VRAM overnight **with the profile
  already applied** — monitor-off scenario, i.e. the Claim 1 monitors-off leak.

### The open driver leak (separate from the pool behavior)

- https://forums.developer.nvidia.com/t/bug-report-vram-not-reclaimed-for-sampled-cross-process-dma-buf-imports/374816
  — andy.ks.wright, 2026-06-28. Minimal standalone C reproducers: importing a
  cross-process dmabuf as EGLImage and **sampling it in a draw** leaks GPU
  memory that `eglDestroyImageKHR`/`glDeleteTextures` never reclaim (~2.2 GB
  plateau, freed only on process exit). Affects **595.71.05 and 610.43.03**.
  No NVIDIA reply yet; single reporter, but with a compositor-free reproducer
  and cross-checked against cosmic-comp (referenced from Smithay PR #2080).
  Sampling cross-process dmabufs is precisely what a compositor does with every
  client buffer.

## Claim 3: other compositors show the same accumulation — CONFIRMED

- KWin, sway, weston, gnome-shell: forum t/307939 (above, 4 reporters).
- Hyprland: https://github.com/hyprwm/Hyprland/discussions/10517 — Atemo-C,
  2025-05-23; 900 MB–1.8 GB/day growth. Maintainer **vaxerski**: "if it's not
  dropping when something requests more VRAM, it's a leak. Question is whether
  it's our fault or nvidia's" — thread conclusion: NVIDIA driver; profile
  workaround confirmed (AmaelG: 4 GB → 250 MB). NVIDIA later added Hyprland to
  the built-in profile list.
- COSMIC (smithay, like niri): thegabriele97 in niri discussion #3146; the
  Smithay #2080 investigation itself was on cosmic-comp/NVIDIA.
- Xwayland: https://github.com/NVIDIA/egl-wayland/issues/126 (resizing X11 apps
  → Xwayland VRAM climbs to the 10% cap); NVIDIA added Xwayland to the profile.
- Firefox under niri: https://github.com/niri-wm/niri/issues/4372 —
  kianblakley, 2026-07-28, **RTX 5060 Ti, niri 26.04** (same era as this
  machine): ~70 MB VRAM retained per closed Firefox window. Maintainers labeled
  it `not niri:hardware` + `nvidia` — i.e. triaged as driver-side, post-fix.

Conclusion: the accumulation pattern is compositor-independent on the
proprietary driver; wlroots/KWin/mutter users just stopped noticing after
NVIDIA shipped default profiles for their binaries.

## Claim 4: quickshell / QtQuick holding VRAM — NO ACKNOWLEDGED LEAK FOUND

- quickshell tracker (github.com/quickshell-mirror/quickshell) has **no open
  VRAM-leak issue**: #102 "crashes when out of VRAM" (closed — victim, not
  cause), #678 "Memory leak + xdg_popup crash after long uptime" (open,
  **system RAM**), #679 PRIME-offload crash. Nothing acknowledging multi-hundred-MB
  VRAM retention.
- No Qt scenegraph VRAM-leak-on-NVIDIA-Wayland bug surfaced in searches.
- The parsimonious explanation for qs at 1.12 GB: it is a GL/scenegraph client
  compositing large surfaces at 5K, and **its process name is in no "No VidMem
  Reuse" rule** — neither the driver's built-in set nor the local
  `/etc/nvidia/nvidia-application-profiles-rc.d/limit-vram-usage` file (which
  covers niri, browsers, terminals, Electron apps — but not `qs`). The same
  pool behavior NVIDIA confirmed for compositors applies to any long-lived GL
  process; cubanismo's profile list includes `plasmashell` — a desktop shell
  exactly analogous to quickshell. Single-source inference, clearly flagged as
  such — but the driver-profile gap is verified fact on this machine.

## Claim 5: NVIDIA release notes on Wayland memory management

- **565 (2024-12)**: added `GLVidHeapReuseRatio` key + built-in "No VidMem
  Reuse" profiles for several compositors (driver page 237587, confirmed by
  cubanismo in egl-wayland#126). This is the only explicit vendor fix shipped
  for the pool behavior.
- **595 (2026-03)**: improved fallback to system memory when VRAM is low, to
  prevent Wayland desktop freezes (r595 release feedback /
  ubuntuhandbook.org/index.php/2026/03/nvidia-595-58-03-released-with-better-wayland-linux-gaming-support/).
  Mitigates exhaustion consequences, not the retention itself. A CachyOS forum
  thread reports a **VRAM leak regression in nvidia-open 595.58**
  (discuss.cachyos.org t/28717, 403-blocked during this research — unverified).
- **No release note through 610 announces the promised "underlying driver
  logic" fix** for the reuse heuristic, and the cross-process dmabuf leak is
  reproduced on 610.43.03 (forum t/374816). The niri wiki's assessment — "it
  is unlikely that the underlying heuristic will see a proper fix" — matches
  the record: cubanismo's Dec 2024 statement remains the last word.

## Actionable implications for this machine (not part of the evidence record)

1. niri 1.26 GB despite fix + profile → the two unreleased fixes are the prime
   suspects: PR #3910 (monitors-off; matches 2-day-uptime pattern) and smithay
   #2080 (in smithay master since 2026-07-16). Testing niri-git with a bumped
   smithay would discriminate. The unfixed driver dmabuf-import leak
   (t/374816) is the floor below which neither will help.
2. quickshell: add `{ "feature": "procname", "matches": "qs" }` to the local
   `limit-vram-usage` profile (confirmed absent) and compare boot-time and
   2-day VRAM. This is the single cheapest experiment with the highest
   information yield for the qs half of the problem.
