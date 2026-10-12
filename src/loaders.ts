import { Range } from "./range";
import {
  loadHeartRate,
  loadLastfm,
  loadRead,
  loadSleep,
  loadSteps,
  loadStressLevel,
} from "./datasetteLoaders";
import { loadFamily } from "./family";
import { Group, TimelineDataItem } from "./data";

export const loadDataForDateRange = async (
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
