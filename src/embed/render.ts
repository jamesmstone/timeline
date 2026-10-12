import moment from "moment";
import { DataItem } from "vis-timeline/peer";
import {
  GraphDataItem,
  Group,
  groups,
  stackGroup,
  TimelineDataItem,
} from "../data";
import { Extreme, extremes, round, stampFormat } from "../markers";
import { ticks } from "./axis";
import { EmbedParams } from "./params";
import { el, escapeXml, fit, num, text, textWidth } from "./svg";
import { groupClass, stylesheet } from "./theme";

export type LaneData = {
  group: Group;
  // null when the lane's sources failed or timed out.
  result: TimelineDataItem["result"] | null;
};

type Box = { x: number; y: number; w: number; h: number };

// Everything inside a lane is drawn against a time fraction (0 at the range's
// start) and a cross fraction (0 at a graph's baseline), so one set of
// drawing code serves both layouts: across a row, or down a column.
type Frame = {
  box: Box;
  horizontal: boolean;
  timeLength: number;
  crossLength: number;
  at: (t: number, c: number) => [number, number];
  rect: (t0: number, t1: number, c0: number, c1: number) => Box;
  // A band at a pixel offset from the lane's top (rows) or left (columns).
  band: (t0: number, t1: number, offset: number, size: number) => Box;
};

const frame = (box: Box, horizontal: boolean): Frame => {
  const at = (t: number, c: number): [number, number] =>
    horizontal
      ? [box.x + t * box.w, box.y + (1 - c) * box.h]
      : [box.x + c * box.w, box.y + t * box.h];
  const corners = ([x0, y0]: number[], [x1, y1]: number[]): Box => ({
    x: Math.min(x0, x1),
    y: Math.min(y0, y1),
    w: Math.abs(x1 - x0),
    h: Math.abs(y1 - y0),
  });
  return {
    box,
    horizontal,
    timeLength: horizontal ? box.w : box.h,
    crossLength: horizontal ? box.h : box.w,
    at,
    rect: (t0, t1, c0, c1) => corners(at(t0, c0), at(t1, c1)),
    band: (t0, t1, offset, size) =>
      horizontal
        ? {
            x: box.x + t0 * box.w,
            y: box.y + offset,
            w: (t1 - t0) * box.w,
            h: size,
          }
        : {
            x: box.x + offset,
            y: box.y + t0 * box.h,
            w: size,
            h: (t1 - t0) * box.h,
          },
  };
};

const rect = (b: Box, attrs: Record<string, string | number> = {}): string =>
  el("rect", { x: b.x, y: b.y, width: b.w, height: b.h, ...attrs });

const hour = 60 * 60 * 1000;
const day = 24 * hour;

const shortLabels: Record<Group, string> = {
  "Heart rate": "Heart",
  "Stress level": "Stress",
  Sleep: "Sleep",
  Steps: "Steps",
  Music: "Music",
  Family: "Family",
  Read: "Read",
};

const time = (value: DataItem["start"]): number => new Date(value).getTime();

const compact = (value: number): string =>
  Math.abs(value) < 10000
    ? round(value)
    : new Intl.NumberFormat("en", {
        notation: "compact",
        maximumFractionDigits: 1,
      }).format(value);

// The end of the range is usually now, and a now line on the plot's edge
// reads as a stray border rather than a marker.
const showsNow = (
  now: number,
  { start, end }: { start: number; end: number },
) => now > start + (end - start) * 0.01 && now < end - (end - start) * 0.01;

const itemLabel = ({ content, title }: DataItem): string => {
  // Loaders hand vis HTML (album art, thumbnails) as content; the plain title
  // is the text an image can carry.
  if (typeof content === "string" && !content.includes("<")) return content;
  return typeof title === "string" ? title : "";
};

export const rangeLabel = (start: Date, end: Date): string => {
  const s = moment.utc(start);
  const e = moment.utc(end);
  const withTime = e.diff(s) < 70 * day;
  const full = withTime ? "D MMM YYYY HH:mm" : "D MMM YYYY";
  const opening = s.year() === e.year() ? full.replace(" YYYY", "") : full;
  return `${s.format(opening)} – ${e.format(full)} UTC`;
};

