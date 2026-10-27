---
name: effect-layers
description: Effect v4 layers. Use when defining an Effect service, wiring a composition root, setting up an entrypoint or ManagedRuntime, testing with layers, or auditing a repo's layer graph.
---

# Effect layers

A service starts as a type, an interface plus a `Context.Service` tag. Implementations come later as layers. The layer's type `Layer.Layer<ROut, E, RIn>` is the dependency declaration, and the compiler checks it.

This skill targets Effect 4.0.x. Check every API against the project's installed `effect` (`dist/*.d.ts`) before using it. Citations like `Layer.ts:1463` point at upstream effect 4.0.6 source; `ai-docs/...` paths also exist under the installed `node_modules/effect`.

## Vocabulary

- `make`: the effect that builds the service value. Always explicitly typed `Effect.Effect<X["Service"], E, R>`.
- `layerNoDeps`: `Layer.effect(X, make)`; every requirement stays open.
- `layer`: `layerNoDeps` with its owned dependencies provided. Infrastructure stays in `RIn` for the composition root. When nothing is owned, `layer` is the only export.
- **owned dependency**: an application service with one production implementation, which this module picks (a repo, another capability). Provide it in `layer` even when other modules use it too; within one graph they share one instance because they provide the same `layer` const.
- **infrastructure**: an adapter to an external system (SQL client, HTTP client, platform services, a broker). Only the composition root picks it.
- `layerConfig(config: Config.Wrap<Options>)`: adapters only, options read through `Config`.
- `layer<Variant>`: another real implementation, e.g. `layerRemote(url)`.
- `layerMemory`: a faithful in-memory implementation of the interface.
- `layerTest`: the service built over test dependencies, merged in with `Layer.provideMerge` so tests can yield them (`layerNoDeps` over test layers, or a memory `make` over a test ref).
- **composition root**: the one module per process that names concrete infrastructure and exports the annotated app layer.

## Design a new service

Read [`references/services-and-layers.md`](references/services-and-layers.md) first.

1. Make it a service only when it owns I/O, a resource, configuration, time or randomness, or has a second real implementation (another backend, or a memory one tests need). Otherwise keep it a function or a value. Reach for Effect's own services (`Clock`, `Random`, `FileSystem`, `HttpClient`) before writing one.
2. Find the repo's layout. Count `rg -l 'static readonly layer' --type ts .` against `rg --files -g '**/layer.ts' .` and follow the larger. With neither, use the module layout in a multi-package repo and statics in a single-package app. Single-file modules (tag and layers in one file) count toward neither.
   - Module layout: `<capability>/service.ts` holds the interface, tag and errors and imports no implementation. `<capability>/layer.ts` holds `make` and the layers. `memory.ts` and test layers sit beside them.
   - Statics layout: steps 3-5 write the same names as `static readonly` members of the tag class.
3. In `service.ts`, declare the interface, then `class X extends Context.Service<X, Interface>()("<package>/<path>/X") {}`, then its `Schema.TaggedError`s. The id is unique in the app.
4. In `layer.ts`, write `make` with its explicit type. Yield dependencies at the top, write methods with `Effect.fn("X.method")`, acquire resources with `Effect.acquireRelease`, fork long-lived fibers with `Effect.forkScoped`, return `X.of({ ... })`.
5. Export the layers, each annotated `Layer.Layer<X, E, RIn>`.
6. Add `layerMemory` or `layerTest` when a test or another service needs one.

**Complete when:** the typecheck passes, `make` and every exported layer carry explicit types, and the `RIn` of `layer` lists exactly the infrastructure the root must supply.

## Wire a composition root

Read [`references/composition-and-runtime.md`](references/composition-and-runtime.md) first.

1. List the tags each process yields: its program, its handlers and every later stage that consumes the root. That set is the process's `AppServices`.
2. Merge the `layer` of each with `Layer.mergeAll`.
3. Bind each infrastructure layer, and every result of a layer factory, to one `const`.
4. Provide infrastructure with `Layer.provide`. Use `Layer.provideMerge` only for a service the program itself yields.
5. Annotate the result `Layer.Layer<AppServices, AppError>`, where `AppError` is the union of the build errors (e.g. `Config.ConfigError | SqlError.SqlError`). Leaving `RIn` out means `never`, so a missing dependency fails to compile on this line.
6. Add the root's build test from [`references/testing-with-layers.md#proving-a-composition-root-builds`](references/testing-with-layers.md#proving-a-composition-root-builds).

**Complete when:** the root compiles with `RIn` of `never`, no factory is called twice in the graph, and the root's build test passes.

## Set up an entrypoint or runtime

Read [`references/composition-and-runtime.md`](references/composition-and-runtime.md) before writing the entrypoint.

- A long-running app modelled as layers (HTTP server): `Layer.launch(AppLayer).pipe(NodeRuntime.runMain)`.
- A program that finishes, or a main loop written as an effect (`Effect.forever`): `program.pipe(Effect.provide(MainLayer), NodeRuntime.runMain)`. A failure of the loop then fails `runMain` and sets the exit code. Under `Layer.launch` with a `forkScoped` loop, the process keeps running after the loop dies.
- A non-Effect host (framework callbacks, React): one `ManagedRuntime` per process, a shared `memoMap` if there are several, disposed on shutdown.
- A resource keyed by a value (tenant, region): `LayerMap.Service` with `idleTimeToLive`.

**Complete when:** each process builds its app layer exactly once (one `Effect.provide`, `Layer.launch`, or `ManagedRuntime.make` with a dispose path); every other provide in a handler or method is a `LayerMap` `get`; and sending SIGINT to a running `runMain` process runs every finalizer and exits 130.

## Write tests

Read [`references/testing-with-layers.md`](references/testing-with-layers.md) first.

1. Default to `it.effect`. Use `it.live` only outside `layer` blocks, for real time.
2. Build test assemblies from `layerNoDeps` with test dependencies via `Layer.provideMerge`.
3. Give each test that writes state its own instance (a per-test `Effect.provide` or `buildPerTest: true`); share a `layer(...)` block only across tests that read.
4. Give each composition root a build test against test infrastructure.

**Complete when:** every service under test is reached through its tag, every test that writes state builds its own instance, and every composition root has a passing build test.

## Audit an existing repo

Run every check in [`references/audit.md`](references/audit.md) in order. Each check carries the id of its catalogue entry.

**Complete when:** every check has a recorded result (hits with `file:line`, or "clean"), and every hit names its catalogue fix.

## Refresh this skill

On an Effect version bump, re-read the upstream files listed in [`references/sources.md`](references/sources.md) and update the citations and APIs that changed.
