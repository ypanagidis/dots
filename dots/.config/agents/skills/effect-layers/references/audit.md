# Audit

Each catalogue entry states the fix; the rule's full explanation lives in services-and-layers.md, composition-and-runtime.md or testing-with-layers.md.

Run from the repository root. Every `rg` command below ends with a path (`.`), because `rg` without one reads stdin when stdin is not a terminal (agent shells, scripts, background tasks) and hangs. For the same reason, pipes into `rg` go through `xargs -r`, which skips the command on empty input. `rg` respects `.gitignore`; add `-g '!<vendored dir>/**'` for vendored or reference code that is never edited. Record every check's result, hits with `file:line` or "clean".

## Checklist

Each check carries the id of its catalogue entry.

**A1. v3 APIs that no longer exist in v4.**

```sh
rg -n --type ts 'Layer\.(scoped|scopedContext|scopedDiscard|fail|failSync|failCause|failCauseSync|die|dieSync|mapError|catchAll|catchAllCause|tapErrorCause|orElse|map|project|service|function|retry|memoize|unwrapEffect|unwrapScoped|toRuntime|toRuntimeWithMemoMap|ensureSuccessType|ensureErrorType|ensureRequirementsType|setConfigProvider|setTracer|setClock|setRandom|setScheduler|annotateLogs|annotateSpans|zipWith|passthrough|discard|context|flatten|match|matchCause|extendScope|scope|locally\w*)\b|Layer\.Layer\.Context\b|Effect\.(Service|Tag|fork|forkDaemon)\b|Context\.(Tag|GenericTag)\b|\.(Default|Live)\b|it\.(scoped|scopedLive)\b' .
```

Every hit is A1.

**A2. Service ids, duplicated or without a path.**

```sh
ids() { rg -U --no-filename -o --type ts '(Context|LayerMap)\.(Service|Reference)<[^;]*?>\(\)\(\s*"[^"]+"' . | grep -o '"[^"]*"$'; }
ids | sort | uniq -d               # duplicates: A2 hit
ids | grep -Ev '/[^"/]+/[^"/]+"$'  # fewer than two path segments: A2 hit
rg -n --type ts 'Context\.(Service|Reference)<[^>]*>\("' .
```

The last command finds function-form keys (`Context.Service<Shape>("id")`) and `Context.Reference<T>("id", ...)`; apply the same two rules to their ids.

**A3. `make` and exported layers without a type.**

```sh
rg -n --type ts '^export const (make|layer\w*|\w*Layer\w*)\s*=|^const make\s*=|static readonly (make|layer\w*)\s*=' .
```

The pattern only matches names with no annotation before `=`. A factory (`= (...): Layer.Layer<...> =>`) with an annotated return type is clean. Every other hit is A3.

**A4. Layer names outside the convention.**

```sh
rg -n --type ts '^export const \w*(Live|Default)\s*[:=]|static readonly (Live|Default)\b' .
rg -n --type ts '^export const \w+Layer\s*[:=]' -g '**/layer.ts' -g '**/service.ts' -g '**/memory.ts' .
```

