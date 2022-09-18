import * as moment from "moment";

export type Range = { start: moment.Moment; end: moment.Moment };
export type Interval = moment.unitOfTime.DurationConstructor;

export const overAWeek = ({ start, end }: Range): boolean => {
  const newStart = start.clone().add(1, "week");
  return newStart.isAfter(end);
};

export const expandToMonth = ({ start, end }: Range): Range => {
  return {
    start: start.clone().startOf("month"),
    end: end.clone().endOf("month"),
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
      nextInterval(first.end.clone(), interval)
    );
    isRangeBeforeRange(cur, last);
    cur = createRange(
      nextInterval(cur.start.clone(), interval),
      nextInterval(cur.end.clone(), interval)
    )
  ) {
    middle.push(cur);
  }
  return [first, ...middle, last].filter((r) => !isEmptyRange(r));
};
