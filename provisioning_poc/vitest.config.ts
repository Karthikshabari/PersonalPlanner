import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [{
    name: "planner-sql-text",
    enforce: "pre",
    transform(source, id) {
      return id.endsWith(".sql") ? { code: `export default ${JSON.stringify(source)};`, map: null } : null;
    },
  }],
  resolve: {
    alias: {
      "cloudflare:workers": fileURLToPath(new URL("./test/cloudflare-workers.ts", import.meta.url)),
    },
  },
  test: { environment: "node" },
});
