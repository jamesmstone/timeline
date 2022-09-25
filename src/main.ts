import { DataSet } from "vis-data/peer";
import { Timeline } from "vis-timeline/peer";
import "vis-timeline/styles/vis-timeline-graph2d.css";
import {
  DataItem,
  DataSetDataItem,
  TimelineGroup,
  TimelineOptions,
  TimelineWindow,
} from "vis-timeline";
import { Range } from "./range";
import { loadLastfm } from "./lastfm";
import * as moment from "moment-timezone";
import { clearWaitingRequests } from "./fetcher";
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

const loadDataForDateRange = async (dateRange: Range): Promise<DataItem[]> => {
  clearWaitingRequests();
  const items = await Promise.allSettled([
    loadLastfm(dateRange),
    loadRead(dateRange),
  ]);
  return items.flatMap((maybeItems) => {
    if (maybeItems.status === "rejected") {
      return errorDataItem(
        {
          group: "Error",
          title: "Failed to load",
          content: "Failed to load some items for this date range",
        },
        dateRange
      );
    }
    return maybeItems.value;
  });
};

export type Loader = typeof loadDataForDateRange;

const container = document.getElementById("visualization");

const items: DataSetDataItem = new DataSet<DataItem>();
const end = moment.tz("UTC").endOf("day");
const start = end.clone().subtract(5, "day").startOf("day");
const options: TimelineOptions = {
  stack: true,
  start: start.toDate(),
  end: end.toDate(),
  moment: (date) => moment(date).utc(),
  groupHeightMode: "auto",
};
const timeline = new Timeline(container, items, options);
const groups = ["Music", "Read"] as const;
export type Group = typeof groups[number];
const stackGroup = (group: Group): boolean => group === "Music";

const timelineGroups: TimelineGroup[] = groups.map((group) => ({
  content: group,
  subgroupStack: stackGroup(group),
  id: group,
}));
timeline.setGroups(timelineGroups);
const updateTimelineForDateRange = async (dateRange: Range): Promise<void> => {
  const data: DataItem[] = await loadDataForDateRange(dateRange);

  items.clear();
  items.add(data);
};

timeline.on("rangechanged", (properties: TimelineWindow) => {
  updateTimelineForDateRange({
    start: moment.tz(properties.start, "UTC"),
    end: moment.tz(properties.end, "UTC"),
  }).then(() => {});
});

updateTimelineForDateRange({ start, end }).then(() => {});
