import { Group } from "../data";
import { Theme } from "./params";

type Palette = {
  surface: string;
  ink: string;
  inkMuted: string;
  inkFaint: string;
  hairline: string;
  hairlineStrong: string;
  pillInk: string;
  pillInkLow: string;
  now: string;
  accents: Record<Group, [high: string, low: string]>;
};

// Mirrors the tokens in styles.css. The embed spells colours out per theme
// rather than using custom properties, which some SVG rasterisers ignore.
const light: Palette = {
  surface: "#ffffff",
  ink: "#0f172a",
  inkMuted: "#5b6b7c",
  inkFaint: "#94a3b8",
  hairline: "#e6eaf1",
  hairlineStrong: "#d3dae5",
  pillInk: "#ffffff",
  pillInkLow: "#0f172a",
  now: "#e11d48",
  accents: {
    "Heart rate": ["#e11d48", "#fb7185"],
    "Stress level": ["#c2410c", "#fbbf24"],
    Sleep: ["#4338ca", "#818cf8"],
    Steps: ["#075985", "#38bdf8"],
    Music: ["#6d28d9", "#a78bfa"],
    Family: ["#15803d", "#4ade80"],
    Read: ["#0f766e", "#2dd4bf"],
  },
};

const dark: Palette = {
  surface: "#0b111c",
  ink: "#eef2f8",
  inkMuted: "#8b98ab",
  inkFaint: "#5a6678",
  hairline: "#1c2433",
  hairlineStrong: "#2b3549",
  pillInk: "#050a12",
  pillInkLow: "#050a12",
  now: "#fb7185",
  accents: {
    "Heart rate": ["#fb7185", "#fda4af"],
    "Stress level": ["#fb923c", "#fde047"],
    Sleep: ["#818cf8", "#a5b4fc"],
    Steps: ["#38bdf8", "#7dd3fc"],
    Music: ["#c084fc", "#d8b4fe"],
    Family: ["#4ade80", "#86efac"],
    Read: ["#2dd4bf", "#5eead4"],
  },
};

export const groupClass = (group: Group): string =>
  "g-" + group.toLowerCase().replace(/[^a-z]+/g, "-");

const rules = (p: Palette): string =>
  [
    `.card{fill:${p.surface};stroke:${p.hairline}}`,
    `.ink{fill:${p.ink}}`,
    `.muted{fill:${p.inkMuted}}`,
    `.faint{fill:${p.inkFaint}}`,
    `.grid{stroke:${p.hairline}}`,
    `.grid-major{stroke:${p.hairlineStrong}}`,
    `.now{stroke:${p.now}}`,
    `.pill-ink{fill:${p.pillInk}}`,
    `.pill-ink-low{fill:${p.pillInkLow}}`,
    `.span{stroke-opacity:.45;fill-opacity:.14}`,
    ...Object.entries(p.accents).map(
      ([group, [high, low]]) =>
        `.${groupClass(group as Group)}{fill:${high};stroke:${high}}` +
        `.${groupClass(group as Group)} stop{stop-color:${high}}` +
        `.${groupClass(group as Group)} .low{fill:${low};stop-color:${low}}`,
    ),
  ].join("");

export const stylesheet = (theme: Theme): string =>
  [
    `text{font-family:ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;stroke:none}`,
    theme === "dark" ? rules(dark) : rules(light),
    theme === "auto"
      ? `@media (prefers-color-scheme:dark){${rules(dark)}}`
      : "",
  ].join("");
