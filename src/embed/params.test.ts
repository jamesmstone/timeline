import { describe, expect, test } from "bun:test";
import { parseEmbedParams } from "./params";

const now = new Date("2026-10-12T12:00:00Z");
const hour = 60 * 60 * 1000;
const day = 24 * hour;

const parse = (query: string) =>
  parseEmbedParams(new URLSearchParams(query), now);

const ok = (query: string) => {
  const parsed = parse(query);
  if (!parsed.ok) throw new Error(parsed.error);
  return parsed.params;
};

const error = (query: string): string => {
  const parsed = parse(query);
  if (parsed.ok) throw new Error(`expected ${query} to be rejected`);
  return parsed.error;
};

describe("time range", () => {
  test("defaults to the week ending now", () => {
    const { start, end } = ok("");
    expect(end).toEqual(now);
    expect(start).toEqual(new Date(now.getTime() - 7 * day));
  });

  test("the captain's snippet asks for the default week", () => {
    expect(ok("end=now&duration=1w")).toEqual(ok(""));
  });

  test("start and end win over duration", () => {
    const { start, end } = ok(
      "start=2026-10-01&end=2026-10-03T06:00:00Z&duration=1h",
    );
    expect(start).toEqual(new Date("2026-10-01T00:00:00Z"));
    expect(end).toEqual(new Date("2026-10-03T06:00:00Z"));
  });

  test("end with a duration reaches back from end", () => {
    const { start, end } = ok("end=2026-10-05T00:00:00Z&duration=36h");
    expect(end).toEqual(new Date("2026-10-05T00:00:00Z"));
    expect(start).toEqual(new Date("2026-10-03T12:00:00Z"));
  });

  test("start with a duration reaches forward from start", () => {
    const { start, end } = ok("start=2026-09-01T00:00:00Z&duration=2w");
    expect(start).toEqual(new Date("2026-09-01T00:00:00Z"));
    expect(end).toEqual(new Date("2026-09-15T00:00:00Z"));
  });

  test("a lone start or end spans the default week", () => {
    expect(ok("start=2026-09-01").end).toEqual(
      new Date("2026-09-08T00:00:00Z"),
    );
    expect(ok("end=2026-09-08").start).toEqual(
      new Date("2026-09-01T00:00:00Z"),
    );
  });

  test("a lone duration ends now", () => {
    const { start, end } = ok("duration=30d");
    expect(end).toEqual(now);
    expect(start).toEqual(new Date(now.getTime() - 30 * day));
  });

  test("now is case-insensitive and offsets are honoured", () => {
    expect(ok("end=NOW").end).toEqual(now);
    expect(ok("start=2026-10-01T02:00:00%2B02:00&end=now").start).toEqual(
      new Date("2026-10-01T00:00:00Z"),
    );
  });

  test("an offset's + may be left unencoded", () => {
    expect(ok("start=2026-10-01T02:00:00+02:00&end=now").start).toEqual(
      new Date("2026-10-01T00:00:00Z"),
    );
    expect(ok("start=2026-10-01T02:00:00+0200&end=now").start).toEqual(
      new Date("2026-10-01T00:00:00Z"),
    );
  });

  test("an empty parameter is the same as a missing one", () => {
    expect(ok("start=&end=&duration=")).toEqual(ok(""));
  });

  test.each([
    ["start=yesterday", "start must be an ISO 8601"],
    ["end=2026-13-01", "end must be an ISO 8601"],
    ["duration=1y", "duration must be a number"],
    ["duration=-1d", "duration must be a number"],
    ["duration=0h", "duration must be more than zero"],
    ["start=2026-10-02&end=2026-10-01", "start must be before end"],
    ["duration=0.5h", "at least 1h"],
    ["start=2000-01-01&end=2026-01-01", "at most 5 years"],
  ])("rejects %s", (query, message) => {
    expect(error(query)).toContain(message);
  });
});

describe("canvas", () => {
  test("defaults to a wide horizontal chart", () => {
    const { width, height, layout } = ok("");
    expect({ width, height, layout }).toEqual({
      width: 1200,
      height: 520,
      layout: "horizontal",
    });
  });

  test("maxWidth from the captain's snippet gives a narrow vertical chart", () => {
    const { width, height, layout } = ok("maxWidth=600px&end=now&duration=1w");
    expect({ width, height, layout }).toEqual({
      width: 600,
      height: 900,
      layout: "vertical",
    });
  });

  test("maxWidth caps an explicit width", () => {
    expect(ok("width=900&maxWidth=700").width).toBe(700);
    expect(ok("width=500&maxWidth=700").width).toBe(500);
  });

  test("auto layout follows the requested aspect ratio", () => {
    expect(ok("width=800&height=1200").layout).toBe("vertical");
    expect(ok("width=500&height=300").layout).toBe("horizontal");
    expect(ok("layout=auto&width=500").layout).toBe("vertical");
  });

  test("an explicit layout wins over the aspect ratio", () => {
    expect(ok("width=500&layout=horizontal").layout).toBe("horizontal");
    expect(ok("width=1200&height=400&layout=Vertical").layout).toBe("vertical");
  });

  test("sizes are clamped rather than rejected", () => {
    expect(ok("width=10&height=99999")).toMatchObject({
      width: 200,
      height: 2400,
    });
    expect(ok("width=640.6px").width).toBe(641);
  });

  test("theme is not a parameter", () => {
    expect(ok("theme=dark")).toEqual(ok(""));
  });

  test.each([
    ["width=wide", "width must be a number"],
    ["height=-5", "height must be a number"],
    ["maxWidth=50%25", "maxWidth must be a number"],
    ["layout=diagonal", "layout must be one of"],
  ])("rejects %s", (query, message) => {
    expect(error(query)).toContain(message);
  });
});