type Context = { start: number; end: number; id: number };

const fraction = ({ start, end }: Context, at: number): number =>
  (at - start) / (end - start);

const clampFraction = (t: number): number => Math.min(1.02, Math.max(-0.02, t));

const graphLane = (
  result: Extract<TimelineDataItem["result"], { type: "graph" }>,
  f: Frame,
  ctx: Context,
): { body: string; scale: [number, number] | null } => {
  const points = result.data
    .filter((d) => Number.isFinite(d.y))
    .map((d) => ({
      at: time(d.x),
      until: d.end === undefined ? null : time(d.end),
      y: d.y,
    }))
    .sort((a, b) => a.at - b.at);
  const inRange = (p: { at: number; until: number | null }) =>
    (p.until ?? p.at) >= ctx.start && p.at <= ctx.end;
  const shown = points.filter(inRange);
  if (shown.length === 0) return { body: "", scale: null };

  if (result.graphOptions?.style !== "line") {
    const max = Math.max(...shown.map((p) => p.y));
    if (max <= 0) return { body: "", scale: null };
    const bars = shown.map((p, i) => {
      const until = p.until ?? shown[i + 1]?.at ?? p.at + day;
      const b = f.rect(
        clampFraction(fraction(ctx, p.at)),
        clampFraction(fraction(ctx, until)),
        0,
        p.y / max,
      );
      const gap = (f.horizontal ? b.w : b.h) > 4 ? 1 : 0;
      return rect(
        f.horizontal
          ? { ...b, x: b.x + gap, w: b.w - 2 * gap }
          : { ...b, y: b.y + gap, h: b.h - 2 * gap },
        { "fill-opacity": 0.45, "stroke-width": 1 },
      );
    });
    return { body: bars.join(""), scale: [0, max] };
  }

  const first = points.findIndex(inRange);
  const last = points.length - 1 - [...points].reverse().findIndex(inRange);
  const run = points.slice(Math.max(0, first - 1), last + 2);
  const min = Math.min(...shown.map((p) => p.y));
  const max = Math.max(...shown.map((p) => p.y));
  const spread = max - min || 1;
  const value = (y: number) => (y - min) / spread;

  // Minute-level heart rate runs to thousands of points; keep each pixel's
  // lowest and highest so the trace still shows every spike.
  const buckets = new Map<number, typeof run>();
  for (const p of run) {
    const px = Math.round(fraction(ctx, p.at) * f.timeLength);
    const bucket = buckets.get(px);
    if (bucket === undefined) buckets.set(px, [p]);
    else bucket.push(p);
  }
  const thinned = [...buckets.values()].flatMap((bucket) => {
    if (bucket.length <= 2) return bucket;
    const lo = bucket.reduce((a, b) => (b.y < a.y ? b : a));
    const hi = bucket.reduce((a, b) => (b.y > a.y ? b : a));
    return lo.at <= hi.at ? [lo, hi] : [hi, lo];
  });

  const inset = (c: number) => 0.04 + c * 0.92;
  const coords = thinned.map((p) =>
    f.at(fraction(ctx, p.at), inset(value(p.y))),
  );
  const [hx, hy] = f.at(0, 1);
  const [lx, ly] = f.at(0, 0);
  const ramp = el(
    "linearGradient",
    {
      id: `ramp-${ctx.id}`,
      gradientUnits: "userSpaceOnUse",
      x1: f.horizontal ? 0 : hx,
      y1: f.horizontal ? hy : 0,
      x2: f.horizontal ? 0 : lx,
      y2: f.horizontal ? ly : 0,
    },
    el("stop", { offset: 0 }),
    el("stop", { offset: 1, class: "low" }),
  );
  const trace =
    coords.length === 1
      ? el("circle", {
          cx: coords[0][0],
          cy: coords[0][1],
          r: 2.5,
          stroke: "none",
        })
      : el("path", {
          d: coords
            .map(([x, y], i) => `${i === 0 ? "M" : "L"}${num(x)} ${num(y)}`)
            .join(""),
          fill: "none",
          stroke: `url(#ramp-${ctx.id})`,
          "stroke-width": 2,
          "stroke-linecap": "round",
          "stroke-linejoin": "round",
        });
  return { body: el("defs", {}, ramp) + trace, scale: [min, max] };
};

