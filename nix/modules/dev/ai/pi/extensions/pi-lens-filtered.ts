import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type ExtensionFactory = (pi: ExtensionAPI) => void | Promise<void>;

/**
 * Load Pi Lens without its bundled skills.
 *
 * Pi's package filter disables the manifest-provided skills, but Pi Lens also
 * adds the same directory dynamically through resources_discover. Proxying the
 * API keeps the extension, tools, diagnostics, and LSP behavior intact while
 * suppressing only that second skill-registration path.
 */
export default async function piLensFiltered(pi: ExtensionAPI): Promise<void> {
	const agentDir = process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent");
	const entry = join(agentDir, "npm", "node_modules", "pi-lens", "dist", "index.js");
	const module = (await import(pathToFileURL(entry).href)) as { default?: ExtensionFactory };

	if (typeof module.default !== "function") {
		throw new Error(`Pi Lens does not export an extension factory: ${entry}`);
	}

	const filteredApi = new Proxy(pi, {
		get(target, property, receiver) {
			if (property === "on") {
				return (event: string, handler: unknown) => {
					if (event === "resources_discover") return;
					return (target.on as (...args: unknown[]) => unknown)(event, handler);
				};
			}

			const value = Reflect.get(target, property, receiver) as unknown;
			return typeof value === "function" ? value.bind(target) : value;
		},
	});

	await module.default(filteredApi);
}
