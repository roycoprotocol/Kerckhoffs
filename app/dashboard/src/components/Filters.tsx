"use client";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";

export interface SelectFilter {
  key: string;
  label: string;
  options: { value: string; label: string }[];
}

// URL-synced filter bar: a debounced search box + zero or more selects + optional toggles. Updates
// the querystring (shareable) via router.replace, preserving unrelated params.
export function Filters({
  searchKey = "q",
  searchPlaceholder = "Search…",
  selects = [],
  toggles = [],
}: {
  searchKey?: string;
  searchPlaceholder?: string;
  selects?: SelectFilter[];
  toggles?: { key: string; label: string }[];
}) {
  const router = useRouter();
  const pathname = usePathname();
  const sp = useSearchParams();

  const [text, setText] = useState(sp.get(searchKey) ?? "");
  useEffect(() => setText(sp.get(searchKey) ?? ""), [sp, searchKey]);

  function commit(next: URLSearchParams) {
    const qs = next.toString();
    router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false });
  }
  function setParam(key: string, value: string) {
    const next = new URLSearchParams(sp.toString());
    if (value) next.set(key, value);
    else next.delete(key);
    commit(next);
  }

  // debounce the text field
  useEffect(() => {
    const cur = sp.get(searchKey) ?? "";
    if (text === cur) return;
    const t = setTimeout(() => setParam(searchKey, text), 250);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [text]);

  const hasFilters = [...sp.keys()].length > 0;

  return (
    <div className="mb-4 flex flex-wrap items-center gap-2">
      <input
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder={searchPlaceholder}
        className="w-64 rounded border border-border bg-panel px-3 py-1.5 text-sm outline-none focus:border-muted"
      />
      {selects.map((s) => (
        <select
          key={s.key}
          value={sp.get(s.key) ?? ""}
          onChange={(e) => setParam(s.key, e.target.value)}
          className="rounded border border-border bg-panel px-2 py-1.5 text-sm"
        >
          <option value="">{s.label}: all</option>
          {s.options.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
      ))}
      {toggles.map((t) => {
        const on = sp.get(t.key) === "1";
        return (
          <button
            key={t.key}
            onClick={() => setParam(t.key, on ? "" : "1")}
            className={`rounded border px-2 py-1.5 text-sm ${on ? "border-ok text-ok" : "border-border text-muted hover:text-fg"}`}
          >
            {t.label}
          </button>
        );
      })}
      {hasFilters && (
        <button onClick={() => commit(new URLSearchParams())} className="px-2 py-1.5 text-sm text-muted hover:text-fg">
          clear
        </button>
      )}
    </div>
  );
}
