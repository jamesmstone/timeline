import { Graph2d, Timeline } from "vis-timeline/peer";
import * as moment from "moment-timezone";
import { GraphDataItem, TimelineDataItem } from "./main";

type Extreme = { kind: "high" | "low"; value: number; at: number };

const aDay = 24 * 60 * 60 * 1000;

const stampFormat = (span: number): string => {
  if (span <= 2 * aDay) return "HH:mm";
  if (span <= 70 * aDay) return "D MMM";
  return "MMM YY";
};

// Loaders fetch whole months around the window, so an unfiltered peak is
// often one the viewer cannot see.
const extremes = (
  data: GraphDataItem[],
  range: { start: Date; end: Date },
): Extreme[] => {
  const points = data.filter(
    (d) =>
      Number.isFinite(d.y) &&
      new Date(d.x) >= range.start &&
      new Date(d.x) <= range.end,
  );
  if (points.length < 2) return [];
  const highest = points.reduce((best, d) => (d.y > best.y ? d : best));
  const lowest = points.reduce((best, d) => (d.y < best.y ? d : best));
  if (highest.y === lowest.y) return [];
  return [
    { kind: "high", value: highest.y, at: new Date(highest.x).getTime() },
    { kind: "low", value: lowest.y, at: new Date(lowest.x).getTime() },
  ];
};

const round = (value: number): string =>
  (Math.abs(value) < 10
    ? Math.round(value * 10) / 10
    : Math.round(value)
  ).toLocaleString();

const markerElement = (
  { kind, value, at }: Extreme,
  format: string,
): HTMLElement => {
  const marker = document.createElement("div");
  marker.className = `marker marker--${kind}`;
  marker.dataset.at = at.toString();

  const chip = document.createElement("span");
  chip.className = "marker__chip";
  chip.append(`${kind === "high" ? "▲" : "▼"} ${round(value)}`);

  const stamp = document.createElement("time");
  stamp.dateTime = new Date(at).toISOString();
  stamp.textContent = moment(at).utc().format(format);
  chip.appendChild(stamp);

  marker.appendChild(chip);
  return marker;
};

export const drawExtremes = (
  markers: HTMLElement,
  result: TimelineDataItem["result"],
  range: { start: Date; end: Date },
): void => {
  const format = stampFormat(range.end.getTime() - range.start.getTime());
  markers.replaceChildren(
    ...(result.type === "graph" ? extremes(result.data, range) : []).map(
      (extreme) => markerElement(extreme, format),
    ),
  );
};

export const placeExtremes = (
  chart: HTMLElement,
  markers: HTMLElement,
  line: Timeline | Graph2d,
): void => {
  const panel = chart.querySelector<HTMLElement>(".vis-panel.vis-center");
  const all = Array.from(markers.children) as HTMLElement[];
  if (panel === null || all.length === 0) return;

  const host = markers.getBoundingClientRect();
  const area = panel.getBoundingClientRect();
  const { start, end } = line.getWindow();
  const span = end.getTime() - start.getTime();

  const onScreen = all.filter((marker) => {
    const ratio = (Number(marker.dataset.at) - start.getTime()) / span;
    marker.hidden = ratio < 0 || ratio > 1;
    if (marker.hidden) return false;
    marker.style.left = `${area.left - host.left + ratio * area.width}px`;
    marker.style.top = `${area.top - host.top}px`;
    marker.style.height = `${area.height}px`;
    marker.firstElementChild.removeAttribute("style");
    return true;
  });

  // Measure every chip before nudging any of them, so a row of markers costs
  // one reflow rather than one per chip.
  const chips = onScreen.map(
    (marker) => marker.firstElementChild as HTMLElement,
  );
  const boxes = chips.map((chip) => chip.getBoundingClientRect());
  chips.forEach((chip, i) => {
    const shift =
      Math.max(0, area.left - boxes[i].left) -
      Math.max(0, boxes[i].right - area.right);
    if (shift !== 0) chip.style.translate = `calc(-50% + ${shift}px) 0`;
  });
};