Also run the second pattern over the single-file modules the fourth A5 command lists. Every hit is A4. Roots, assemblies, infrastructure bindings and `Layer<never>` layers named `<Name>Layer` in their own modules are conventional (services-and-layers.md#naming) and these patterns do not match them.

**A5. Layout drift.**

```sh
rg -l --type ts 'static readonly layer' . | wc -l
rg --files -g '**/layer.ts' . | wc -l
rg -l --type ts 'Context\.Service<' -g '**/service.ts' . | xargs -r rg -l 'Layer\.(effect|effectContext|succeed|sync)\('
rg -l --type ts 'Context\.Service<' -g '!**/service.ts' -g '!**/layer.ts' -g '!**/test/**' -g '!**/*.test.ts' . | xargs -r rg -l 'Layer\.(effect|effectContext|succeed|sync)\('
```

The larger of the first two counts is the repo's layout; with both at zero, it is the module layout in a multi-package repo and statics otherwise. The third command lists `service.ts` files that also implement. The fourth lists single-file modules (tag and layers in one file). A5 hits:

- every file in the minority layout;
- every `service.ts` from the third command;
- every file from the fourth command, except statics-layout files in a statics repo.

**A6. `provideMerge` use.**

```sh
rg -n --type ts 'Layer\.provideMerge' .
```

A hit is clean when a program or test yields the merged service; record which. Otherwise it is A6.

**A7. Provides outside entrypoints and tests.**

```sh
rg -n --type ts 'Effect\.provide\(' -g '!**/test/**' -g '!**/*.test.ts' .
```

Clean:

- the process entrypoint;
- `Effect.provide(SomeMap.get(key))`;
- a CLI command that runs once per invocation and provides layers built from its own arguments (a source database URL, say).

Every other hit inside a handler, service method or `make` is A7.

**A8. Layer factories called more than once.**

```sh
rg --no-filename -o --type ts '\b(\w+\.)?(layer\w*|\w*Layer\w*|\w*Services)\(' . | sort | uniq -c | sort -rn
```

Ignore `layer(` and `it.layer(` from `@effect/vitest`. For each name with a count above 1, a second call that lands in the same graph is A8. A call inside a function, loop or retry that runs more than once per process is A8 too, whatever the count.

**A9. Configuration passed as factory arguments to application layers.**

```sh
rg -n --type ts '^export const (layer\w*|\w*Layer\w*|\w*Services)\s*=\s*(<[^>]*>\s*)?\(|^export function (layer\w*|\w*Layer\w*|\w*Services)\b|static readonly layer\w*\s*=\s*\(' .
```

A hit on an infrastructure adapter (`layerConfig`, `layer(options)` on a client) or a `Layer<never>` layer (`ObservabilityLayer(options)`) is clean. A hit on an application service is A9.

**A10. Graph built at runtime.**

```sh
rg -n --type ts 'Layer\.(build|buildWithScope|buildWithMemoMap|makeMemoMap|makeMemoMapUnsafe)\b' -g '!**/test/**' -g '!**/*.test.ts' .
```

A hit that follows composition-and-runtime.md#a-service-built-when-a-precondition-appears (forked into the layer scope, dependencies from context captured in `make`, served by its own tag) is clean. Every other hit in application code is A10.

**A11. Several implementations behind one tag.**

```sh
rg --no-filename -o --type ts 'Layer\.(effect|effectContext|succeed|sync|mock)\(\s*(\w+)' -r '$2' . | sort | uniq -c | sort -rn
```

`layer` plus `layerMemory`/`layerTest` is normal. Two production layers with different semantics for one tag are A11.

**A12. Captured services re-provided.**

```sh
rg -n --type ts 'Layer\.succeed\(' -g '!**/test/**' -g '!**/*.test.ts' .
```

A hit whose value came from `yield*` of a service is A12. A domain value the code computed (a loaded profile, the current tenant) is clean.

**A13. Background fibers that die with the build fiber.**

```sh
rg -n --type ts 'forkChild|Effect\.fork\b|forkDaemon' .
```

A hit inside `make`, `Layer.effect` or `Layer.effectDiscard` is A13. `Effect.fork` and `forkDaemon` are also A1.

**A14. Isolation opt-outs.**

```sh
rg -n --type ts 'Layer\.fresh|local:\s*true' .
```

A hit without an adjacent comment giving the reason is A14.

**A15. Entrypoints.**

```sh
rg -n --type ts 'runMain|Layer\.launch' -g '!**/test/**' -g '!**/*.test.ts' .
rg -n --type ts -B6 'runMain' -g '!**/test/**' -g '!**/*.test.ts' . | rg 'Effect\.provide\('
```

Per process: more than one entrypoint, or more than one `Effect.provide` on the way to `runMain` (the second command), is A15.

**A16. Runtimes.**

```sh
rg -n --type ts 'ManagedRuntime\.make' .
rg -n --type ts '\.dispose(Effect)?\b|memoMap' .
```

A `ManagedRuntime` that serves as a process entrypoint, has no dispose path (`afterAll` in tests), or is one of several in a process without a shared `memoMap` is A16. A browser runtime that lives as long as the page and whose layer registers no finalizers is clean.

**A17. Keyed resources.**

```sh
rg -n --type ts -A8 'LayerMap\.Service' . | rg 'LayerMap\.Service|idleTimeToLive'
```

A `LayerMap.Service` with no `idleTimeToLive` line after it is A17.

**A18. Accessor style.**

```sh
rg -n --type ts '\b[A-Z]\w*\.use(Sync)?\(' .
```

A hit on a service tag is A18; `React.use` and `HttpRouter.use` are unrelated.

**A19. Layer error handling.**

```sh
rg -n --type ts 'Layer\.orDie' .
rg -l --type ts 'Config\.|layerConfig' . | xargs -r rg -n '\borDie\b'
```

A hit over a layer that reads `Config` or opens a connection, or over the `Config` reads in a `Layer.unwrap` or `make` body, is A19.

**A20. Test coverage of the graph.**

```sh
rg -l --type ts 'layerTest|layerMemory|layerNoDeps' .
rg -n --type ts 'Layer\.build\(' -g '**/test/**' -g '**/*.test.ts' .
```

A composition root without a build test is A20. So is a service with owned dependencies and no `layerNoDeps`, because tests cannot swap them. Repos and adapters backed by a database and tested against the test database are clean.

**A21. Tests that override a closed root.**

```sh
rg -n -U --type ts '\w+\.pipe\(\s*Layer\.provide(Merge)?\(|Layer\.provide(Merge)?\(\s*\w+\s*,' -g '**/test/**' -g '**/*.test.ts' .
```

A hit whose target is a closed root (its `RIn` is already `never`, e.g. `AppLayer`) is A21.

## Anti-pattern catalogue

Apply fixes in catalogue order, with two exceptions. Fix A11 before A4: renaming first can leave two modules exporting `layer` for one tag. Fix A21 and add the root build test (A20) before A6 or A9: those refactors move layers inside the root, which breaks A21 tests silently.

**A1. v3 API.** Does not compile on v4 or reads as v3. Fix with the v4 replacement:

| v3 | v4 |
|---|---|
| `Layer.scoped` / `scopedContext` / `scopedDiscard` | `Layer.effect` / `effectContext` / `effectDiscard` |
| `Layer.unwrapEffect`, `unwrapScoped` | `Layer.unwrap` |
| `Layer.fail(e)`, `failSync`, `failCause`, `failCauseSync` | `Layer.unwrap` over the Effect constructor: `Layer.unwrap(Effect.fail(e))` |
| `Layer.die(d)`, `dieSync(f)` | `Layer.unwrap(Effect.die(d))`, `Layer.unwrap(Effect.suspend(() => Effect.die(f())))` |
| `Layer.catchAll`, `catchAllCause`, `tapErrorCause` | `Layer.catch`, `Layer.catchCause`, `Layer.tapCause` |
| `Layer.orElse(f)` | `Layer.catch(self, () => fallback)` |
| `Layer.map`, `Layer.project`, `Layer.flatten` | `Layer.flatMap` |
| `Layer.service(X)` | `Layer.effect(X, X)` |
| `Layer.function` | `Layer.effect(B, Effect.map(A, f))` |
| `Layer.context` | `Layer.effectContext(Effect.context<R>())` |
| `Layer.passthrough` | `Layer.merge(Layer.effectContext(Effect.context<RIn>()), self)` |
| `Layer.discard` | `Layer.flatMap(self, () => Layer.empty)` |
| `Layer.retry` | `Effect.retry` on the acquisition effect |
| `Layer.memoize` | ambient memo maps; delete it |
| `Layer.mapError`, `annotateLogs`, `annotateSpans`, `zipWith`, `match`, `matchCause` | wrap with `Layer.fromBuild` and `Layer.buildWithMemoMap`; `Layer.merge` when `zipWith` only merged contexts |
| `Layer.toRuntime`, `toRuntimeWithMemoMap` | `Layer.build` / `buildWithMemoMap`, then `Effect.runForkWith` / `runPromiseWith`; or `ManagedRuntime` |
| `Layer.extendScope` | `Layer.buildWithScope(self, outerScope)`, then `Effect.provideContext` |
| `Layer.scope` | `Layer.effect(Scope.Scope, Effect.acquireRelease(Scope.make(), Scope.close))` |
| `Layer.ensureSuccessType` / `ensureErrorType` / `ensureRequirementsType` | `Layer.satisfiesSuccessType` / `satisfiesErrorType` / `satisfiesServicesType` |
| `Layer.setConfigProvider(p)` | `ConfigProvider.layer(p)` |
| `Layer.setTracer`, `setClock`, `setRandom`, `setScheduler` | `Layer.succeed(Tracer.Tracer, tracer)`, `Layer.succeed(Clock.Clock, clock)`, `Layer.succeed(Random.Random, random)`, `Layer.succeed(Scheduler.Scheduler, scheduler)` |
| `Layer.locally`, `locallyWith` | `Layer.updateService(self, reference, f)` |
| `Layer.locallyScoped` | `Layer.succeed(reference, value)` |
| `Layer.Layer.Context<L>` | `Layer.Services<L>` |
| `Effect.fork`, `Effect.forkDaemon` | `Effect.forkChild` (`Effect.forkScoped` inside a layer, A13), `Effect.forkDetach` |
| `Effect.Service`, `Context.Tag`, `Effect.Tag` | `Context.Service<Self, Shape>()(id)` |
| `.Default`, `.Live` | `layer` |
| static proxy calls `X.method()` | `yield* X` |
| `it.scoped`, `it.scopedLive` | `it.effect`, `it.live` |

**A2. Id collision or bare id.** Two services with one id share a context slot. Fix: `"<package>/<path>/<Name>"`, e.g. `"@acme/accounts/user-repo/UserRepo"`.

**A3. Untyped `make` or layer.** A new `yield*` adds a requirement nothing flags until the composition root, and doc comments like "needs Db" go stale. Fix: `make: Effect.Effect<X["Service"], E, R>` and `Layer.Layer<X, E, RIn>` on every exported layer, whatever its name.

**A4. Non-conventional names** (`FooLive`, `pgClientLayer`, `UserRepoDefault`). Fix: services-and-layers.md#naming; the module or class carries the service name.

**A5. Mixed layouts or implementation in `service.ts`.** Consumers of the tag pull in the implementation and its dependencies. Fix: move `make` and layers to `layer.ts`, or to statics in a statics-layout repo. Split single-file modules per services-and-layers.md#what-goes-where-in-the-module-layout, including its migration steps.

**A6. `provideMerge` everywhere.** Infrastructure such as `SqlClient` leaks into the app context, so services reach the raw client with no trace in their types. Fix: `Layer.provide` in each service's `layer`; the root merges only the services the program yields. Where several processes or later stages share the services, follow composition-and-runtime.md#several-processes-one-set-of-services, and provide each leaked dependency explicitly before removing the `provideMerge`.

**A7. Provide inside a handler or method.** Unless an enclosing provide or runtime already built the same layer object, the layer is built per call; either way the dependency is hidden. Fix: yield the service in `make` and provide the layer once at the root.

**A8. Factory called twice in one graph.** Two pools, two sets of finalizers. Fix: bind the call to one `const` in the composition root.

**A9. Configuration as arguments of application layers** (`layer(options)`, `X.layer(content)`). Callers build graphs by hand. Fix by the kind of argument (services-and-layers.md#configuration): tuning values move to `Config` with `withDefault` and tests override them through `ConfigProvider`; a domain or runtime value gets its own tag, provided with `Layer.succeed` by the code that produces it; infrastructure options stay on the adapter's `layerConfig`.

**A10. Graph built at runtime.** `Layer.buildWithScope` behind a hand-written lock and cache. Whether it reuses app instances depends on the calling fiber: `buildWithScope` forks the fiber's `CurrentMemoMap`, which exists only inside a layer build or under `Effect.provide`, and then on layer object identity. Fix by why it is built at runtime:

- the resource varies by a key and comes and goes with demand: `LayerMap.Service` keyed by the value, with `invalidate` on change;
- the process cannot do anything useful without it: a layer whose acquisition retries;
- a singleton that can only be built once a precondition holds, while the process keeps serving: composition-and-runtime.md#a-service-built-when-a-precondition-appears.

`LayerMap` does not suit a process singleton that runs background fibers; an idle entry is released with its fibers.

**A11. One tag, two meanings.** A lazy proxy and the real implementation behind the same tag; which one a consumer gets depends on which provide wins. Fix: the real implementation in its package keeps the tag; the app-level proxy gets its own tag, and every consumer that should see the proxy yields the new tag.

**A12. Re-providing a captured service** (`Layer.succeed(Db, db)` with `db` from `yield* Db`). Hides the dependency from the type. Fix: in a static graph, let the requirement propagate and provide the real layer at the root. In a subgraph built at runtime, leave the dependency in the subgraph's `RIn` and supply it from context captured in `make` at the build call; reference no infrastructure layer constant inside (composition-and-runtime.md#a-service-built-when-a-precondition-appears).

**A13. `forkChild` (v3 `fork`) in layer construction.** The fiber lives as long as the fiber running the build, which `mergeAll`, array-form `provide` and `ManagedRuntime` end as soon as construction finishes. Whether it survives depends on how the graph is composed. Fix: `Effect.forkScoped`.

**A14. `Layer.fresh` or `local: true` used to dodge confusing composition.** `fresh` rebuilds every dependency too. Fix: compose once; keep the opt-out only for deliberate isolation, with a comment that says why.

**A15. Several provides at an entrypoint** (`Effect.provide(appLayer)` then `Effect.provide(ObservabilityLayer)`). Fix: one layer, `appLayer.pipe(Layer.provideMerge(ObservabilityLayer))`, then one provide, or `Layer.launch`. Update doc comments and examples that show the old pattern in the same change.

**A16. `ManagedRuntime` misuse.** Used as a process entrypoint (loses signal handling and exit codes), never disposed (finalizers never run), or several runtimes with separate memo maps (duplicate instances). Fix: `runMain` for entrypoints; otherwise one disposed runtime per host with a shared `memoMap`; in tests, `layer(...)` from `@effect/vitest`.

**A17. `LayerMap` without `idleTimeToLive`.** Each `get` builds and releases. Fix: set it.

**A18. `X.use(f)` as the default access.** Hides the dependency at the call site. Fix: `yield* X`; keep `use` for one-liners at non-Effect bridges.

**A19. `orDie` over config or connection failures** (`Layer.orDie`, or `Effect.orDie` on `Config` reads in a `Layer.unwrap` or `make`). Misconfiguration becomes a defect and loses typed reporting at boot. Fix: keep the error typed to the entrypoint.

**A20. No test layers or no root build test.** A service with owned dependencies has no `layerNoDeps` to swap them, and a broken graph is found at deploy. Fix: `layerNoDeps` plus `layerMemory`/`layerTest` per testing-with-layers.md, and one build test per composition root.

**A21. Override through memo identity.** A test provides a test layer over a closed root that already provides the same dependency. It works only because both reference one layer object, so a refactor inside the root silently points the test at the real environment. Fix: build the test graph from the root's open form (`AppServicesNoInfra.pipe(Layer.provide(TestInfra))`), per testing-with-layers.md#overriding-a-dependency-of-a-closed-root.
