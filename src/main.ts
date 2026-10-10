import {
  DataItem,
  Graph2d,
  Timeline,
  TimelineOptions,
  TimelineWindow,
} from "vis-timeline/peer";
import "vis-timeline/styles/vis-timeline-graph2d.css";
// After vis's own sheet, so the theme overrides win on equal specificity.
import "./styles.css";
import { Graph2dOptions } from "vis-timeline/types";
import * as moment from "moment-timezone";
import { Interval, Range } from "./range";
import { clearWaitingRequests } from "./fetcher";
import {
  loadHeartRate,
  loadLastfm,
  loadRead,
  loadSleep,
  loadSteps,
  loadStressLevel,
} from "./datasetteLoaders";
import { loadFamily } from "./family";
import { drawExtremes, placeExtremes } from "./markers";

const debounce = (func, timeout = 300) => {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => {
      func.apply(this, args);
    }, timeout);
  };
};

export const errorDataItem = (
  { group, title, content }: Pick<DataItem, "group" | "title" | "content">,
  { start, end }: Range,
): DataItem => ({
  group,
  content,
  title,
  start: start.toDate(),
  end: end.toDate(),
});
export const graphErrorDataItem = (
  { group, title, content }: Pick<DataItem, "group" | "title" | "content">,
  { start, end }: Range,
): GraphDataItem => ({
  group,
  content,
  title,
  x: start.toDate(),
  y: null,
  start: start.toDate(),
  end: end.toDate(),
});

const stackGroup = (group: Group): boolean => group !== "Music";

export type GraphDataItem = DataItem & { x: DataItem["start"]; y: number };
export type GraphTimelineDataItem = {
  type: "graph";
  data: GraphDataItem[];
  graphOptions?: Partial<Graph2dOptions>;
};
export type TimelineDataItem = {
  options: { dateRange: Range; search: string };
  result:
    | GraphTimelineDataItem
    | {
        type: "timeline";
        data: DataItem[];
      };
};

const loadDataForDateRange = async (
  group: Group,
  dateRange: Range,
  search?: string,
): Promise<TimelineDataItem> => {
  switch (group) {
    case "Music":
      return await loadLastfm(dateRange, search);
    case "Heart rate":
      return await loadHeartRate(dateRange, search);
    case "Stress level":
      return await loadStressLevel(dateRange, search);
    case "Steps":
      return await loadSteps(dateRange, search);
    case "Sleep":
      return await loadSleep(dateRange, search);
    case "Read":
      return await loadRead(dateRange, search);
    case "Family":
      return await loadFamily(dateRange, search);
  }
};

export type Loader = (
  dateRange: Range,
  search: string | undefined,
) => Promise<TimelineDataItem>;

const today = (): Range => ({
  start: moment.tz("UTC").startOf("day"),
  end: moment.tz("UTC").endOf("day"),
});
const back = (amount: number, unit: Interval): Range => ({
  start: moment.tz("UTC").startOf("day").subtract(amount, unit).add(1, "day"),
  end: moment.tz("UTC").endOf("day"),
});

const presets = {
  today,
  yesterday: (): Range => ({
    start: moment.tz("UTC").subtract(1, "day").startOf("day"),
    end: moment.tz("UTC").subtract(1, "day").endOf("day"),
  }),
  week: (): Range => back(1, "week"),
  month: (): Range => back(1, "month"),
  year: (): Range => back(1, "year"),
};
type Preset = keyof typeof presets;

const initPreset: Preset = "week";
const initRange = presets[initPreset]();

const groups = [
  "Heart rate",
  "Stress level",
  "Sleep",
  "Steps",
  "Music",
  "Family",
  "Read",
] as const;
export type Group = (typeof groups)[number];

type Line = {
  group: Group;
  line: Timeline | Graph2d;
  chart: HTMLElement;
  markers: HTMLElement;
};

let lines: Line[] = [];

// Each row is its own vis instance, so only the last draws the date axis. The
// rows line up with it through the shared --gutter in styles.css, which a
// graph's y-axis has to fill exactly.
const drawsAxis = (group: Group): boolean =>
  group === groups[groups.length - 1];

const setLineGraph = (
  range: Range,
  container: HTMLElement,
  line: GraphTimelineDataItem,
  group: Group,
) => {
  const graphOptions: Graph2dOptions = {
    graphHeight: 150,
    width: width,
    style: "bar",

    barChart: { align: "left" },
    drawPoints: false,
    showMajorLabels: drawsAxis(group),
    showMinorLabels: drawsAxis(group),
    dataAxis: {
      icons: false,
      // @ts-ignore
      width: getComputedStyle(container).getPropertyValue("--gutter"),
      left: {
        // @ts-ignore
        format: (value) => value.toLocaleString(),
      },
    },
    // @ts-ignore
    interpolation: false,
    start: range.start.toDate(),
    end: range.end.toDate(),
    moment: (date) => moment(date).utc(),
  };
  return new Graph2d(
    container,
    line.data,
    // vis would otherwise number the class per created group, so a lane that
    // empties and refills drops to group1, group2... and loses the theme. A
    // custom name would also lose vis's own fill-opacity: 0 on the groupN rules.
    [{ id: group, content: group, className: "vis-graph-group0" }],
    line.hasOwnProperty("graphOptions")
      ? { ...graphOptions, ...line.graphOptions }
      : graphOptions,
  );
};

