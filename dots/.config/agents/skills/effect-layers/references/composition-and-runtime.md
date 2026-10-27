# Composition and runtime

## provide, provideMerge, merge

| Combinator | Result | Use |
|---|---|---|
| `Layer.provide(self, that)` | `Layer<A, E \| E2, RIn2 \| Exclude<R, ROut2>>` | satisfy `self`'s requirements and hide `that` (Layer.ts:1463) |
| `Layer.provideMerge(self, that)` | like `provide`, output `A \| ROut2` | the consumer also yields `that`'s services (:1582) |
| `Layer.merge` / `Layer.mergeAll` | union of outputs, errors, requirements | independent layers side by side (:1329, :1275) |

`provide` and `provideMerge` build the dependency first. An array of dependencies builds concurrently, as with `mergeAll`.

`provideMerge` fits when the program itself yields the dependency:

- an observability layer whose logger and tracer the program's own fiber must use;
- a test ref or test-control service the test inspects;
- `HttpServer` or an `HttpClient` aimed at the test server in HTTP tests.

Everywhere else `provideMerge` leaks infrastructure. Once `SqlClient` is in the app context, any service can reach for the raw client and nothing in its type says so.

## The composition root

One module per process. It is the only place that names concrete infrastructure, and it exports an annotated layer whose `RIn` is `never`.

```ts
// apps/api/src/app-layer.ts
import { PgClient } from "@effect/sql-pg"
import { Config, Layer } from "effect"
import type { SqlClient, SqlError } from "effect/sql"
import * as BillingLayer from "@acme/billing/billing/layer"
import type { Billing } from "@acme/billing/billing/service"
import * as SignupLayer from "@acme/accounts/signup/layer"
import type { Signup } from "@acme/accounts/signup/service"

export type AppServices = Signup | Billing

export const AppServicesNoInfra: Layer.Layer<AppServices, never, SqlClient.SqlClient> = Layer.mergeAll(
  SignupLayer.layer,
  BillingLayer.layer
)

const SqlLayer = PgClient.layerConfig({ url: Config.Redacted("DATABASE_URL") })

export const AppLayer: Layer.Layer<AppServices, Config.ConfigError | SqlError.SqlError> =
  AppServicesNoInfra.pipe(Layer.provide(SqlLayer))
```

`AppServicesNoInfra` is the root's `layerNoDeps`. The build test provides test infrastructure to it (testing-with-layers.md).

Keep the root flat: named `const`s in dependency order, one `Layer.provide` per infrastructure tier.

## Several processes, one set of services

When an API, a worker and a CLI share services, split the shared module from the per-process roots:

- The shared module exports the services with infrastructure open (`AppServicesNoInfra`) and each infrastructure layer as a `const` (`SqlLayer`).
- Each process root lists the tags that process yields (its program, its handlers, every later stage that consumes the root), merges those services' `layer`s, and provides the shared infrastructure constants once.
- A later stage that needs infrastructure itself (a routes layer, a health check on the SQL client) gets the same constant in the same root: `RoutesLayer.pipe(Layer.provide([AppLayer, SqlLayer]))`. Memoization keys on the object, so both references build one pool. A second `PgClient.layerConfig(...)` call would open a second one.
- Infrastructure that reaches a later stage only because `provideMerge` leaked it is A6. Provide it to that stage explicitly, as above, before removing the `provideMerge`.

## Memoization

A memo map caches built layers keyed by the layer object's reference (`Map<Layer, MemoMapEntry>`, Layer.ts:429-460). Consequences:

- The same `const` referenced from several places in one graph builds once. `Signup.layer` and `Billing.layer` can both provide `UserRepoLayer.layer` and share one instance.
- A factory returns a new object per call. `PgClient.layerConfig(...)` called in two modules opens two pools with two sets of finalizers. Call it once and bind the result.
- `Layer.flatMap`, `tap*`, `orDie` and `catch*` are not memoized. `effect`, `effectContext`, `effectDiscard`, `sync`, `suspend`, `mergeAll`, `provide` and `provideMerge` are.

`Effect.provide` forks the ambient memo map. Nested provides reuse layers an enclosing provide or runtime already built; sibling provides build their own copies (migration/layer-memoization.md). `Effect.provide(layer)` inside a request handler or service method builds the layer per call unless the same layer object was already built by an enclosing provide or runtime. Either way it hides the dependency, so compose first and provide once.

Opt out of sharing only on purpose:

- `Layer.fresh(layer)` builds with a new memo map, so every dependency of that layer is rebuilt too, shared database included (Layer.ts:2207).
- `Effect.provide(layer, { local: true })` builds the whole subtree with a new memo map (internal/layer.ts:15-21).

