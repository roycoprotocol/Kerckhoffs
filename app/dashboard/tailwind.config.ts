import type { Config } from "tailwindcss";

export default {
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "#0b0e14",
        panel: "#141922",
        border: "#232a36",
        muted: "#8b95a7",
        fg: "#e6e9ef",
        high: "#ff5c5c",
        med: "#f5a623",
        low: "#6b7688",
        ok: "#3ecf8e",
      },
      fontFamily: {
        mono: ["ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
      },
    },
  },
  plugins: [],
} satisfies Config;
