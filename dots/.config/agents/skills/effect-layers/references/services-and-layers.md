# Services and layers

## The tag

`Context.Service<Self, Shape>()(id)` makes a class that is both the context key and the type. `X["Service"]` is the shape. `X.of(value)` returns its argument and exists for typing (Context.ts:103-108, 151-155).

The id is the service's runtime identity. Two services with the same id take the same slot in a context. Build it from the package name, the directory path and the class name: `"@acme/accounts/user-repo/UserRepo"`. Upstream examples: `"@effect/sql-pg/PgClient"`, `"effect/http/FetchHttpClient/Fetch"`, and the comment at 01_service.ts:16-18. A test-control tag appends `/Test`.

Module layout, `service.ts`:

```ts
import { Context, type Effect, type Option, Schema } from "effect"
import type { User, UserId } from "../domain/user.js"

export class UserRepoError extends Schema.TaggedError<UserRepoError>()("UserRepoError", {
  cause: Schema.Defect()
}) {}

export interface Interface {
  readonly findById: (id: UserId) => Effect.Effect<Option.Option<User>, UserRepoError>
}

export class UserRepo extends Context.Service<UserRepo, Interface>()(
  "@acme/accounts/user-repo/UserRepo"
) {}
```

Call `Context.Service<Self, Interface>()(id)` with the id alone, so the shape comes from the interface. The `{ make }` overload infers the shape from the implementation, which reverses type-first, and creates no layer in v4 (migration/services.md:171-199).

## `make`

`make` builds the service value. Give it an explicit type so a new `yield*` that adds a requirement or error fails at the definition instead of surfacing at the composition root.

Module layout, `layer.ts`:

```ts
import { Array, Effect, Layer } from "effect"
import { SqlClient } from "effect/sql"
import type { User, UserId } from "../domain/user.js"
import { UserRepo, UserRepoError } from "./service.js"

export const make: Effect.Effect<UserRepo["Service"], never, SqlClient.SqlClient> =
  Effect.gen(function*() {
    const sql = yield* SqlClient.SqlClient

    const findById = Effect.fn("UserRepo.findById")(
      function*(id: UserId) {
        const rows = yield* sql<User>`SELECT * FROM users WHERE id = ${id}`
        return Array.head(rows)
      },
      Effect.mapError((cause) => new UserRepoError({ cause }))
    )

    return UserRepo.of({ findById })
  })

// SqlClient is shared infrastructure, so the root provides it and `layer` is the only export.
export const layer: Layer.Layer<UserRepo, never, SqlClient.SqlClient> = Layer.effect(UserRepo, make)
```

Rules for `make`:

- Yield stable dependencies once at the top and close over them in methods. `yield* X` keeps the dependency visible. `X.use(f)` hides it at the call site (migration/services.md:126-140).
- Name every method with `Effect.fn("X.method")`.
- Resources go through `Effect.acquireRelease`. `Scope` may appear in the `R` of `make`; `Layer.effect` removes it and supplies the layer's own scope (Layer.ts:1039-1046). Wrapping `make` in `Effect.scoped` releases the resource before anyone uses the layer.
- Long-lived fibers (pollers, listeners, subscriptions) use `Effect.forkScoped`, which ties the fiber to the layer scope. `Effect.forkChild` (v3 `Effect.fork`) ties it to whichever fiber runs the build. That fiber is often short-lived: `merge`, `mergeAll` and array-form `provide` build each layer in its own fiber, and `ManagedRuntime` builds in a dedicated one (Layer.ts:1209-1220, ManagedRuntime.ts:363). There the poller is interrupted silently when construction finishes. `Layer.launch` of a plain provide chain builds on the main fiber, where the same poller survives. So `forkChild` works or fails depending on how the graph is composed; `forkScoped` is always correct.

## A service with owned dependencies

`layerNoDeps` keeps every requirement open. `layer` provides the owned dependencies, here a repo with one production implementation, and leaves infrastructure open. A repo that several services use is still owned by each: every `layer` provides the same `UserRepoLayer.layer` const, and memoization builds it once per graph.

