# Restyle the Royco Access Control dashboard to the royco.org design language

You are restyling an existing, working Next.js dashboard. This is a **visual-only** pass: do not
change routes, data fetching, page structure, or any logic — only Tailwind config, global CSS,
fonts, and classNames/markup inside components. The app must remain information-dense and
scannable; it is a security monitoring tool used daily by engineers.

## 1. The app you are restyling

Location: `app/dashboard` (Next.js 15 App Router, React 19, Tailwind 3, all pages are server
components; three client components: `Nav.tsx`, `Filters.tsx`, `CommandSearch.tsx`).

Run it: `npm run dev` in `app/dashboard` (dev server on :3000; subgraph endpoints are configured
in `.env.local` and already running). Verify every page listed below after restyling.

### Routes / pages

- `/[chain]/markets/dawn` and `/[chain]/markets/day` — market listings. One panel per market:
  header row (market name, controlling-AM badge, deploy time + deployer on the right), then a
  3-column table of components (component type / contract label / address).
- `/[chain]/vaults` — one panel per vault stack (name + "Concrete vault"/"Makina stack" caption +
  AM badge; table of contracts; optional "Makina governance slots" footer list).
- `/[chain]/am/[am]` — AccessManager section. Section header strip (AM label + badge + manager
  name + monospace address), sub-nav (Roles | Functions | Pending ops), then:
  - Roles index: 7-column table (role, holders, admin, guardian, grant delay, gated fns).
  - `/role/[id]` detail: config panel + holders table + gated-functions table + history table.
  - `/functions`: one panel per target contract with (function, selector, gated-by-role) rows.
  - `/operations`: pending timelocked operations table.
- `/[chain]/contracts` — Directory: panels per category (Control plane, Multisigs, Markets,
  Vaults, …) with nested parent→children groups and address rows.
- `/[chain]/address/[addr]` — address detail: roles held per AM + gated-target panels per AM.
- `/diff` — multi-chain matrix, one table per AM (roles × chains), its own standalone header.
- Top chrome (`[chain]/layout.tsx`): header ("Royco Access Control" wordmark, ⌘K search button,
  chain switcher `<select>`), primary nav tabs (Dawn Markets | Day Markets | Vaults | Dawn AM |
  Day AM, with Directory and Multi-chain diff right-aligned).

### Files that carry the styling

- `tailwind.config.ts` — theme tokens (see current palette below).
- `src/app/globals.css` — base styles (`color-scheme: dark` today).
- `src/app/layout.tsx` — root layout (add `next/font` here).
- `src/components/ui.tsx` — `Panel`, `PageTitle` (title + subtitle), `Table/Th/Td`, `Mono`,
  `AmBadge` (dawn | day | migrating | unknown), `RoleLink`, `AccountLink`, `Empty`,
  `SubgraphMissing`, `SeverityPill` (mostly unused now).
- `src/components/Nav.tsx` — `Nav` (primary tabs), `AmSubNav` (secondary tabs), `ChainSwitcher`.
- `src/components/AddressLabel.tsx` — `AddressLabel`, `CategoryBadge`, `CategoryDot`,
  `categoryColor` (per-category hue map).
- `src/components/Filters.tsx` — URL-synced search input + `<select>` filters + toggle chips.
- `src/components/CommandSearch.tsx` — ⌘K modal palette.
- Page files under `src/app/` use these components plus utility classes
  (`text-muted`, `border-border`, `bg-panel`, `text-ok`, `text-[11px]`, etc.).

### Current look (what you are replacing)

Dark theme, generic "ops dashboard": bg `#0b0e14`, panels `#141922`, borders `#232a36`, text
`#e6e9ef`, muted `#8b95a7`, green `#3ecf8e`, system font stack, system monospace, 2xl-rounded
panels, green underline on active tabs, indigo/teal/amber AM badges.

## 2. Target design language — royco.org/security (measured, exact)

The dashboard must look like a sibling page of https://www.royco.org/security — light, editorial,
precise. Tokens extracted from the live site:

### Color

| Token | Value | Use |
|---|---|---|
| page background | `#F3F1EB` (warm cream) | body |
| surface | `#FDFDFB` (near-white) | cards/panels, header, inputs |
| ink | `#0F0E0D` | headlines, primary text |
| body text | `#4B4A49` | secondary text |
| muted | `#868584` | eyebrows, captions, deemphasized cells |
| accent green | `#16A34A` | links, emphasis words, active states |
| green tint | `rgba(60,194,123,0.11)` | pill backgrounds behind green text |
| hairline | a warm gray in the `#E5E2DA`–`#EAE7DF` range | all borders/dividers (1px) |
| bronze/tan | sampled from the site's "Launch app" button, ~`#A18A69` | primary-action accents, Dawn identity |

No pure white, no pure black, no cool grays anywhere.

### Type

| Role | Font | Treatment |
|---|---|---|
| Display / page titles | **Shippori Mincho B1** (Google font), weight 600 | serif; large (site uses 52/57 for hero — use ~28–32px for dashboard page titles); one word may be green for emphasis |
| UI / body / tables | **Inter**, weight 500 (600 for table headers/emphasis) | 15px table cells on the site; 13–14px is fine for dense tables |
| Mono (addresses, ids, selectors, stats, eyebrows) | **Fragment Mono** (Google font), 400 | eyebrow labels: 11–12px, uppercase, letter-spacing ~0.1em, muted color; big stat numbers: 28px |

