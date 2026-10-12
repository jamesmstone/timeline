import { expect, test } from "bun:test";
import { cached } from "./load";

test("shares one load per range while it is fresh", async () => {
  let loads = 0;
  const load = cached(async () => {
    loads++;
    return [];
  });
  const week = {
    start: new Date("2026-10-05T00:00:00Z"),
    end: new Date("2026-10-12T00:00:00Z"),
  };
  await Promise.all([load(week), load({ ...week })]);
  expect(loads).toBe(1);
  await load({ ...week, start: new Date("2026-10-06T00:00:00Z") });
  expect(loads).toBe(2);
});