```ts
import { Effect, Layer } from "effect"
import type { SqlClient } from "effect/sql"
import { UserRepo } from "../user-repo/service.js"
import * as UserRepoLayer from "../user-repo/layer.js"
import { Signup } from "./service.js"

export const make: Effect.Effect<Signup["Service"], never, UserRepo> = Effect.gen(function*() {
  const users = yield* UserRepo
  const register = Effect.fn("Signup.register")(function*(input: SignupInput) {
    // ...
  })
  return Signup.of({ register })
})

export const layerNoDeps: Layer.Layer<Signup, never, UserRepo> = Layer.effect(Signup, make)

export const layer: Layer.Layer<Signup, never, SqlClient.SqlClient> = layerNoDeps.pipe(
  Layer.provide(UserRepoLayer.layer)
)
```

`Layer.provide` hides `UserRepo` from consumers of `layer`. Tests swap it only through `layerNoDeps`, which is why a module that provides anything also exports `layerNoDeps` (ai-docs/src/09_testing/20_layer-tests.ts).

Dependency layers keep their own requirements: `Layer.provide(that)` adds `that`'s `RIn` to the result (Layer.ts:1463). That is how `SqlClient` reaches `layer`'s type above.

## What goes where in the module layout

- `service.ts`: the interface, the tag, its errors, and the types and schemas consumers need. It imports types and schemas only, so consumers depend on it without pulling in an implementation.
- A helper that consumers call and that imports runtime code (a span wrapper, an encoder built on a runtime module) gets its own module beside `service.ts`, e.g. `<capability>/span.ts`.
- A helper only the implementation uses stays in `layer.ts`, or in a private module `layer.ts` imports.
- `HttpApiBuilder.group` handlers go in `http.ts` beside `layer.ts` (upstream: `fixtures/server/Users/http.ts`), unless the repo already keeps them in `layer.ts`.

Splitting a single-file module (tag, `make` and layers in one file):

1. Create `<capability>/service.ts` and `<capability>/layer.ts` in a directory named after the old file. Move the code per the list above.
2. Update the package's `exports` if it lists files instead of a `./*` pattern, and the namespaces in `index.ts`.
3. Update every consumer import in the same change: code that yields the tag imports `service`, composition roots import `layer`. Delete the old file instead of leaving a re-export; the typecheck lists every import left.

## Statics layout

The same roles as class members. `this` in a static initializer is the class.

```ts
export class UserRepo extends Context.Service<UserRepo, {
  findById(id: UserId): Effect.Effect<Option.Option<User>, UserRepoError>
}>()("@acme/accounts/user-repo/UserRepo") {
  static readonly make: Effect.Effect<UserRepo["Service"], never, SqlClient.SqlClient> =
    Effect.gen(function*() {
      const sql = yield* SqlClient.SqlClient
      // ...
      return UserRepo.of({ findById })
    })

  static readonly layer: Layer.Layer<UserRepo, never, SqlClient.SqlClient> = Layer.effect(this, this.make)
}
```

Upstream ai-docs use this layout (01_service.ts, 20_layer-composition.ts). Platform modules use the module layout with function-form keys (PgClient.ts:79, 217, 430-466).

## Layer constructors

Pick the constructor that matches acquisition (Layer.ts line numbers):

| Constructor | Use | Memoized |
|---|---|---|
| `Layer.succeed(X, value)` | an existing value (:827) | no, nothing to build |
| `Layer.sync(X, () => value)` | lazy synchronous construction (:949) | yes |
| `Layer.effect(X, make)` | effectful or scoped acquisition; `RIn` excludes `Scope` (:1039) | yes |
| `Layer.effectContext(eff)` | one acquisition provides several tags, e.g. `PgClient` and `SqlClient` (:1099) | yes |
| `Layer.effectDiscard(eff)` | side effects or background fibers, no service (:1133) | yes |
| `Layer.unwrap(eff)` | an effect chooses which layer to use, typically from `Config` (:1205) | via the inner layer |
| `Layer.suspend(() => layer)` | lazy choice (:1165) | yes |
| `Layer.mock(X, partial)` | tests only; see testing-with-layers.md (:2354) | |

## Configuration

A value a layer needs falls in one of three cases:

