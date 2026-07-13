"use client";
import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { getCatalog, shorten } from "@/lib/catalog";
import { searchLabels } from "@/lib/labels";
import { CategoryDot } from "@/components/AddressLabel";

interface Result {
  kind: "role" | "address";
  href: string;
  primary: string;
  secondary: string;
  category?: string;
}

export function CommandSearch({ chainId, slug }: { chainId: number; slug: string }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const h = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setOpen((o) => !o);
      } else if (e.key === "Escape") {
        setOpen(false);
      }
    };
    window.addEventListener("keydown", h);
    return () => window.removeEventListener("keydown", h);
  }, []);

  useEffect(() => {
    if (open) setTimeout(() => inputRef.current?.focus(), 0);
    else setQ("");
  }, [open]);

  const results = useMemo<Result[]>(() => {
    const needle = q.trim().toLowerCase();
    if (!needle) return [];
    const roles: Result[] = (getCatalog(chainId)?.roles ?? [])
      .filter((r) => r.name.toLowerCase().includes(needle))
      .slice(0, 6)
      .map((r) => ({ kind: "role", href: `/${slug}/role/${r.id}`, primary: r.name, secondary: `role ${r.id}` }));
    const addrs: Result[] = searchLabels(chainId, needle, 8).map((l) => ({
      kind: "address",
      href: `/${slug}/address/${l.address}`,
      primary: l.name,
      secondary: shorten(l.address),
      category: l.category,
    }));
    return [...roles, ...addrs];
  }, [q, chainId, slug]);

  function go(href: string) {
    setOpen(false);
    router.push(href);
  }

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="flex items-center gap-2 rounded border border-border bg-panel px-2 py-1 text-sm text-muted hover:text-fg"
      >
        Search
        <kbd className="rounded bg-border px-1 text-[10px]">⌘K</kbd>
      </button>
      {open && (
        <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/50 pt-24" onClick={() => setOpen(false)}>
          <div className="w-full max-w-xl rounded-lg border border-border bg-panel" onClick={(e) => e.stopPropagation()}>
            <input
              ref={inputRef}
              value={q}
              onChange={(e) => setQ(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && results[0]) go(results[0].href);
              }}
              placeholder="Search roles, contracts, addresses…"
              className="w-full rounded-t-lg bg-transparent px-4 py-3 text-sm outline-none"
            />
            {results.length > 0 && (
              <ul className="max-h-80 overflow-y-auto border-t border-border">
                {results.map((r, i) => (
                  <li key={i}>
                    <button
                      onClick={() => go(r.href)}
                      className="flex w-full items-center gap-2 px-4 py-2 text-left text-sm hover:bg-border/40"
                    >
                      {r.kind === "address" ? <CategoryDot category={r.category ?? "external"} /> : <span className="text-muted">◆</span>}
                      <span>{r.primary}</span>
                      <span className="ml-auto font-mono text-[11px] text-muted">{r.secondary}</span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      )}
    </>
  );
}
