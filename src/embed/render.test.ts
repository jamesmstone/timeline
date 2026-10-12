import { describe, expect, test } from "bun:test";
import { XMLParser, XMLValidator } from "fast-xml-parser";
import { groups } from "../data";
import { lanes, now, range } from "./fixtures";
import { EmbedParams } from "./params";
import { renderEmbed } from "./render";

const params = (overrides: Partial<EmbedParams> = {}): EmbedParams => ({
  ...range,
  width: 1200,
  height: 520,
  layout: "horizontal",
  ...overrides,
});

const layouts: [string, Partial<EmbedParams>][] = [
  ["horizontal", {}],
  ["vertical", { width: 600, height: 900, layout: "vertical" }],
  ["tiny horizontal", { width: 200, height: 200 }],
  ["tiny vertical", { width: 200, height: 200, layout: "vertical" }],
];

const root = (svg: string) =>
  new XMLParser({ ignoreAttributes: false, attributeNamePrefix: "" }).parse(svg)
    .svg;

describe.each(layouts)("%s", (_, overrides) => {
  const svg = renderEmbed(lanes, params(overrides), now);

  test("is well-formed XML", () => {
    expect(XMLValidator.validate(svg)).toBe(true);
  });

  test("is sized to the request", () => {
    const { width, height } = params(overrides);
    const { width: w, height: h, viewBox } = root(svg);
    expect([w, h, viewBox]).toEqual([
      String(width),
      String(height),
      `0 0 ${width} ${height}`,
    ]);
  });

  test("is an accessible image", () => {
    const svgRoot = root(svg);
    expect(svgRoot.role).toBe("img");
    expect(svgRoot.title["#text"]).toContain("Timeline");
    expect(svgRoot.desc["#text"]).toContain("Steps is unavailable");
  });

  test("carries no script and escapes source text", () => {
    expect(svg).not.toMatch(/<script/i);
    expect(svg).not.toContain("<b>");
    expect(svg).not.toContain("\u0001");
  });
});

test("labels a span with its escaped source text", () => {
  const svg = renderEmbed(lanes, params(), now);
  expect(svg).toContain("&lt;/text&gt;&lt;script&gt;");
});

test("marks a lane whose sources failed", () => {
  expect(renderEmbed(lanes, params(), now)).toContain(">Unavailable<");
});

test("summarises the peaks it draws", () => {
  const { desc } = root(renderEmbed(lanes, params(), now));
  expect(desc["#text"]).toContain("Heart rate peaked at 70");
  expect(desc["#text"]).toContain("dipped to 63");
});

test("says how many stacked items it had no room for", () => {
  expect(renderEmbed(lanes, params(), now)).toMatch(/\+\d+ more/);
});

const distinct = (values: number[]) => new Set(values).size === values.length;
const same = (values: number[]) => new Set(values).size === 1;

const layout = (overrides: Partial<EmbedParams>) => {
  const svg = root(renderEmbed(lanes, params(overrides), now));
  const pills = (svg.g as { class: string; rect: unknown }[])
    .filter((g) => g.class.startsWith("g-"))
    .map((g) => [g.rect].flat()[0] as { x: string; y: string })
    .map(({ x, y }) => ({ x: Number(x), y: Number(y) }));
  const ticks = (svg.text as { "#text": string; x: string; y: string }[])
    .filter((t) => /^\w{3} \d+$/.test(t["#text"]))
    .map(({ x, y }) => ({ x: Number(x), y: Number(y) }));
  return { pills, ticks };
};

test("stacks a horizontal chart's lanes down the page, time across", () => {
  const { pills, ticks } = layout({});
  expect(pills).toHaveLength(groups.length);
  expect(same(pills.map((p) => p.x)) && distinct(pills.map((p) => p.y))).toBe(
    true,
  );
  expect(ticks.length).toBeGreaterThan(2);
  expect(same(ticks.map((t) => t.y)) && distinct(ticks.map((t) => t.x))).toBe(
    true,
  );
});

test("lays a vertical chart's lanes across the page, time down", () => {
  const { pills, ticks } = layout({
    width: 600,
    height: 900,
    layout: "vertical",
  });
  expect(pills).toHaveLength(groups.length);
  expect(same(pills.map((p) => p.y)) && distinct(pills.map((p) => p.x))).toBe(
    true,
  );
  expect(ticks.length).toBeGreaterThan(2);
  expect(same(ticks.map((t) => t.x)) && distinct(ticks.map((t) => t.y))).toBe(
    true,
  );
});

test("is light unless the reader's colour scheme is dark", () => {
  const style = root(renderEmbed(lanes, params(), now)).style as string;
  const [base, dark] = style.split("@media (prefers-color-scheme:dark)");
  expect(base).toContain(".card{fill:#ffffff");
  expect(dark).toContain(".card{fill:#0b111c");
});

test("draws an empty week without failing", () => {
  const empty = lanes.map(({ group }) => ({
    group,
    result: { type: "timeline" as const, data: [] },
  }));
  expect(XMLValidator.validate(renderEmbed(empty, params(), now))).toBe(true);
});