const width = "100%";
const setLineTimeline = (
  range: Range,
  container: HTMLElement,
  line: { type: "timeline"; data: DataItem[] },
  group: Group,
) => {
  const timelineOptions: TimelineOptions = {
    stack: stackGroup(group),
    start: range.start.toDate(),
    end: range.end.toDate(),
    moment: (date) => moment(date).utc(),
    groupHeightMode: "auto",
    width: width,
    showMajorLabels: drawsAxis(group),
    showMinorLabels: drawsAxis(group),
  };
  return new Timeline(
    container,
    line.data,
    [{ id: group, content: "" }],
    timelineOptions,
  );
};

const updateAllLinesRange = async (
  newRange: Range,
  except: Group,
): Promise<void> => {
  for (const { line, group } of lines) {
    if (group !== except) {
      line.setWindow(newRange.start.toDate(), newRange.end.toDate(), {
        animation: false,
      });
    }
  }
};
const search = document.getElementById("search");

const presetButtons = Array.from(
  document.querySelectorAll<HTMLButtonElement>("[data-preset]"),
);

// Applying a preset moves every line, and each move reports a range change
// that is indistinguishable from a drag -- so suppress the "you panned off the
// preset" reset for the duration.
let applyingPreset = false;

const setActivePreset = (preset: Preset | null): void => {
  for (const button of presetButtons) {
    button.setAttribute(
      "aria-pressed",
      String(button.dataset.preset === preset),
    );
  }
};

const applyPreset = (preset: Preset): void => {
  const { start, end } = presets[preset]();
  clearWaitingRequests();
  applyingPreset = true;
  setActivePreset(preset);
  for (const { line } of lines) {
    line.setWindow(start.toDate(), end.toDate(), { animation: false });
  }
  applyingPreset = false;
};

type Slot = { chart: HTMLElement; markers: HTMLElement };

const setLine = (
  { chart, markers }: Slot,
  lineData: TimelineDataItem,
  range: Range,
  group: Group,
): Graph2d | Timeline => {
  const startsDifferent = !lineData.options.dateRange.start.isSame(range.start);
  const endsDifferent = !lineData.options.dateRange.end.isSame(range.end);
  const searchDifferent = lineData.options.search !== search.value;
  if (startsDifferent) {
    return;
  }
  if (endsDifferent) {
    return;
  }
  if (searchDifferent) {
    return;
  }

  const line =
    lineData.result.type === "graph"
      ? setLineGraph(range, chart, lineData.result, group)
      : setLineTimeline(range, chart, lineData.result, group);

  const showExtremes = (result: TimelineDataItem["result"]) => {
    drawExtremes(markers, result, line.getWindow());
    placeExtremes(chart, markers, line);
  };
  showExtremes(lineData.result);

  line.on("rangechanged", async (properties: TimelineWindow) => {
    const newRange = {
      start: moment.tz(properties.start, "UTC"),
      end: moment.tz(properties.end, "UTC"),
    };

    const newLineData = await loadDataForDateRange(
      group,
      newRange,
      // @ts-ignore
      search.value,
    );
    if (newLineData.result.type !== lineData.result.type) {
      line.destroy();
      chart.textContent = null;
      const newLine = setLine({ chart, markers }, newLineData, newRange, group);
      lines = lines.map((line) => {
        if (line.group === group) return { ...line, line: newLine };
        return line;
      });
      return;
    }
    line.setItems(newLineData.result.data);
    showExtremes(newLineData.result);
  });
  line.on("rangechange", (properties: TimelineWindow) => {
    if (!applyingPreset) setActivePreset(null);
    placeExtremes(chart, markers, line);
    updateAllLinesRange(
      {
        start: moment.tz(properties.start, "UTC"),
        end: moment.tz(properties.end, "UTC"),
      },
      group,
    ).then(() => {});
  });
  return line;
};

const run = async () => {
  const onSearch = debounce(async (e) => {
    const searchValue = e.target.value;
    const loadLines = lines.map(async ({ line, group }) => {
      const window = line.getWindow();
      const newLineData = await loadDataForDateRange(
        group,
        {
          start: moment(window.start),
          end: moment(window.end),
        },
        searchValue,
      );
      line.setItems(newLineData.result.data);
    });
    await Promise.all(loadLines);
  });

  search.addEventListener("input", onSearch);

  for (const button of presetButtons) {
    button.addEventListener("click", () =>
      applyPreset(button.dataset.preset as Preset),
    );
  }
  setActivePreset(initPreset);

  window.addEventListener("resize", () => {
    for (const { line, chart, markers } of lines) {
      placeExtremes(chart, markers, line);
    }
  });

  const container = document.getElementById("visualization");

  const slots = groups.map((group: Group) => {
    const groupDiv = document.createElement("div");
    groupDiv.setAttribute("id", group);
    groupDiv.setAttribute("class", "line");

    const chart = document.createElement("div");
    chart.setAttribute("class", "line__chart");
    const markers = document.createElement("div");
    markers.setAttribute("class", "markers");
    groupDiv.append(chart, markers);

    container.appendChild(groupDiv);
    return { group, chart, markers };
  });

  const loadLines = slots.map(async ({ group, chart, markers }) => {
    const data = await loadDataForDateRange(group, initRange, search.value);
    lines = [
      ...lines,
      {
        group,
        chart,
        markers,
        line: setLine({ chart, markers }, data, initRange, group),
      },
    ];
  });
  await Promise.all(loadLines);

  /* 
  # Datasets
  
  |    Dataset | day            | month          | year            |
  |-----------:|:---------------|----------------|-----------------|
  |     Family | multiple range | multiple range | multiple range  |
  |      Music | single range   | graph count    | graph count     |
  | Heart Rate | graph          | graph avg      | graph avg       |
  
   */
};
run().then(() => {});
