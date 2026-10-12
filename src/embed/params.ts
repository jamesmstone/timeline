import moment from "moment";

export type Layout = "horizontal" | "vertical";
export type Theme = "light" | "dark" | "auto";

export type EmbedParams = {
  start: Date;
  end: Date;
  width: number;
  height: number;
  layout: Layout;
  theme: Theme;
};

export type Parsed =
  { ok: true; params: EmbedParams } | { ok: false; error: string };

const hour = 60 * 60 * 1000;
const day = 24 * hour;
const units = { h: hour, d: day, w: 7 * day } as const;

export const defaultDuration = 7 * day;
export const minDuration = hour;
export const maxDuration = 5 * 366 * day;

export const minSize = 200;
export const maxSize = 2400;
export const defaultWidth = 1200;
// Below this a horizontal row's plot is too short to read a week off, so
// auto layout turns the chart on its side instead.
export const verticalBelow = 640;

export const defaultHeight = (layout: Layout, width: number): number =>
  layout === "horizontal" ? 520 : clampSize(Math.round(width * 1.5));

const clampSize = (value: number): number =>
  Math.min(maxSize, Math.max(minSize, value));

class ParamError extends Error {}

const parseTime = (name: string, value: string, now: Date): Date => {
  if (value.toLowerCase() === "now") return now;
  const parsed = moment.utc(value, moment.ISO_8601, true);
  if (!parsed.isValid())
    throw new ParamError(`${name} must be an ISO 8601 time or "now"`);
  return parsed.toDate();
};

const parseDuration = (value: string): number => {
  const match = /^(\d+(?:\.\d+)?)([hdw])$/i.exec(value.trim());
  if (match === null)
    throw new ParamError(
      'duration must be a number followed by h, d or w, e.g. "24h" or "1w"',
    );
  const span = Number(match[1]) * units[match[2].toLowerCase()];
  if (span <= 0) throw new ParamError("duration must be more than zero");
  return span;
};

const parseSize = (name: string, value: string): number => {
  const match = /^(\d+(?:\.\d+)?)(px)?$/i.exec(value.trim());
  if (match === null)
    throw new ParamError(`${name} must be a number of pixels, e.g. "600"`);
  return Number(match[1]);
};

const oneOf = <T extends string>(
  name: string,
  value: string,
  allowed: readonly T[],
): T => {
  const lower = value.toLowerCase();
  if (!(allowed as readonly string[]).includes(lower))
    throw new ParamError(`${name} must be one of ${allowed.join(", ")}`);
  return lower as T;
};

const optional = <T>(
  query: URLSearchParams,
  name: string,
  parse: (value: string) => T,
): T | null => {
  const value = query.get(name);
  return value === null || value === "" ? null : parse(value);
};

const resolveRange = (
  start: Date | null,
  end: Date | null,
  duration: number | null,
  now: Date,
): { start: Date; end: Date } => {
  if (start !== null && end !== null) return { start, end };
  const span = duration ?? defaultDuration;
  if (end !== null) return { start: new Date(end.getTime() - span), end };
  if (start !== null) return { start, end: new Date(start.getTime() + span) };
  return { start: new Date(now.getTime() - span), end: now };
};

export const parseEmbedParams = (query: URLSearchParams, now: Date): Parsed => {
  try {
    const start = optional(query, "start", (v) => parseTime("start", v, now));
    const end = optional(query, "end", (v) => parseTime("end", v, now));
    const duration = optional(query, "duration", parseDuration);
    const range = resolveRange(start, end, duration, now);
    const span = range.end.getTime() - range.start.getTime();
    if (span <= 0) throw new ParamError("start must be before end");
    if (span < minDuration)
      throw new ParamError("the range must be at least 1h");
    if (span > maxDuration)
      throw new ParamError("the range must be at most 5 years");

    const width = optional(query, "width", (v) => parseSize("width", v));
    const maxWidth = optional(query, "maxWidth", (v) =>
      parseSize("maxWidth", v),
    );
    const height = optional(query, "height", (v) => parseSize("height", v));
    const resolvedWidth = clampSize(
      Math.round(
        Math.min(width ?? maxWidth ?? defaultWidth, maxWidth ?? Infinity),
      ),
    );
    const requested = optional(query, "layout", (v) =>
      oneOf("layout", v, ["auto", "horizontal", "vertical"] as const),
    );
    const layout: Layout =
      requested === "horizontal" || requested === "vertical"
        ? requested
        : height !== null
          ? height > resolvedWidth
            ? "vertical"
            : "horizontal"
          : resolvedWidth < verticalBelow
            ? "vertical"
            : "horizontal";
    const theme =
      optional(query, "theme", (v) =>
        oneOf("theme", v, ["light", "dark", "auto"] as const),
      ) ?? "light";

    return {
      ok: true,
      params: {
        ...range,
        width: resolvedWidth,
        height:
          height === null
            ? defaultHeight(layout, resolvedWidth)
            : clampSize(Math.round(height)),
        layout,
        theme,
      },
    };
  } catch (e) {
    if (e instanceof ParamError) return { ok: false, error: e.message };
    throw e;
  }
};
