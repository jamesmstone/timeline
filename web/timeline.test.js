import { describe, expect, test } from "bun:test";
import pan from "./timeline.js";

describe("panning", () => {
  test("dragging right reveals earlier time", () => {
    expect(pan.panned(1000, 100, 1000, 500)).toBe(950);
    expect(pan.panned(1000, -200, 1000, 500)).toBe(1100);
  });

  test("a window spans one viewport either side of the view", () => {
    expect(pan.windowFor(1000, 100)).toEqual({ from: 900, to: 1200 });
  });

  test("the view maps into the middle third of a fresh window", () => {
    const { from } = pan.windowFor(1000, 100);
    expect(pan.viewBoxX(1000, from, 1200, 100)).toBe(1200);
  });

  test("a window is refetched only near its edge", () => {
    const { from, to } = pan.windowFor(1000, 100);
    expect(pan.needsWindow(1000, 100, from, to)).toBe(false);
    expect(pan.needsWindow(1000 - 70, 100, from, to)).toBe(false);
    expect(pan.needsWindow(1000 - 76, 100, from, to)).toBe(true);
    expect(pan.needsWindow(1000 + 76, 100, from, to)).toBe(true);
  });
});

describe("zooming", () => {
  test("the instant under the cursor stays put", () => {
    const before = 1000 + 0.25 * 40000;
    const z = pan.zoomed(1000, 40000, 0.25, 0.5);
    expect(z.span).toBe(20000);
    expect(z.vstart + 0.25 * z.span).toBe(before);
  });

  test("span is clamped", () => {
    expect(pan.zoomed(0, pan.MIN_SPAN, 0.5, 0.1).span).toBe(pan.MIN_SPAN);
    expect(pan.zoomed(0, pan.MAX_SPAN, 0.5, 10).span).toBe(pan.MAX_SPAN);
  });
});

describe("urls", () => {
  test("the svg request carries the window, view and width", () => {
    expect(pan.svgUrl({ vstart: 1000, span: 100, w: 800 })).toBe(
      "/lanes.svg?from=900&to=1200&span=100&at=1000&w=800",
    );
  });

  test("the page url is shareable", () => {
    expect(pan.pageUrl({ vstart: 1000, span: 100 })).toBe("/?span=100&at=1000");
  });
});
