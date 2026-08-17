"use client";
import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { buildSearchResults, type SearchResult } from "@/lib/search";
import { CategoryDot } from "@/components/AddressLabel";

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

  const results = useMemo<SearchResult[]>(() => buildSearchResults(chainId, slug, q), [q, chainId, slug]);

  function go(href: string) {
    setOpen(false);
    router.push(href);
  }

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="flex items-center gap-2.5 rounded-md border border-border bg-panel px-3 py-1.5 text-xs text-muted hover:border-[#D9D5C9] hover:text-fg"
      >
        Search
        <kbd className="rounded border border-border2 px-1.5 py-px font-mono text-[10px]">⌘K</kbd>
      </button>
      {open && (
        <div className="fixed inset-0 z-50 flex items-start justify-center bg-[rgba(15,14,13,0.25)] pt-[14vh]" onClick={() => setOpen(false)}>
          <div className="w-full max-w-xl overflow-hidden rounded-xl border border-border bg-panel shadow-[0_12px_40px_rgba(15,14,13,0.08)]" onClick={(e) => e.stopPropagation()}>
            <input
              ref={inputRef}
              value={q}
              onChange={(e) => setQ(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && results[0]) go(results[0].href);
              }}
              placeholder="Search roles, contracts, addresses…"
              className="w-full border-b border-border2 bg-transparent px-4 py-3.5 text-sm outline-none"
            />
            {results.length > 0 && (
              <ul className="max-h-80 overflow-y-auto p-2">
                {results.map((r, i) => (
                  <li key={i}>
                    <button
                      onClick={() => go(r.href)}
                      className="flex w-full items-center gap-2.5 rounded-md px-2.5 py-2 text-left text-sm hover:bg-ok-tint"
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