const timelineLane = (
  group: Group,
  data: DataItem[],
  f: Frame,
  ctx: Context,
): string => {
  const items = data
    .map((item) => ({
      at: time(item.start),
      until:
        item.end === undefined || item.end === null ? null : time(item.end),
      label: itemLabel(item),
    }))
    .filter((i) =>
      i.until === null
        ? i.at >= ctx.start && i.at <= ctx.end
        : i.until >= ctx.start && i.at <= ctx.end,
    )
    .sort((a, b) => a.at - b.at);
  if (items.length === 0) return "";

  const px = (at: number) => fraction(ctx, at) * f.timeLength;
  const stacked = stackGroup(group);
  const laneEnds: number[] = [];
  const placed = items.map((item) => {
    const from = px(item.at);
    const to =
      item.until === null
        ? from + 8 + (f.horizontal ? textWidth(item.label, 10) : 0)
        : px(item.until);
    let lane = stacked ? laneEnds.findIndex((end) => end <= from) : 0;
    if (lane === -1) lane = laneEnds.length;
    laneEnds[lane] = Math.max(laneEnds[lane] ?? -Infinity, to + 2);
    return { ...item, lane };
  });

  const lanes = laneEnds.length;
  const fits = Math.max(1, Math.floor(f.crossLength / 3));
  const shownLanes = Math.min(lanes, fits);
  const size = Math.min(18, f.crossLength / shownLanes);
  const font = Math.min(10, size - 4);
  const hidden = placed.filter((i) => i.lane >= shownLanes).length;

  const body = placed
    .filter((i) => i.lane < shownLanes)
    .map((item) => {
      const t0 = clampFraction(fraction(ctx, item.at));
      const offset = item.lane * size;
      const mid = offset + size / 2;
      const [cx, cy] = f.horizontal
        ? [f.box.x + t0 * f.box.w, f.box.y + mid]
        : [f.box.x + mid, f.box.y + t0 * f.box.h];
      let mark: string;
      let labelFrom: number;
      let labelRoom: number;
      if (item.until === null) {
        mark = el("circle", {
          cx,
          cy,
          r: Math.max(1, Math.min(3, size / 2 - 1)),
          stroke: "none",
        });
        labelFrom = 7;
        labelRoom = f.horizontal ? f.box.x + f.box.w - cx - 7 : 0;
      } else {
        const t1 = clampFraction(fraction(ctx, item.until));
        const b = f.band(t0, t1, offset + 1, Math.max(1, size - 2));
        mark = rect(b, {
          class: "span",
          rx: Math.min(4, Math.max(0, (size - 2) / 2)),
          "stroke-width": 1,
        });
        const visibleFrom = Math.max(0, t0) * f.timeLength;
        const visibleTo = Math.min(1, t1) * f.timeLength;
        labelFrom = visibleFrom - t0 * f.timeLength + 4;
        labelRoom = visibleTo - visibleFrom - 8;
      }
      if (size < 11 || item.label === "") return mark;
      const label = fit(item.label, font, labelRoom);
      if (label === null) return mark;
      const [lx, ly] = f.horizontal
        ? [cx + labelFrom, cy + font * 0.35]
        : [cx - font * 0.35, cy + labelFrom];
      return (
        mark +
        text(
          {
            x: lx,
            y: ly,
            class: "ink",
            "font-size": font,
            transform: f.horizontal
              ? undefined
              : `rotate(90 ${num(lx)} ${num(ly)})`,
          },
          label,
        )
      );
    })
    .join("");

  const more =
    hidden === 0
      ? ""
      : text(
          {
            x: f.box.x + f.box.w - 2,
            y: f.box.y + f.box.h - 3,
            "text-anchor": "end",
            class: "muted",
            "font-size": 9,
            "font-weight": 600,
          },
          `+${hidden} more`,
        );
  return body + more;
};