## Scopes, finalizers and shutdown

- `Layer.effect` runs `make` in the layer's scope. `Effect.acquireRelease` registers the release there; acquisition is uninterruptible by default and `release` receives the `Exit`.
- `Effect.forkScoped` attaches a background fiber to the layer scope (services-and-layers.md#make).
- Release order: `provide(self, that)` builds `that` then `self` in one scope, so `self` is released before `that`. Siblings in `mergeAll` release in parallel. A scope closes uninterruptibly.
- A failure partway through a build closes that layer's forked scope with the failure, releasing what it acquired. Layers that already finished are released when the enclosing provide or launch scope closes.
- Nothing bounds shutdown time. A second SIGINT only interrupts again. Put a timeout on any release effect that can hang.
- A handle no layer scope owns (an unscoped client, a stray timer) keeps the event loop alive. A successful `runMain` does not call `process.exit`, so the process hangs.

## Entrypoints

A long-running app modelled as layers (HTTP server, workers):

```ts
import { NodeRuntime } from "@effect/platform-node"
import { Layer } from "effect"
import { ServerLayer } from "./server.js"

Layer.launch(ServerLayer).pipe(NodeRuntime.runMain)
```

`Layer.launch(self)` is `scoped(build(self) then never)`, so the scope closes only on interrupt or failure (Layer.ts:2255). Background-only work is a `Layer.effectDiscard` that forks with `Effect.forkScoped` (ai-docs 06_running/10_run-main.ts).

A program that finishes: `program.pipe(Effect.provide(AppLayer), NodeRuntime.runMain)`.

A main loop written as an effect (a worker's `Effect.forever` polling loop) uses the same form: `loop.pipe(Effect.provide(MainLayer), NodeRuntime.runMain)`. `Layer.launch(Layer.effectDiscard(Effect.forkScoped(loop)))` also runs it, but a failure of the forked loop does not reach `launch`, so the process keeps running and does nothing. Keep the loop on the main fiber.

`MainLayer` is the app layer with the observability layer merged in, one value: `AppLayer.pipe(Layer.provideMerge(ObservabilityLayer))`. Two chained `Effect.provide` calls are A15.

`NodeRuntime.runMain(effect, { disableErrorReporting?, teardown? })` requires `R = never` and is marked unstable:

- SIGINT and SIGTERM interrupt the main fiber. There is no force-exit.
- Exit code: 0 on success, 130 for interrupt-only causes (SIGTERM included, not 143), otherwise the error's `[Runtime.errorExitCode]` or 1 (`Runtime.defaultTeardown`, Runtime.ts:111-118). A custom `teardown: Runtime.Teardown` remaps codes, for example 143 for an orchestrator that expects it.
- `process.exit(code)` runs only after a signal or a non-zero code.
- `runMain` logs the failure cause after the effect you passed has finished. An observability layer provided inside that effect has already closed, so the final error goes to the default logger (Runtime.ts:211-219). Log fatal errors inside the provided effect when they must reach the exporter.
- `runMain` skips that log for interrupt-only causes, for errors with `[Runtime.errorReported] = false`, and with `disableErrorReporting`.

## Dynamic layers

Choose a layer from configuration with `Layer.unwrap` (services-and-layers.md#configuration).

For resources keyed by a value, use `LayerMap.Service` instead of hand-built caches:

```ts
export class PoolMap extends LayerMap.Service<PoolMap>()("@acme/tenancy/pool-map/PoolMap", {
  lookup: (tenantId: string) => DatabasePool.layer(tenantId),
  idleTimeToLive: "1 minute"
}) {}

const users = queryUsers.pipe(Effect.provide(PoolMap.get("acme")))
const program = users.pipe(Effect.provide(PoolMap.layer))
```

- `PoolMap.get(key)` is a `Layer<DatabasePool, E, PoolMap>`. Providing it per call is fine here; the map caches the built entry.
- Set `idleTimeToLive`. The default is zero, so an entry is released as soon as nobody holds it and rebuilt on the next `get`. `preloadKeys` is ignored without a TTL.
- `PoolMap.invalidate(key)` removes the entry. Current holders keep the old resource until they release it.
- Options: `lookup` or a static `layers` record, plus `dependencies`, `idleTimeToLive`, `preloadKeys`/`preload` (LayerMap.ts:414-489). Marked unstable.
- `LayerMap` suits resources that come and go with demand. It does not suit a process singleton that runs background fibers: with `idleTimeToLive` the map releases an idle entry, and its fibers, locks and in-memory state with it.

`Layer.build` and `Layer.buildWithScope` belong in infrastructure that owns a scope and memo map (LayerMap, HttpRouter, `@effect/vitest`). In application code they split the lifecycle. Two exceptions: a layer built in a session scope around a newly spawned resource, and a service that can only be built once a precondition holds (next section).

## A service built when a precondition appears

Some singletons can only be built after something exists at runtime: a profile in the database, a license, a leader lease. The process should serve what it can until then. Neither of the usual fixes allows that:

- A layer whose acquisition retries blocks every layer that depends on it. Under `Layer.launch`, the HTTP server does not listen until the precondition holds, so the process has no degraded mode.
- A `LayerMap` releases the singleton when it is idle (previous section).

Build it in the background instead. `make` forks the acquisition with retry into the layer scope, publishes the result through a `Deferred` (or a `SubscriptionRef` when the value can change later), and serves it behind a tag of its own. The real service keeps its tag; the handle gets a new one, and consumers yield the handle (audit A11).

```ts
export class ExecutorHandle extends Context.Service<ExecutorHandle, {
  readonly get: Effect.Effect<Executor["Service"], ExecutorUnavailable>
}>()("@acme/app/executor-handle/ExecutorHandle") {}

export const make: Effect.Effect<
  ExecutorHandle["Service"],
  never,
  Scope.Scope | Profiles | SqlClient.SqlClient
> = Effect.gen(function*() {
  const profiles = yield* Profiles
  const scope = yield* Effect.scope
  const context = yield* Effect.context<SqlClient.SqlClient>()
  const ready = yield* Deferred.make<Executor["Service"]>()

  yield* profiles.active.pipe( // fails until a profile exists
    Effect.flatMap((profile) =>
      Layer.buildWithScope(
        ExecutorLayer.layer.pipe(Layer.provide(Layer.succeed(Profile, profile))),
        scope
      ).pipe(Effect.provideContext(context))
    ),
    Effect.retry(Schedule.spaced("5 seconds")),
    Effect.flatMap((built) => Deferred.succeed(ready, Context.get(built, Executor))),
    Effect.forkScoped
  )

  const get = Deferred.isDone(ready).pipe(
    Effect.flatMap((done) => done ? Deferred.await(ready) : Effect.fail(new ExecutorUnavailable()))
  )
  return ExecutorHandle.of({ get })
})
```

Rules for any subgraph built at runtime:

- Type the subgraph with its real `RIn` and supply that from context captured in `make` (`Effect.context<R>()`, then `Effect.provideContext` at the build call). `make`'s type then lists the dependencies, and the root provides them once.
- Reference no infrastructure layer constant (`SqlLayer`) inside the subgraph. Whether such a reference reuses the app's instance depends on the calling fiber: `buildWithScope` forks the fiber's `CurrentMemoMap` (Layer.ts:600-605, 786-793), which is present only inside a layer build or under `Effect.provide`. Elsewhere it opens a second pool.
- Domain values computed at runtime (`profile` above) enter with `Layer.succeed` (services-and-layers.md#configuration). Captured services do not; re-providing `Layer.succeed(SqlClient, sql)` hides the requirement from the subgraph's type (audit A12).

## ManagedRuntime

Use `ManagedRuntime.make(layer, { memoMap? })` only to bridge a host that is not Effect: framework callbacks, React, a library that calls you. It is the wrong tool for a process entrypoint, where `runMain` already handles signals and exit codes.

- One runtime per process, or per framework adapter. Several runtimes share one memo map from `Layer.makeMemoMapUnsafe()` (ai-docs 04_integration/10_managed-runtime.ts).
- Dispose on shutdown with `runtime.dispose()` or `runtime.disposeEffect`. Disposal interrupts in-flight runs, then closes the layer scope. A module-level runtime nobody disposes never runs its finalizers. A browser runtime that lives as long as the page and whose layer registers no finalizers (only `FetchHttpClient`, say) needs no dispose path.
- In tests, use `layer(...)` from `@effect/vitest` instead (testing-with-layers.md#sharing-and-isolation).
- The layer builds lazily on first use, and a failed build is cached for the runtime's lifetime. A database outage at first use poisons the runtime. Retry inside the layer's acquisition, or dispose and recreate the runtime.
- `runSync` throws on an async layer build.
- Other code can share the runtime's instances through `Layer.effectContext(runtime.contextEffect)`.

Built-in alternatives: `HttpRouter.toWebHandler(appLayer, { memoMap? })` returns `{ handler, dispose }` for web-handler hosts; `Atom.runtime` covers React state.

From a host callback inside an Effect program, capture the context once with `Effect.context<R>()` and run with `Effect.runForkWith(context)(effect)` or `Effect.runPromiseWith(context)(effect)`.
