import { describe, expect, test } from "bun:test";
import { XMLParser, XMLValidator } from "fast-xml-parser";
import { lanes, now, range } from "./fixtures";
import { EmbedParams } from "./params";
import { renderEmbed } from "./render";

const params = (overrides: Partial<EmbedParams> = {}): EmbedParams => ({
  ...range,
  width: 1200,
  height: 520,
  layout: "horizontal",
  theme: "light",
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

test("lays a vertical chart out down the page, not stretched", () => {
  const horizontal = renderEmbed(lanes, params(), now);
  const vertical = renderEmbed(
    lanes,
    params({ width: 600, height: 900, layout: "vertical" }),
    now,
  );
  expect(horizontal).toContain("rotate(-90");
  expect(vertical).not.toContain("rotate(-90");
});

test("follows the reader's colour scheme only when asked", () => {
  expect(renderEmbed(lanes, params(), now)).not.toContain("@media");
  expect(renderEmbed(lanes, params({ theme: "auto" }), now)).toContain(
    "@media (prefers-color-scheme:dark)",
  );
  expect(renderEmbed(lanes, params({ theme: "dark" }), now)).toContain(
    ".card{fill:#0b111c",
  );
});

test("draws an empty week without failing", () => {
  const empty = lanes.map(({ group }) => ({
    group,
    result: { type: "timeline" as const, data: [] },
  }));
  expect(XMLValidator.validate(renderEmbed(empty, params(), now))).toBe(true);
});
