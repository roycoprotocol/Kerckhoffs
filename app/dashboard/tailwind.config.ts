import type { Config } from "tailwindcss";

// Design tokens from the royco.org design language (see app/docs/design-restyle-prompt.md and the
// claude.ai/design "Dashboard redesign mockup" project). Light, editorial, warm-cream.
export default {
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "#F3F1EB", // page background (warm cream)
        panel: "#FDFDFB", // card / surface
        border: "#E7E4DC", // outer hairline
        border2: "#ECE9E1", // inner row hairline
        fg: "#0F0E0D", // ink
        body: "#4B4A49", // secondary text
        muted: "#868584", // eyebrows, captions
        ok: "#16A34A", // brand green (Day identity, links, live)
        bronze: "#8A6F47", // Dawn identity
        high: "#C2402A", // warm red (veto / errors)
        med: "#B07D2B", // amber (migrating / countdowns)
        low: "#A6A5A3",
      },
      backgroundColor: {
        "ok-tint": "rgba(60,194,123,0.11)",
        "bronze-tint": "rgba(161,138,105,0.16)",
        "med-tint": "rgba(176,125,43,0.12)",
        "high-tint": "rgba(194,64,42,0.08)",
        "head-tint": "rgba(15,14,13,0.025)",
      },
      fontFamily: {
        serif: ["var(--font-serif)", "Georgia", "serif"],
        sans: ["var(--font-sans)", "Inter", "sans-serif"],
        mono: ["var(--font-mono)", "ui-monospace", "SFMono-Regular", "monospace"],
      },
      keyframes: {
        dotPulse: { "0%, 100%": { opacity: "0.4" }, "50%": { opacity: "1" } },
        scanPulse: { "0%, 100%": { opacity: "0.35" }, "50%": { opacity: "1" } },
        ping2: { "0%": { transform: "scale(1)", opacity: "0.5" }, "80%, 100%": { transform: "scale(2.8)", opacity: "0" } },
        gauntletDot: {
          "0%": { left: "2%", opacity: "0" },
          "4%": { opacity: "1" },
          "16%": { left: "20%" },
          "24%": { left: "20%" },
          "30%": { left: "34%" },
          "80%": { left: "80%" },
          "92%": { left: "97%", opacity: "1" },
          "96%": { left: "97%", opacity: "0" },
          "100%": { left: "97%", opacity: "0" },
        },
      },
      animation: {
        dotPulse: "dotPulse 2.4s ease-in-out infinite",
        scanPulse: "scanPulse 1.4s ease-in-out infinite",
        ping2: "ping2 2.2s cubic-bezier(0,0,0.2,1) infinite",
        gauntletDot: "gauntletDot 14s linear infinite",
      },
    },
  },
  plugins: [],
} satisfies Config;