- **Tuning values with production defaults** (batch sizes, debounce, timeouts, switches a test turns off). Read them in `make` with `Config` and `Config.withDefault`. The layer stays argument-less, and tests override values with `Layer.provide(ConfigProvider.layer(ConfigProvider.fromUnknown({ ... })))`.
- **Domain or runtime values** (the active tenant, a profile loaded from the database, anything the program computes). Give the value its own tag. The code that produces it provides it with `Layer.succeed(Tag, value)`, and services yield the tag like any dependency. It is neither infrastructure nor configuration. Use a `Context.Reference` when a truthful default exists.
- **Infrastructure options** (URLs, pool sizes, credentials). The adapter takes them, following PgClient: `layer(options)` for decoded options and `layerConfig(config: Config.Wrap<Options>)` for `Config` recipes.

An application layer factory that takes configuration as arguments pushes graph construction onto every caller.

Choose an implementation from configuration with `Layer.unwrap` (ai-docs 20_layer-unwrap.ts):

```ts
export const layer: Layer.Layer<MessageStore, Config.ConfigError | MessageStoreError> = Layer.unwrap(
  Effect.gen(function*() {
    const inMemory = yield* Config.Boolean("MESSAGE_STORE_IN_MEMORY").pipe(Config.withDefault(false))
    if (inMemory) return layerMemory
    const url = yield* Config.URL("MESSAGE_STORE_URL")
    return layerRemote(url)
  })
)
```

An adapter's `layerConfig`:

```ts
export const layerConfig = (
  config: Config.Wrap<MailerOptions>
): Layer.Layer<Mailer, Config.ConfigError | MailerError> =>
  Layer.effect(Mailer, Effect.flatMap(Config.unwrap(config), makeWith))
```

Every call of a factory returns a new layer object and so a new instance.

Config constructors are capitalized: `Config.String`, `Config.Boolean`, `Config.Redacted`, `Config.URL` (Config.ts:979, 1307, 1484, 1527). The lowercase forms some docs show do not exist; only combinators such as `option`, `schema` and `withDefault` are lowercase.

## References

`Context.Reference<T>(id, { defaultValue })` is a service with a lazy, cached default. It adds no requirement, so it fits ambient values with a truthful default: feature flags, host facts, the current tenant (Context.ts:1366-1373; ai-docs 10_reference.ts).

```ts
export const FeatureFlag = Context.Reference<boolean>("@acme/flags/feature-flag/FeatureFlag", {
  defaultValue: () => false
})
```

Override it like any service, with `Layer.succeed(FeatureFlag, true)`.

## Naming

Inside a service's module, layers are named by role (the Vocabulary in SKILL.md), and the module or class names the service. `Default`, `Live` and `Layer`-suffixed constants there (`FooLive`, `UserRepoDefault`, `pgClientLayer`) carry v3 habits. A namespace import of a `layer.ts` (`import * as UserRepoLayer`) is fine.

Layers that are not one service's implementation take PascalCase names, as in upstream's ai-docs:

- Composition roots and assemblies of several services: `<Name>Layer` (`AppLayer`, `ServerLayer`), with `<Name>NoInfra` for the form that leaves infrastructure open (`AppServicesNoInfra`).
- Infrastructure bound to a `const` in a root: `<Name>Layer` (`SqlLayer`).
- `HttpApiBuilder.group` handlers: `<Group>Handlers`, and `<Group>HandlersNoDeps` before their dependencies are provided (51_http-server).
- `Layer<never>` layers that install a logger, tracer or other references: `<Concern>Layer` (`ObservabilityLayer`, 08_observability).

`Live` and `Default` suffixes are A4 everywhere.

## Typing helpers

- `Layer.Success<L>`, `Layer.Error<L>`, `Layer.Services<L>` read `ROut`, `E`, `RIn` from a layer (Layer.ts:155-189). `Services` replaces v3 `Layer.Layer.Context`.
- `Layer.satisfiesSuccessType<T>()(layer)`, `satisfiesErrorType`, `satisfiesServicesType` check a constraint without widening the inferred type (Layer.ts:2438-2497). Use them where a full annotation would be unwieldy, such as a long `ROut` union or an `HttpApiBuilder.group` handler layer.