Load all three with `next/font/google` in `src/app/layout.tsx` and expose as Tailwind families
(`font-serif`, `font-sans`, `font-mono`).

### Signature patterns to adopt

1. **Eyebrow labels**: every page gets a mono, uppercase, letter-spaced, muted eyebrow above the
   serif title (e.g. `MARKETS · ETHEREUM` above "Dawn Markets."). Section numbers (`01`, `02`)
   right-aligned are on-brand where a page has multiple sections.
2. **Serif titles ending with a period**: "Dawn Markets.", "Roles.", "Pending operations." —
   matches "Security you can verify." / "Eight layers of defense."
3. **Hairline tables on cream**: table header row = mono or Inter-600 11–12px uppercase muted on
   a very subtle tinted band (like the site's audit table), 1px hairline row separators, roomy
   row height, first column ink-colored and weightier, secondary columns `#4B4A49`/muted.
4. **Green tint pills**: small actions/links inside tables (like the site's "View ↗") are 12px,
   green text on `rgba(60,194,123,0.11)`, 6px radius. Use this treatment for role links and
   in-table actions.
5. **Cards**: `#FDFDFB` surface, 1px hairline border, **12px radius**, no shadows (or a barely
   perceptible one). The site's chrome (nav pill) is the same surface + radius.
6. **Stats row** (optional but on-brand): a hairline-separated row of mono eyebrow + big Fragment
   Mono number, like the site's `BUG BOUNTY / $250K · AUDITS / 15`. Good fit for page subtitles
   that are currently plain text ("23 markets · 92 contracts", "19 configured roles",
   "indexed block 25753196") — consider rendering these as small stat clusters.
7. **Generous whitespace** between sections; content max-width ~1100–1200px centered.

## 3. Specific restyling directives

- **Theme flip**: dark → light. Update `tailwind.config.ts` tokens and `globals.css`
  (`color-scheme: light`). Map existing token names rather than renaming classes everywhere:
  `bg→#F3F1EB`, `panel→#FDFDFB`, `border→hairline`, `fg→#0F0E0D`, `muted→#868584`,
  `ok→#16A34A`. Keep `high/med/low` for the rare error/status text but recolor to fit
  (high `#C2402A`-ish warm red, med amber `#B07D2B`-ish, low = muted).
- **Header**: keep one top bar on the cream background — wordmark "Royco **Access Control**"
  (wordmark in Inter 600 ink; consider "ROYCO" in the site's spaced-caps style), search button
  and chain switcher as surface-colored bordered controls (6px radius).
- **Primary nav tabs**: replace the green-underline dark tabs with the site's quiet nav-link
  style — Inter 13px, muted at rest, ink when active, with either a subtle underline or a
  surface pill for the active tab. Keep Directory/diff right-aligned and visually secondary.
- **AM badges** (`AmBadge` in `ui.tsx`) — re-key the identity colors to the new language:
  - `dawn` → bronze/tan: tan text on a warm tan tint (echoes the site's Launch-app brown).
  - `day` → green: `#16A34A` on the green tint — "day" owns the brand green.
  - `migrating` → amber tint; `unknown` → muted hairline outline, no fill.
  Badge shape: 11px Inter 500 (or Fragment Mono 10px uppercase), 6px radius, tinted bg, no border.
- **Category colors** (`AddressLabel.tsx` `categoryColor`/`CategoryBadge`/`CategoryDot`): mute
  the rainbow — dots stay small and desaturated; badges become tinted pills in the new palette
  (greens/bronzes/warm grays only).
- **Addresses/selectors/ids**: Fragment Mono, muted, 12–13px everywhere (`Mono` component).
- **Filters**: search input + selects become surface-on-cream bordered controls, 6px radius,
  Inter 13px; focus ring = green.
- **⌘K palette**: light surface modal, hairline border, 12px radius, subtle overlay
  (`rgba(15,14,13,0.25)`), rows highlight with the green tint.
- **Empty states / errors** (`Empty`, `SubgraphMissing`): centered muted Inter on a dashed or
  hairline panel — keep them quiet, not alarming.
- **/diff matrix**: divergent cells currently use a red tint — restyle to a soft warm-red tint
  (`rgba(194,64,42,0.08)`) with ink text; "n/a" cells stay near-invisible muted.
- **Do not** introduce component libraries, CSS-in-JS, or shadcn; stay with Tailwind utilities
  and the existing component files.
- **Do not** change any copy except where a directive above says so (title punctuation/eyebrows).

## 4. Acceptance checklist

1. `npm run typecheck` and `npm run build` pass in `app/dashboard`.
2. Every route in §1 renders correctly at desktop width (≥1280px) and holds up at ~900px.
3. Screenshot side-by-side with https://www.royco.org/security: same background, same fonts,
   same table voice, same green — a person seeing both should assume the same design team.
4. Density check: the Dawn Markets page (23 markets) and the roles table (19 rows × 7 cols) must
   remain comfortably scannable — the editorial style must not cost information density.
5. Contrast: all text ≥ WCAG AA against its background (muted `#868584` on `#F3F1EB` is the
   floor — do not go lighter).
