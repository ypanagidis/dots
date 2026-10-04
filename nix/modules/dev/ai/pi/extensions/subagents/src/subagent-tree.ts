import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { SubagentSnapshot } from "./domain.ts";
import type { SubagentReadModel } from "./manager.ts";

export const SUBAGENT_TREE_REGISTRY_REQUEST_EVENT =
  "subagents:agent-tree-registry:request:v1";
export const SUBAGENT_TREE_REGISTRY_OFFER_EVENT =
  "subagents:agent-tree-registry:offer:v1";

export interface SubagentTreeOptions {
  readonly runningOnly?: boolean;
  readonly modelOnly?: boolean;
}

export interface SubagentTreeNode {
  /** Stable native child-session id (with an owner/local-id fallback in tests). */
  readonly key: string;
  readonly ownerKey: string;
  readonly snapshot: SubagentSnapshot;
  readonly ownerView: SubagentReadModel;
  /** Zero for a direct child of the teamlead, one for its child, and so on. */
  readonly depth: number;
  readonly parentKey?: string;
  readonly ancestorLast: ReadonlyArray<boolean>;
  readonly isLast: boolean;
  readonly idPath: ReadonlyArray<string>;
}

export interface SubagentTreeView {
  list(options?: SubagentTreeOptions): ReadonlyArray<SubagentTreeNode>;
  get(key: string): SubagentTreeNode | undefined;
  size(): number;
  directKey(id: string): string | undefined;
  subscribe(listener: () => void): () => void;
  subscribeTo(key: string, listener: () => void): () => void;
  requestSend(key: string, text: string): void;
  requestAbort(key: string): void;
}

interface CoordinatorRegistration {
  readonly token: symbol;
  readonly view: SubagentReadModel;
  readonly unsubscribe: () => void;
}

interface TreeDraft {
  readonly ownerKey: string;
  readonly snapshot: SubagentSnapshot;
  readonly ownerView: SubagentReadModel;
  readonly children: ReadonlyArray<TreeDraft>;
}

export function createSubagentTreeBridge(registry: SubagentTreeRegistry) {
  return {
    name: "subagent-tree-bridge",
    hidden: true,
    factory(pi: ExtensionAPI) {
      const offer = () =>
        pi.events.emit(SUBAGENT_TREE_REGISTRY_OFFER_EVENT, registry);
      pi.events.on(SUBAGENT_TREE_REGISTRY_REQUEST_EVENT, offer);
      offer();
    },
  };
}

/** Resolve an inherited root registry, or create one for a top-level session. */
export function resolveSubagentTreeRegistry(
  pi: ExtensionAPI,
): SubagentTreeRegistry {
  let inherited: SubagentTreeRegistry | undefined;
  pi.events.on(SUBAGENT_TREE_REGISTRY_OFFER_EVENT, (value: unknown) => {
    const registry = value as SubagentTreeRegistry;
    if (registry && typeof registry.register === "function") {
      inherited ??= registry;
    }
  });
  pi.events.emit(SUBAGENT_TREE_REGISTRY_REQUEST_EVENT, {});
  return inherited ?? new SubagentTreeRegistry();
}

export function subagentTreeNodeKey(
  ownerKey: string,
  snapshot: Pick<SubagentSnapshot, "id" | "meta">,
): string {
  return snapshot.meta.nativeSessionId ?? `${ownerKey}\0${snapshot.id}`;
}

export function subagentTreePrefix(
  node: Pick<SubagentTreeNode, "ancestorLast" | "isLast">,
): string {
  return (
    node.ancestorLast.map((last) => (last ? "   " : "│  ")).join("") +
    (node.isLast ? "└─ " : "├─ ")
  );
}

function childCoordinatorKey(snapshot: SubagentSnapshot): string | undefined {
  return snapshot.meta.nativeSessionId;
}

export class SubagentTreeRegistry {
  private readonly coordinators = new Map<string, CoordinatorRegistration>();
  private readonly listeners = new Set<() => void>();

