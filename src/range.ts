import * as moment from "moment-timezone";
import { unitOfTime } from "moment";

export type Range = { start: moment.Moment; end: moment.Moment };
export type Interval = moment.unitOfTime.DurationConstructor;

export const capNow = (time: moment.Moment) => {
  const now = moment();
  if (time.isAfter()) {
    return now;
  }
  return time;
};

export const diff = (
  unit: moment.unitOfTime.Diff,
  { start, end }: Range,
): number => start.diff(end, unit, true);
const diffWeeks = (range: Range): number => diff("week", range);
const diffDays = (range: Range): number => diff("day", range);
export const overWeeks = (amount: number, range: Range): boolean =>
  Math.abs(diffWeeks(range)) > amount;
export const overDays = (amount: number, range: Range): boolean =>
  Math.abs(diffDays(range)) > amount;
export const overAWeek = (range: Range): boolean => overWeeks(1, range);

export type ExpandToInterval = unitOfTime.StartOf;
export const expandToInterval = (
  { start, end }: Range,
  interval: ExpandToInterval,
): Range => ({
  start: start.clone().startOf(interval),
  end: end.clone().endOf(interval),
});

export const expandToWeek = (range: Range): Range =>
  expandToInterval(range, "isoWeek");
export const expandToMonth = (range: Range): Range =>
  expandToInterval(range, "month");
export const expandToYear = (range: Range): Range =>
  expandToInterval(range, "year");

export const expandToDecade = ({ start, end }: Range): Range => {
  return {
    start: start.clone().startOf("year").subtract("9", "years"),
    end: end.clone().endOf("year"),
  };
};

export const createRange = (start: Range["start"], end: Range["end"]) => ({
  start: start.clone(),
  end: end.clone(),
});
const isEmptyRange = ({ start, end }: Range): boolean => start.isSame(end);

const isRangeBeforeRange = (a: Range, b: Range) => {
  const { end: aTo } = a;
  const { start: bFrom } = b;
  return aTo.isSameOrBefore(bFrom);
};
const nextInterval = (time: moment.Moment, interval: Interval) =>
  time.clone().add(1, interval).startOf(interval);
export const chunkRange = (range: Range, interval: Interval): Range[] => {
  const { start, end } = range;
  if (start.clone().add(1, interval).isAfter(end)) {
    // The range to chunk is smaller than the interval,
    // so we need to just return the provided range
    return [createRange(start, end)];
  }
  const first = createRange(start.clone(), nextInterval(start, interval));
  const last = createRange(end.clone().startOf(interval), end.clone());

  const middle: Range[] = [];
  for (
    let cur: Range = createRange(
      nextInterval(first.start.clone(), interval),
      nextInterval(first.end.clone(), interval),
    );
    isRangeBeforeRange(cur, last);
    cur = createRange(
      nextInterval(cur.start.clone(), interval),
      nextInterval(cur.end.clone(), interval),
    )
  ) {
    middle.push(cur);
  }
  return [first, ...middle, last].filter((r) => !isEmptyRange(r));
};
