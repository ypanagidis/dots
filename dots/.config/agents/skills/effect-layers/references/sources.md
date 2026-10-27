# Sources

For whoever refreshes this skill. Everything here is grounded in the Effect repository at 4.0.6; re-read these files on a version bump.

## services-and-layers.md

- `packages/effect/src/Context.ts` (`Service`, `Reference`, `ServiceClass`)
- `packages/effect/src/Layer.ts` (constructors, `provide`, `Success`/`Error`/`Services`)
- `packages/effect/src/Config.ts`, `ConfigProvider.ts`
- `ai-docs/src/01_effect/03_services/01_service.ts`, `10_reference.ts`, `20_layer-composition.ts`, `20_layer-unwrap.ts`
- `ai-docs/src/01_effect/05_resources/10_acquire-release.ts`, `20_layer-side-effects.ts`
- `ai-docs/src/51_http-server/fixtures/server/Users.ts` (`layerNoDeps` / `layer` / `layerMemory`), `fixtures/server/Users/http.ts` (`UsersApiHandlersNoDeps`)
- `ai-docs/src/08_observability/*` (`ObservabilityLayer`)
- `migration/services.md`, `migration/v3-to-v4.md` (Layer section)
- `packages/sql/pg/src/PgClient.ts`, `packages/platform/node/src/NodeHttpServer.ts` (module-level `make` / `layer` / `layerConfig`)

## composition-and-runtime.md

- `packages/effect/src/Layer.ts` (`provide`, `provideMerge`, `mergeAll`, `MemoMap`, `CurrentMemoMap`, `fresh`, `launch`, `build*`)
- `packages/effect/src/internal/layer.ts` (`Effect.provide` with layers)
- `packages/effect/src/Effect.ts` (`provide`, `acquireRelease`, `forkScoped`, `forkChild`, `runForkWith`)
- `packages/effect/src/ManagedRuntime.ts`, `LayerMap.ts`, `RcMap.ts`, `Runtime.ts`, `SubscriptionRef.ts`
- `packages/platform/node-shared/src/NodeRuntime.ts`, `packages/platform/node/src/NodeRuntime.ts`
- `ai-docs/src/01_effect/05_resources/*`, `ai-docs/src/01_effect/06_running/*`, `ai-docs/src/04_integration/10_managed-runtime.ts`
- `migration/layer-memoization.md`, `migration/runtime.md`, `migration/fiber-keep-alive.md`, `migration/forking.md`

## testing-with-layers.md

- `packages/vitest/src/index.ts`, `packages/vitest/src/internal/internal.ts` (`it.effect`, `it.live`, `layer`, `buildPerTest`, `excludeTestServices`, `TestEnv`)
- `packages/vitest/test/build-per-test.test.ts`, `nested-isolation.test.ts`, `isolation.test.ts`, `timeout.test.ts`
- `packages/effect/src/Layer.ts` (`mock`, `fresh`, `build`, memo maps)
- `packages/effect/src/testing/TestClock.ts`
- `ai-docs/src/09_testing/10_effect-tests.ts`, `20_layer-tests.ts`
- `ai-docs/src/51_http-server/20_testing.ts`, `packages/platform/node/src/NodeHttpServer.ts` (`layerTest`), `packages/effect/src/http-api/HttpApiTest.ts`
- `migration/layer-memoization.md` (opting out)

## audit.md

- `migration/v3-to-v4.md` (Layer and Effect sections), `migration/forking.md`, `migration/services.md`, `migration/layer-memoization.md`
- `packages/effect/src/Layer.ts` (export list), `LayerMap.ts`, `RcMap.ts`, `ManagedRuntime.ts`
- `packages/vitest/src/internal/internal.ts`
