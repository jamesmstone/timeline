import moment from "moment";
import { groups } from "../data";
import { loadDataForDateRange } from "../loaders";
import { LoadLanes } from "./handler";
import { LaneData } from "./render";

const timeout = 20 * 1000;
const ttl = 60 * 1000;
const maxEntries = 64;

const within = <T>(promise: Promise<T>, ms: number): Promise<T> =>
  Promise.race([
    promise,
    new Promise<T>((_, reject) =>
      setTimeout(() => reject(new Error(`timed out after ${ms}ms`)), ms),
    ),
  ]);

export const loadLanes: LoadLanes = async ({ start, end }) => {
  const range = { start: moment.utc(start), end: moment.utc(end) };
  return await Promise.all(
    groups.map(async (group): Promise<LaneData> => {
      try {
        const { result } = await within(
          loadDataForDateRange(group, range, ""),
          timeout,
        );
        return { group, result };
      } catch (e) {
        console.error(`embed: ${group} failed:`, e);
        return { group, result: null };
      }
    }),
  );
};

// Every <picture> source asks for the same range at a different size, and an
// embed on a busy page is fetched once per visitor; both should cost the data
// sources one load a minute, not one per request.
export const cached = (load: LoadLanes): LoadLanes => {
  const entries = new Map<string, { at: number; lanes: Promise<LaneData[]> }>();
  return (range) => {
    const key = `${range.start.toISOString()}/${range.end.toISOString()}`;
    const hit = entries.get(key);
    if (hit !== undefined && Date.now() - hit.at < ttl) return hit.lanes;
    const lanes = load(range);
    entries.delete(key);
    entries.set(key, { at: Date.now(), lanes });
    while (entries.size > maxEntries)
      entries.delete(entries.keys().next().value);
    return lanes;
  };
};
