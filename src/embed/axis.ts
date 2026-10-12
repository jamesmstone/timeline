import moment from "moment";

export type Tick = { at: number; label: string; major: boolean };

type Step = {
  approx: number;
  amount: number;
  unit: "hour" | "day" | "week" | "month" | "year";
  format: string;
};

const hour = 60 * 60 * 1000;
const day = 24 * hour;

const steps: Step[] = [
  { approx: hour, amount: 1, unit: "hour", format: "HH:mm" },
  { approx: 3 * hour, amount: 3, unit: "hour", format: "HH:mm" },
  { approx: 6 * hour, amount: 6, unit: "hour", format: "HH:mm" },
  { approx: 12 * hour, amount: 12, unit: "hour", format: "HH:mm" },
  { approx: day, amount: 1, unit: "day", format: "ddd D" },
  { approx: 2 * day, amount: 2, unit: "day", format: "D MMM" },
  { approx: 7 * day, amount: 1, unit: "week", format: "D MMM" },
  { approx: 30 * day, amount: 1, unit: "month", format: "MMM" },
  { approx: 91 * day, amount: 3, unit: "month", format: "MMM" },
  { approx: 182 * day, amount: 6, unit: "month", format: "MMM" },
  { approx: 365 * day, amount: 1, unit: "year", format: "YYYY" },
];

const first = (start: number, step: Step): moment.Moment => {
  const t = moment.utc(start);
  switch (step.unit) {
    case "hour":
      t.startOf("day");
      break;
    case "day":
      t.startOf("day");
      break;
    case "week":
      t.startOf("isoWeek");
      break;
    case "month":
      t.startOf("year");
      break;
    case "year":
      t.startOf("year");
      break;
  }
  while (t.valueOf() < start) t.add(step.amount, step.unit);
  return t;
};

// A tick that opens a larger unit carries it in bold, the way vis marks its
// major labels: the day under hourly ticks, the year under monthly ones.
const major = (t: moment.Moment, step: Step): string | null => {
  if (step.unit === "hour" && t.hours() === 0) return t.format("ddd D");
  if (step.unit === "month" && t.month() === 0) return t.format("YYYY");
  return null;
};

export const ticks = (
  start: number,
  end: number,
  length: number,
  spacing: number,
): Tick[] => {
  const span = end - start;
  const wanted = Math.max(1, Math.floor(length / spacing));
  const step =
    steps.find((s) => span / s.approx <= wanted) ?? steps[steps.length - 1];
  const amount =
    step.unit === "year"
      ? Math.max(1, Math.ceil(span / step.approx / wanted))
      : step.amount;
  const resolved = { ...step, amount };
  const out: Tick[] = [];
  for (
    const t = first(start, resolved);
    t.valueOf() <= end;
    t.add(resolved.amount, resolved.unit)
  ) {
    const label = major(t, resolved);
    out.push({
      at: t.valueOf(),
      label: label ?? t.format(resolved.format),
      major: label !== null,
    });
  }
  return out;
};