const peakMarkers = (
  found: Extreme[],
  f: Frame,
  ctx: Context,
  withStamp: boolean,
): string => {
  const format = stampFormat(ctx.end - ctx.start);
  return found
    .map(({ kind, value, at }) => {
      const t = fraction(ctx, at);
      const [x0, y0] = f.at(t, 0);
      const [x1, y1] = f.at(t, 1);
      const line = el("line", {
        x1: x0,
        y1: y0,
        x2: x1,
        y2: y1,
        "stroke-opacity": 0.45,
        "stroke-dasharray": "3 3",
        "stroke-width": 1,
      });
      const reading = `${kind === "high" ? "▲" : "▼"} ${
        withStamp ? round(value) : compact(value)
      }`;
      const stamp = withStamp ? moment.utc(at).format(format) : "";
      const size = 8.5;
      const width =
        textWidth(reading, size) + (stamp ? textWidth(stamp, size) + 4 : 0) + 10;
      const height = 14;
      const { box } = f;
      let cx: number;
      let cy: number;
      if (f.horizontal) {
        cx = Math.min(
          box.x + box.w - width / 2,
          Math.max(box.x + width / 2, x0),
        );
        cy = kind === "high" ? box.y + height / 2 : box.y + box.h - height / 2;
      } else {
        cx = kind === "high" ? box.x + box.w - width / 2 : box.x + width / 2;
        cy = Math.min(
          box.y + box.h - height / 2,
          Math.max(box.y + height / 2, y0),
        );
      }
      const chip = el(
        "g",
        { class: kind === "low" ? "low" : undefined },
        rect(
          { x: cx - width / 2, y: cy - height / 2, w: width, h: height },
          { rx: height / 2, stroke: "none" },
        ),
        `<text x="${num(cx - width / 2 + 5)}" y="${num(cy + size * 0.35)}" font-size="${size}" font-weight="700" class="${
          kind === "low" ? "pill-ink-low" : "pill-ink"
        }">${escapeXml(reading)}${
          stamp
            ? `<tspan dx="4" font-weight="500" opacity="0.75">${escapeXml(stamp)}</tspan>`
            : ""
        }</text>`,
      );
      return line + chip;
    })
    .join("");
};

const graphPeaks = (lane: LaneData, ctx: Context): Extreme[] =>
  lane.result?.type === "graph"
    ? extremes(lane.result.data as GraphDataItem[], {
        start: new Date(ctx.start),
        end: new Date(ctx.end),
      })
    : [];

const describe = (lanes: LaneData[], ctx: Context, label: string): string => {
  const format = stampFormat(ctx.end - ctx.start);
  const details = lanes.flatMap((lane) => {
    if (lane.result === null) return [`${lane.group} is unavailable.`];
    const peaks = graphPeaks(lane, ctx);
    if (peaks.length === 0) return [];
    const [high, low] = peaks;
    return [
      `${lane.group} peaked at ${round(high.value)} (${moment
        .utc(high.at)
        .format(format)}) and dipped to ${round(low.value)} (${moment
        .utc(low.at)
        .format(format)}).`,
    ];
  });
  return [
    `James Stone's heart rate, stress, sleep, steps, music, family and reading, ${label}.`,
    ...details,
  ].join(" ");
};

const lanePill = (group: Group, b: Box, horizontal: boolean): string => {
  const size = horizontal ? 8 : 7.5;
  const spacing = horizontal ? 1.2 : 0.6;
  const room = (horizontal ? b.h : b.w) - 8;
  const label =
    [group, shortLabels[group]]
      .map((l) => l.toUpperCase())
      .find((l) => textWidth(l, size, spacing) <= room) ?? null;
  const cx = b.x + b.w / 2;
  const cy = b.y + b.h / 2;
  return (
    rect(b, { rx: Math.min(b.w, b.h) / 2, stroke: "none" }) +
    (label === null
      ? ""
      : text(
          {
            x: cx,
            y: cy + size * 0.35,
            "text-anchor": "middle",
            "font-size": size,
            "font-weight": 700,
            "letter-spacing": spacing,
            class: "pill-ink",
            transform: horizontal
              ? `rotate(-90 ${num(cx)} ${num(cy)})`
              : undefined,
          },
          label,
        ))
  );
};

