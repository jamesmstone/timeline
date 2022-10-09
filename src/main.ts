import {
  DataItem,
  Graph2d,
  Timeline,
  TimelineOptions,
  TimelineWindow,
} from "vis-timeline/peer";
import "vis-timeline/styles/vis-timeline-graph2d.css";
import { Graph2dOptions } from "vis-timeline/types";
import * as moment from "moment-timezone";
import { Range } from "./range";
import { clearWaitingRequests } from "./fetcher";
import { loadLastfm } from "./lastfm";
import { loadRead } from "./read";

export const errorDataItem = (
  { group, title, content }: Pick<DataItem, "group" | "title" | "content">,
  { start, end }: Range
): DataItem => ({
  group,
  content,
  title,
  start: start.toDate(),
  end: end.toDate(),
});
export const graphErrorDataItem = (
  { group, title, content }: Pick<DataItem, "group" | "title" | "content">,
  { start, end }: Range
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
export type TimelineDataItem =
  | {
      type: "graph";
      data: GraphDataItem[];
    }
  | {
      type: "timeline";
      data: DataItem[];
    };

const loadDataForDateRange = async (
  group: Group,
  dateRange: Range
): Promise<TimelineDataItem> => {
  clearWaitingRequests();
  switch (group) {
    case "Music":
      return await loadLastfm(dateRange);
    case "Read":
      return await loadRead(dateRange);
  }
};

export type Loader = (dateRange: Range) => Promise<TimelineDataItem>;

const end = moment.tz("UTC").endOf("day");
const start = end.clone().subtract(5, "day").startOf("day");
const initRange = { start, end };

const groups = ["Music", "Read"] as const;
export type Group = typeof groups[number];

let lines: { line: Timeline | Graph2d; group: Group }[] = [];

const setLineGraph = (
  range: Range,
  container: HTMLElement,
  line: { type: "graph"; data: GraphDataItem[] },
  group: Group
) => {
  const graphOptions: Graph2dOptions = {
    graphHeight: 150,
    width: width,
    style: "bar",

    barChart: { /*width: 50,*/ align: "left" },
    drawPoints: false,
    dataAxis: {
      icons: false,

      // @ts-ignore
      width: 75,
      left: {
        // @ts-ignore
        format: (value) => {
          return "" + value.toPrecision(3);
        },
      },
    },
    // @ts-ignore
    interpolation: false,
    start: range.start.toDate(),
    end: range.end.toDate(),
    moment: (date) => moment(date).utc(),
  };
  return new Graph2d(container, line.data, graphOptions);
};

const width = "65vw";
const setLineTimeline = (
  range: Range,
  container: HTMLElement,
  line: { type: "timeline"; data: DataItem[] },
  group: Group
) => {
  const timelineOptions: TimelineOptions = {
    stack: stackGroup(group),
    start: range.start.toDate(),
    end: range.end.toDate(),
    moment: (date) => moment(date).utc(),
    groupHeightMode: "auto",
    width: width,
  };
  return new Timeline(
    container,
    line.data,
    [{ id: group, content: "" }],
    timelineOptions
  );
};

const updateAllLinesRange = async (
  newRange: Range,
  except: Group
): Promise<void> => {
  for (const { line, group } of lines) {
    if (group !== except) {
      line.setWindow(newRange.start.toDate(), newRange.end.toDate(), {
        animation: false,
      });
    }
  }
};

const setLine = (
  container: HTMLElement,
  lineData: TimelineDataItem,
  range: Range,
  group: Group
): Graph2d | Timeline => {
  const line =
    lineData.type === "graph"
      ? setLineGraph(range, container, lineData, group)
      : setLineTimeline(range, container, lineData, group);

  line.on("rangechanged", async (properties: TimelineWindow) => {
    const newRange = {
      start: moment.tz(properties.start, "UTC"),
      end: moment.tz(properties.end, "UTC"),
    };
    const newLineData = await loadDataForDateRange(group, newRange);
    if (newLineData.type !== lineData.type) {
      line.destroy();
      const container = document.getElementById(group);
      container.textContent = null;
      const newLine = setLine(container, newLineData, newRange, group);
      lines = lines.map((line) => {
        if (line.group === group) return { group, line: newLine };
        return line;
      });
      return;
    }
    line.setItems(newLineData.data);
  });
  line.on("rangechange", (properties: TimelineWindow) => {
    updateAllLinesRange(
      {
        start: moment.tz(properties.start, "UTC"),
        end: moment.tz(properties.end, "UTC"),
      },
      group
    ).then(() => {});
  });
  return line;
};

const run = async () => {
  const container = document.getElementById("visualization");

  const groupDivs: { groupDiv: HTMLDivElement; group: Group }[] = groups.map(
    (group: Group) => {
      const groupDiv = document.createElement("div");
      groupDiv.setAttribute("id", group);
      groupDiv.setAttribute("class", "line");
      return { group, groupDiv };
    }
  );
  groupDivs.forEach(({ groupDiv }) => {
    container.appendChild(groupDiv);
  });

  for (const { group, groupDiv } of groupDivs) {
    const data = await loadDataForDateRange(group, initRange);
    lines = [
      ...lines,
      { group, line: setLine(groupDiv, data, initRange, group) },
    ];
  }

  //
  // const timelineGroups: TimelineGroup[] = groups.map((group) => ({
  //   content: group,
  //   subgroupStack: stackGroup(group),
  //   id: group,
  // }));
  // timeline.setGroups(timelineGroups);
  // const updateTimelineForDateRange = async (dateRange: Range): Promise<void> => {
  //   const data: DataItem[] = await loadDataForDateRange(dateRange);
  //
  //   items.clear();
  //   items.add(data);
  // };
  //
  // timeline.on("rangechanged", (properties: TimelineWindow) => {
  //   updateTimelineForDateRange({
  //     start: moment.tz(properties.start, "UTC"),
  //     end: moment.tz(properties.end, "UTC"),
  //   }).then(() => {});
  // });
  //
  // updateTimelineForDateRange({ start, end }).then(() => {});

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
