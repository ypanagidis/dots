# Testing with layers

## Runners

- `it.effect` wraps the test in `Effect.scoped` and provides `TestClock` and `TestConsole`. There is no `it.scoped`.
- `it.live` wraps in `Effect.scoped` only: real clock, real console. It does not exist inside a `layer` block. There, set `excludeTestServices: true` on the top-level `layer(...)` (nested blocks inherit it and cannot set their own), or use `TestClock.withLive`.
- Time starts at 0 and the test env has no seeded `Random`.
- Under `TestClock`, `Effect.sleep` waits until the test moves the clock. Fork the effect that sleeps, then call `TestClock.adjust(duration)` (testing/TestClock.ts:632) or `TestClock.setTime`. A sleep on the test's own fiber never wakes.

## Test assemblies

Build the test assembly from `layerNoDeps`, providing test dependencies with `Layer.provideMerge` so the test can yield them too (ai-docs 20_layer-tests.ts):

```ts
// user-repo/test.ts
export class UserRepoTestRef extends Context.Service<UserRepoTestRef, Ref.Ref<ReadonlyArray<User>>>()(
  "@acme/accounts/user-repo/UserRepo/Test"
) {}

const layerTestRef: Layer.Layer<UserRepoTestRef> = Layer.effect(UserRepoTestRef, Ref.make<ReadonlyArray<User>>([]))

export const layerTest: Layer.Layer<UserRepo | UserRepoTestRef> = Layer.effect(UserRepo, makeMemory).pipe(
  Layer.provideMerge(layerTestRef)
)

// signup/test.ts
export const layerTest: Layer.Layer<Signup | UserRepo | UserRepoTestRef> = SignupLayer.layerNoDeps.pipe(
  Layer.provideMerge(UserRepoTest.layerTest)
)
```

`makeMemory` here reads the ref with `yield* UserRepoTestRef`. When the same acquisition should provide both tags, `Layer.effectContext` (Layer.ts:1099) returning both does the same job.

Rules:

- A test assembly is a `const`. A `makeTestLayer()` factory returns a new object per call, so two consumers in one graph get two stores.
- `layerTest` takes no arguments. Seed data through the test ref or test-control service. If a test truly needs a parameterised layer, bind the call to one `const` in that test file.
- Override one service by rebuilding from `layerNoDeps` pieces. `Layer.merge(AppLayer, Override)` only wins in the final context; services inside `AppLayer` were already built against the original.
- Repos and adapters backed by a database are tested against the test database; they need no `layerMemory`. Write `layerMemory` for the services above them when their tests should not touch the database.
- `Layer.mock(X, partial)` (Layer.ts:2354) fits a small local fake. Omitted Effect, Stream or Channel members, and functions returning them, die with `UnimplementedError` when called; other members are required. Unused methods fail only at runtime, so prefer a faithful `layerMemory` for anything reused.

## Sharing and isolation

Per test, fresh services:

```ts
it.effect("registers a user", () =>
  Effect.gen(function*() {
    const signup = yield* Signup
    const users = yield* UserRepoTestRef
    yield* signup.register(input)
    expect((yield* Ref.get(users)).length).toBe(1)
  }).pipe(Effect.provide(SignupTest.layerTest))
)
```

Shared across a block:

```ts
layer(SignupTest.layerTest)("Signup", (it) => {
  it.effect("first", () => /* ... */)
  it.effect("sees state left by first", () => /* ... */)
})
```

- A named `layer(L)(name, f)` builds `L` once in `beforeAll` and releases it in `afterAll`. State, `TestClock` time and console lines carry over between its tests.
- Build failures in a block go through `Effect.orDie` and surface as defects.
- `buildPerTest: true` builds the layer per test into a fork of the block's memo map and releases it when the test ends.
- Nested `it.layer(L2)` may depend on the parent's services and reuses the parent's instances; sibling nested blocks are isolated from each other.
- `Effect.provide(X.layerTest)` inside a `layer(X.layerTest)` block returns the shared instance, because the block's memo map is ambient. Use `Effect.provide(X.layerTest, { local: true })` for a private copy, or `Layer.fresh`.
- `layer(L, { timeout })` is the hook timeout for build and teardown, not a test timeout.
- A `memoMap` shared across sequential top-level blocks saves nothing once the first block has closed; entries are reference-counted and rebuilt.
- A `ManagedRuntime` built in `beforeAll` and disposed in `afterAll` does what a `layer(...)` block does with more code. Existing ones are fine; new tests use `layer(...)`. One never disposed is audit A16.

## HTTP tests

- `HttpApiTest.groups(api, ["users"])` runs handlers in memory with a typed client, no server. Provide handlers built from their `NoDeps` layer plus `layerMemory` dependencies, merged with `HttpServer.layerServices` (ai-docs 51_http-server/20_testing.ts).
- `NodeHttpServer.layerTest` serves on port 0 and provides an `HttpClient` aimed at it. Combine with `HttpRouter.serve(...).pipe(Layer.provideMerge(NodeHttpServer.layerTest))`.

## Proving a composition root builds

Two proofs, both required for every root.

The type proof is the annotation. `Layer.Layer<AppServices, AppError>` has `RIn = never`, so a missing dependency fails to compile. The top-level `layer(...)` of `@effect/vitest` also accepts only `Layer.Layer<R, E>`, which rejects an open requirement in the test file.

The runtime proof builds the root against test infrastructure. Use `it.live` so a layer that retries or sleeps on the real clock cannot hang on `TestClock`:

```ts
import { it } from "@effect/vitest"
import { Effect, Layer } from "effect"
import type { SqlError } from "effect/sql"
import { AppServicesNoInfra, type AppServices } from "../src/app-layer.js"
import { TestSqlLayer } from "./infra.js"

const AppLayerTest: Layer.Layer<AppServices, SqlError.SqlError> = AppServicesNoInfra.pipe(Layer.provide(TestSqlLayer))

it.live("the app layer builds", () =>
  Effect.gen(function*() {
    yield* Layer.build(AppLayerTest)
  })
)
```

`it.live` supplies the `Scope` that `Layer.build` needs and closes it after the test, so finalizers run too. A build error stays a typed failure here, unlike the `orDie` in a `layer` block. `TestSqlLayer` is the test database or in-memory stand-ins; when the root uses `Layer.unwrap` over `Config`, provide the config the build reads.

## Overriding a dependency of a closed root

A test that provides over a root which already provides the same dependency (`AppLayer.pipe(Layer.provide(TestConfigLayer))`) looks like an override but is not one. `Layer.provide` builds `TestConfigLayer` first. If it wraps the same layer object the root references inside (`AppConfig.layer`), the root's reference hits the memo and gets the test instance. Once a refactor changes that identity, the root builds its own instance from the real environment. The test still compiles, and now runs against whatever database that environment names.

Build test graphs from the open form instead, `AppServicesNoInfra.pipe(Layer.provide(TestInfra))`, where a missing dependency is a type error. Before any refactor that moves layers inside a root (audit A6, A9), add the root's build test from `AppServicesNoInfra` and move tests that provide over the closed root onto it.