const unavailable = (b: Box): string =>
  text(
    {
      x: b.x + b.w / 2,
      y: b.y + b.h / 2 + 3.5,
      "text-anchor": "middle",
      "font-size": 10,
      "font-style": "italic",
      class: "faint",
    },
    "Unavailable",
  );

const laneBody = (
  lane: LaneData,
  f: Frame,
  ctx: Context,
  withStamp: boolean,
): { body: string; scale: [number, number] | null } => {
  if (lane.result === null) return { body: unavailable(f.box), scale: null };
  const clip = el(
    "clipPath",
    { id: `clip-${ctx.id}` },
    rect({ x: f.box.x - 1, y: f.box.y - 1, w: f.box.w + 2, h: f.box.h + 2 }),
  );
  const drawn =
    lane.result.type === "graph"
      ? graphLane(lane.result, f, ctx)
      : {
          body: timelineLane(lane.group, lane.result.data, f, ctx),
          scale: null,
        };
  return {
    body:
      el("defs", {}, clip) +
      el("g", { "clip-path": `url(#clip-${ctx.id})` }, drawn.body) +
      peakMarkers(graphPeaks(lane, ctx), f, ctx, withStamp),
    scale: drawn.scale,
  };
};

export const renderEmbed = (
  lanes: LaneData[],
  { start, end, width: W, height: H, layout, theme }: EmbedParams,
  now: Date,
): string => {
  const horizontal = layout === "horizontal";
  const span = { start: start.getTime(), end: end.getTime() };
  const label = rangeLabel(start, end);
  const pad = W < 420 ? 10 : 16;

  const titleSize = 17;
  const labelSize = 11.5;
  const oneLine =
    textWidth("Timeline", titleSize) + 16 + textWidth(label, labelSize) <=
    W - 2 * pad;
  const header =
    text(
      {
        x: pad,
        y: pad + 14,
        class: "ink",
        "font-size": titleSize,
        "font-weight": 700,
      },
      "Timeline",
    ) +
    text(
      oneLine
        ? {
            x: W - pad,
            y: pad + 13,
            "text-anchor": "end",
            class: "muted",
            "font-size": labelSize,
          }
        : { x: pad, y: pad + 32, class: "muted", "font-size": labelSize },
      fit(label, labelSize, W - 2 * pad) ?? "",
    );
  const top = pad + (oneLine ? 28 : 44);

  const ordered = groups.map(
    (group) => lanes.find((l) => l.group === group) ?? { group, result: null },
  );
  const parts: string[] = [];
  const grid: string[] = [];

  if (horizontal) {
    const axis = 22;
    const bottom = H - pad - axis;
    const rowH = (bottom - top) / ordered.length;
    const pillW = 18;
    const gutter = W < 420 ? 30 : 40;
    const plotX = pad + pillW + 8 + gutter;
    const plotW = W - pad - plotX;

    for (const t of ticks(span.start, span.end, plotW, 90)) {
      const x = plotX + fraction({ ...span, id: 0 }, t.at) * plotW;
      grid.push(
        el("line", {
          x1: x,
          y1: top,
          x2: x,
          y2: bottom,
          class: t.major ? "grid-major" : "grid",
          "stroke-width": 1,
        }),
      );
      if (x + textWidth(t.label, 10) <= W - pad)
        grid.push(
          text(
            {
              x: x + 3,
              y: bottom + 15,
              "font-size": 10,
              class: t.major ? "ink" : "muted",
              "font-weight": t.major ? 600 : undefined,
            },
            t.label,
          ),
        );
    }
    ordered.forEach((lane, i) => {
      const y = top + i * rowH;
      if (i > 0)
        grid.push(
          el("line", {
            x1: pad,
            y1: y,
            x2: W - pad,
            y2: y,
            class: "grid",
            "stroke-width": 1,
          }),
        );
      const inner = { x: plotX, y: y + 6, w: plotW, h: rowH - 12 };
      const ctx = { ...span, id: i };
      const { body, scale } = laneBody(lane, frame(inner, true), ctx, true);
      const values =
        scale === null
          ? ""
          : [
              [scale[1], inner.y + 8],
              [scale[0], inner.y + inner.h],
            ]
              .map(([v, ty]) =>
                text(
                  {
                    x: plotX - 6,
                    y: ty,
                    "text-anchor": "end",
                    "font-size": 9.5,
                    class: "muted",
                  },
                  compact(v),
                ),
              )
              .join("");
      parts.push(
        el(
          "g",
          { class: groupClass(lane.group) },
          lanePill(
            lane.group,
            { x: pad, y: y + 6, w: pillW, h: rowH - 12 },
            true,
          ),
          values,
          body,
        ),
      );
    });
    if (showsNow(now.getTime(), span)) {
      const x = plotX + fraction({ ...span, id: 0 }, now.getTime()) * plotW;
      parts.push(
        el("line", {
          x1: x,
          y1: top,
          x2: x,
          y2: bottom,
          class: "now",
          "stroke-width": 1,
        }),
      );
    }
  } else {
    const gutter = 40;
    const left = pad + gutter;
    const colW = (W - pad - left) / ordered.length;
    const pillH = 18;
    const plotTop = top + pillH + 8;
    const plotH = H - pad - plotTop;

    for (const t of ticks(span.start, span.end, plotH, 60)) {
      const y = plotTop + fraction({ ...span, id: 0 }, t.at) * plotH;
      grid.push(
        el("line", {
          x1: left,
          y1: y,
          x2: W - pad,
          y2: y,
          class: t.major ? "grid-major" : "grid",
          "stroke-width": 1,
        }),
      );
      grid.push(
        text(
          {
            x: left - 5,
            y: y + 3.5,
            "text-anchor": "end",
            "font-size": 9.5,
            class: t.major ? "ink" : "muted",
            "font-weight": t.major ? 600 : undefined,
          },
          fit(t.label, 9.5, gutter - 4) ?? "",
        ),
      );
    }
    ordered.forEach((lane, i) => {
      const x = left + i * colW;
      if (i > 0)
        grid.push(
          el("line", {
            x1: x,
            y1: plotTop,
            x2: x,
            y2: H - pad,
            class: "grid",
            "stroke-width": 1,
          }),
        );
      const inner = { x: x + 4, y: plotTop, w: colW - 8, h: plotH };
      const ctx = { ...span, id: i };
      const { body } = laneBody(lane, frame(inner, false), ctx, colW >= 110);
      parts.push(
        el(
          "g",
          { class: groupClass(lane.group) },
          lanePill(
            lane.group,
            { x: x + 3, y: top, w: colW - 6, h: pillH },
            false,
          ),
          body,
        ),
      );
    });
    if (showsNow(now.getTime(), span)) {
      const y = plotTop + fraction({ ...span, id: 0 }, now.getTime()) * plotH;
      parts.push(
        el("line", {
          x1: left,
          y1: y,
          x2: W - pad,
          y2: y,
          class: "now",
          "stroke-width": 1,
        }),
      );
    }
  }

  const ctx = { ...span, id: 0 };
  return (
    `<?xml version="1.0" encoding="UTF-8"?>\n` +
    el(
      "svg",
      {
        xmlns: "http://www.w3.org/2000/svg",
        width: W,
        height: H,
        viewBox: `0 0 ${W} ${H}`,
        role: "img",
        "aria-labelledby": "title desc",
      },
      el("title", { id: "title" }, escapeXml(`Timeline, ${label}`)),
      el("desc", { id: "desc" }, escapeXml(describe(ordered, ctx, label))),
      el("style", {}, stylesheet(theme)),
      rect(
        { x: 0.5, y: 0.5, w: W - 1, h: H - 1 },
        { rx: 14, class: "card", "stroke-width": 1 },
      ),
      header,
      ...grid,
      ...parts,
    )
  );
};
