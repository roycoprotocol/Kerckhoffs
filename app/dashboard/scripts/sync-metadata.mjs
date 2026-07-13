#!/usr/bin/env node
// Copy the generated catalog metadata (app/metadata) into the dashboard tree so it can be imported
// statically and bundled — robust across local dev and Vercel. Re-run whenever the catalog changes.
import { readdirSync, mkdirSync, copyFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const src = join(here, "..", "..", "metadata");
const dst = join(here, "..", "src", "metadata");
mkdirSync(dst, { recursive: true });

let n = 0;
for (const f of readdirSync(src)) {
  if (!f.endsWith(".json")) continue;
  copyFileSync(join(src, f), join(dst, f));
  n++;
}
console.log(`[sync-metadata] copied ${n} json files -> src/metadata/`);