  register(
    key: string,
    view: SubagentReadModel,
  ): { readonly view: SubagentTreeView; unregister(): void } {
    const token = Symbol(key);
    const previous = this.coordinators.get(key);
    previous?.unsubscribe();
    const registration: CoordinatorRegistration = {
      token,
      view,
      unsubscribe: view.subscribe(() => this.notify()),
    };
    this.coordinators.set(key, registration);
    this.notify();

    let active = true;
    return {
      view: this.view(key),
      unregister: () => {
        if (!active) return;
        active = false;
        const current = this.coordinators.get(key);
        if (current?.token !== token) return;
        current.unsubscribe();
        this.coordinators.delete(key);
        this.notify();
      },
    };
  }

  view(rootKey: string): SubagentTreeView {
    return {
      list: (options) => this.list(rootKey, options),
      get: (key) => this.list(rootKey).find((node) => node.key === key),
      size: () => this.list(rootKey).length,
      directKey: (id) =>
        this.list(rootKey).find(
          (node) => node.ownerKey === rootKey && node.snapshot.id === id,
        )?.key,
      subscribe: (listener) => this.subscribe(listener),
      subscribeTo: (_key, listener) => this.subscribe(listener),
      requestSend: (key, text) => {
        const node = this.list(rootKey).find((entry) => entry.key === key);
        if (node) node.ownerView.requestSend(node.snapshot.id, text);
      },
      requestAbort: (key) => {
        const node = this.list(rootKey).find((entry) => entry.key === key);
        if (node) node.ownerView.requestAbort(node.snapshot.id);
      },
    };
  }

  list(
    rootKey: string,
    options: SubagentTreeOptions = {},
  ): ReadonlyArray<SubagentTreeNode> {
    const drafts = this.buildCoordinator(rootKey, options, new Set());
    const nodes: SubagentTreeNode[] = [];
    this.flatten(drafts, nodes, 0, [], [], undefined);
    return nodes;
  }

  private buildCoordinator(
    key: string,
    options: SubagentTreeOptions,
    ancestors: ReadonlySet<string>,
  ): ReadonlyArray<TreeDraft> {
    if (ancestors.has(key)) return [];
    const registration = this.coordinators.get(key);
    if (!registration) return [];
    const nextAncestors = new Set(ancestors);
    nextAncestors.add(key);

    const drafts: TreeDraft[] = [];
    for (const snapshot of registration.view.list()) {
      if (options.modelOnly && snapshot.origin !== "model") continue;
      const childKey = childCoordinatorKey(snapshot);
      const children = childKey
        ? this.buildCoordinator(childKey, options, nextAncestors)
        : [];
      if (
        options.runningOnly &&
        snapshot.status !== "running" &&
        children.length === 0
      ) {
        continue;
      }
      drafts.push({
        ownerKey: key,
        snapshot,
        ownerView: registration.view,
        children,
      });
    }
    return drafts;
  }

  private flatten(
    drafts: ReadonlyArray<TreeDraft>,
    output: SubagentTreeNode[],
    depth: number,
    ancestorLast: ReadonlyArray<boolean>,
    idPath: ReadonlyArray<string>,
    parentKey: string | undefined,
  ): void {
    drafts.forEach((draft, index) => {
      const isLast = index === drafts.length - 1;
      const key = subagentTreeNodeKey(draft.ownerKey, draft.snapshot);
      const nextIdPath = [...idPath, draft.snapshot.id];
      output.push({
        key,
        ownerKey: draft.ownerKey,
        snapshot: draft.snapshot,
        ownerView: draft.ownerView,
        depth,
        parentKey,
        ancestorLast,
        isLast,
        idPath: nextIdPath,
      });
      this.flatten(
        draft.children,
        output,
        depth + 1,
        [...ancestorLast, isLast],
        nextIdPath,
        key,
      );
    });
  }

  private subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notify(): void {
    for (const listener of [...this.listeners]) {
      try {
        listener();
      } catch {
        // Rendering subscribers must not affect agent lifecycle state.
      }
    }
  }
}
