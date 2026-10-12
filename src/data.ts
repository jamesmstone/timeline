import { DataItem } from "vis-timeline/peer";
import { Graph2dOptions } from "vis-timeline/types";
import { Range } from "./range";

export const groups = [
  "Heart rate",
  "Stress level",
  "Sleep",
  "Steps",
  "Music",
  "Family",
  "Read",
] as const;
export type Group = (typeof groups)[number];

export const stackGroup = (group: Group): boolean => group !== "Music";

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

export type Loader = (
  dateRange: Range,
  search: string | undefined,
) => Promise<TimelineDataItem>;
