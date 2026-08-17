"use client";
// The Search page body: one large input over the same result set as the ⌘K palette — roles on
// either AM, labeled contracts, and any pasted address (the address page renders arbitrary
// contracts' state).
import { useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { buildSearchResults, type SearchResult } from "@/lib/search";
import { CategoryDot } from "@/components/AddressLabel";

export function SearchPanel({ chainId, slug }: { chainId: number; slug: string }) {
  const router = useRouter();
  const [q, setQ] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);
  const results = useMemo<SearchResult[]>(() => buildSearchResults(chainId, slug, q, 12), [q, chainId, slug]);

  return (
    <div className="mx-auto mt-10 max-w-2xl">
      <input
        ref={inputRef}
        autoFocus
        value={q}
        onChange={(e) => setQ(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter" && results[0]) router.push(results[0].href);
        }}
        placeholder="Search a role, contract name, or paste any address…"
        className="w-full rounded-xl border border-border bg-panel px-5 py-4 text-[15px] shadow-[0_4px_16px_rgba(15,14,13,0.04)] outline-none focus:border-[#D9D5C9]"
      />
      {q.trim() === "" ? (
        <p className="mt-4 text-center text-[13px] text-muted">
          Look up the live state of anything the access managers govern — a role (try “ORACLE” or a
          role id), a labeled contract (“kernel”, “entry point”), or any raw 0x address.
        </p>
      ) : results.length === 0 ? (
        <p className="mt-4 text-center text-[13px] text-muted">No matches.</p>
      ) : (
        <ul className="mt-4 overflow-hidden rounded-xl border border-border bg-panel">
          {results.map((r, i) => (
            <li key={i} className={i > 0 ? "border-t border-border2" : ""}>
              <button
                onClick={() => router.push(r.href)}
                className="flex w-full items-center gap-3 px-4 py-3 text-left text-sm hover:bg-ok-tint"
              >
                {r.kind === "address" ? (
                  <CategoryDot category={r.category ?? "external"} />
                ) : (
                  <span className="text-muted">◆</span>
                )}
                <span className="font-medium">{r.primary}</span>
                <span className="ml-auto font-mono text-[11px] text-muted">{r.secondary}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
