import { describe, expect, test } from "bun:test";
import { XMLValidator } from "fast-xml-parser";
import { lanes } from "./fixtures";
import { createEmbedHandler } from "./handler";

const now = new Date("2026-10-12T12:34:56.789Z");

const setup = () => {
  const requested: { start: Date; end: Date }[] = [];
  const handler = createEmbedHandler({
    load: async (range) => {
      requested.push(range);
      return lanes;
    },
    now: () => now,
  });
  const get = (path: string, method = "GET") =>
    handler(new Request(`https://timeline.jamesst.one${path}`, { method }));
  return { requested, get };
};

describe("GET /embed.svg", () => {
  test("serves a cacheable, cross-origin SVG", async () => {
    const response = await setup().get("/embed.svg?end=now&duration=1w");
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe(
      "image/svg+xml; charset=utf-8",
    );
    expect(response.headers.get("access-control-allow-origin")).toBe("*");
    expect(response.headers.get("cache-control")).toBe(
      "public, max-age=60, s-maxage=300",
    );
    expect(response.headers.get("content-security-policy")).toContain(
      "default-src 'none'",
    );
    expect(XMLValidator.validate(await response.text())).toBe(true);
  });

  test("loads the requested range with now rounded to the minute", async () => {
    const { requested, get } = setup();
    await get("/embed.svg?duration=24h");
    expect(requested).toEqual([
      {
        start: new Date("2026-10-11T12:34:00Z"),
        end: new Date("2026-10-12T12:34:00Z"),
      },
    ]);
  });

  test("serves both sources of the captain's <picture>", async () => {
    const { get } = setup();
    const narrow = await (
      await get("/embed.svg?maxWidth=600px&end=now&duration=1w")
    ).text();
    const wide = await (await get("/embed.svg?end=now&duration=1w")).text();
    expect(narrow).toContain('width="600"');
    expect(wide).toContain('width="1200"');
  });

  test("answers bad parameters with a 400 image naming the problem", async () => {
    const { requested, get } = setup();
    const response = await get("/embed.svg?duration=forever");
    expect(response.status).toBe(400);
    expect(response.headers.get("content-type")).toBe(
      "image/svg+xml; charset=utf-8",
    );
    const body = await response.text();
    expect(XMLValidator.validate(body)).toBe(true);
    expect(body).toContain("duration must be");
    expect(requested).toEqual([]);
  });

  test("HEAD carries the headers without the body", async () => {
    const response = await setup().get("/embed.svg", "HEAD");
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("image/svg+xml");
    expect(await response.text()).toBe("");
  });
});

test("answers a CORS preflight", async () => {
  const response = await setup().get("/embed.svg", "OPTIONS");
  expect(response.status).toBe(204);
  expect(response.headers.get("access-control-allow-origin")).toBe("*");
});

test("refuses other methods", async () => {
  const response = await setup().get("/embed.svg", "POST");
  expect(response.status).toBe(405);
  expect(response.headers.get("allow")).toBe("GET, HEAD, OPTIONS");
});

test("serves nothing else", async () => {
  expect((await setup().get("/")).status).toBe(404);
  expect((await setup().get("/embed.png")).status).toBe(404);
});
