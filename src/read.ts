import { errorDataItem, Group, Loader } from "./main";
import {
  chunkRange,
  expandToDecade,
  expandToMonth,
  expandToYear,
  Interval,
  overDays,
  overWeeks,
  Range,
} from "./range";
import { DataItem } from "vis-timeline";
import * as moment from "moment";
import { addTTL, datasetteFetch } from "./datasette";

type readDetail = {
  date: string;
  image: string;
  date_time: number;
  hnurl: string;
  description: string;
  title: string;
  url: string;
};

type readSummary = { day: string; count: number };

const interval: Interval = "month";

const firstRead = "2012-10-01";
const group: Group = "Read";
const loadReadDay = async (dateRange: Range) => {
  const loadDateRange = expandToMonth(dateRange);
  const ranges = chunkRange(loadDateRange, interval);
  const data: PromiseSettledResult<readDetail[]>[] = await Promise.allSettled(
    ranges.map(async ({ start, end }): Promise<readDetail[]> => {
      if (end.isBefore(firstRead) || start.isAfter(moment())) return [];
      return await datasetteFetch(
        addTTL(
          encodeURI(`https://api-read.jamesst.one/readingList.json?_shape=array&sql=with dates as (
  select
    unixepoch(date) as date_time,
    *
  from
    read
)
select
  *
from
  dates
where date_time < ${end.unix()}
and date_time >= ${start.unix()}
order by
  date_time desc`),
          dateRange
        )
      );
    })
  );
  return data.flatMap((d, i): DataItem[] => {
    if (d.status === "rejected") {
      return [
        errorDataItem(
          {
            group: group,
            content: d.reason,
            title: "Loading Error",
          },
          ranges[i]
        ),
      ];
    }
    return d.value.map((detail) => {
      const truncatedTitle = detail.title.slice(0, 30);
      return {
        group: group,
        content: `<img height="34px" alt="${detail.title}" loading="lazy" src="${detail.image}"/>${truncatedTitle}`,
        title: detail.title,
        start: moment.unix(detail.date_time).toDate(),
      };
    });
  });
};
const loadReadDaySummary = async (dateRange: Range) => {
  const loadDateRange = expandToMonth(dateRange);
  const ranges = chunkRange(loadDateRange, interval);
  const data: PromiseSettledResult<readSummary[]>[] = await Promise.allSettled(
    ranges.map(async ({ start, end }): Promise<readSummary[]> => {
      if (end.isBefore(firstRead) || start.isAfter(moment())) return [];
      const url = `https://api-read.jamesst.one/readingList.json?_shape=array&sql=select
  strftime('%Y-%m-%d', date) AS day,
  COUNT(rowid) AS count
from
  read
where unixepoch(date) < ${end.unix()}
and unixepoch(date) >= ${start.unix()}
group by
  1
order by
  1 desc
`;
      return await datasetteFetch(addTTL(encodeURI(url), dateRange));
    })
  );
  return data.flatMap((d, i): DataItem[] => {
    if (d.status === "rejected") {
      return [
        errorDataItem(
          {
            group: group,
            content: d.reason,
            title: "Loading Error",
          },
          ranges[i]
        ),
      ];
    }
    return d.value.map((summary) => ({
      group: group,
      content: `Read  ${summary.count} articles on ${summary.day} `,
      title: `Read: ${summary.count}`,
      start: moment(summary.day).toDate(),
      end: moment(summary.day).add(1, "day").startOf("day").toDate(),
    }));
  });
};

const loadReadMonthSummary = async (dateRange: Range): Promise<DataItem[]> => {
  const loadDateRange = expandToYear(dateRange);
  const ranges = chunkRange(loadDateRange, "year");
  const data: PromiseSettledResult<readSummary[]>[] = await Promise.allSettled(
    ranges.map(async ({ start, end }): Promise<readSummary[]> => {
      if (end.isBefore(firstRead) || start.isAfter(moment())) return [];
      const url = `https://api-read.jamesst.one/readingList.json?_shape=array&sql=select
  strftime('%Y-%m-01', date) AS day,
  COUNT(rowid) AS count
from
  read
where unixepoch(date) < ${end.unix()}
and unixepoch(date) >= ${start.unix()}
group by
  1
order by
  1 desc
`;
      return await datasetteFetch(addTTL(encodeURI(url), dateRange));
    })
  );
  return data.flatMap((d, i): DataItem[] => {
    if (d.status === "rejected") {
      return [
        errorDataItem(
          {
            group: group,
            content: d.reason,
            title: "Loading Error",
          },
          ranges[i]
        ),
      ];
    }
    return d.value.map((summary) => ({
      group: group,
      content: `Read  ${summary.count} articles during ${moment(
        summary.day
      ).format("MMM YY")} `,
      title: `Reads: ${summary.count}`,
      start: moment(summary.day).toDate(),
      end: moment(summary.day).add(1, "month").startOf("month").toDate(),
    }));
  });
};

const loadReadYearSummary = async (dateRange: Range): Promise<DataItem[]> => {
  const loadDateRange = expandToDecade(dateRange);
  const ranges = chunkRange(loadDateRange, "year");
  const data: PromiseSettledResult<readSummary[]>[] = await Promise.allSettled(
    ranges.map(async ({ start, end }): Promise<readSummary[]> => {
      if (end.isBefore(firstRead) || start.isAfter(moment())) return [];
      const url = `https://api-read.jamesst.one/readingList.json?_shape=array&sql=select
  strftime('%Y-01-01', date) AS day,
  COUNT(rowid) AS count
from
  read
where unixepoch(date) < ${end.unix()}
and unixepoch(date) >= ${start.unix()}
group by
  1
order by
  1 desc
`;
      return await datasetteFetch(addTTL(encodeURI(url), dateRange));
    })
  );
  return data.flatMap((d, i): DataItem[] => {
    if (d.status === "rejected") {
      return [
        errorDataItem(
          {
            group: group,
            content: d.reason,
            title: "Loading Error",
          },
          ranges[i]
        ),
      ];
    }
    return d.value.map((summary) => ({
      group: group,
      content: `Read  ${summary.count} articles during ${moment(
        summary.day
      ).format("YYYY")} `,
      title: `Reads: ${summary.count}`,
      start: moment(summary.day).toDate(),
      end: moment(summary.day).add(1, "year").startOf("year").toDate(),
    }));
  });
};

export const loadRead: Loader = async (dateRange): Promise<DataItem[]> => {
  if (dateRange.end.isBefore(firstRead) || dateRange.start.isAfter(moment())) {
    return [];
  }
  if (overWeeks(52, dateRange)) {
    return await loadReadYearSummary(dateRange);
  }
  if (overWeeks(6, dateRange)) {
    return await loadReadMonthSummary(dateRange);
  }
  if (overDays(5, dateRange)) {
    return await loadReadDaySummary(dateRange);
  }
  return await loadReadDay(dateRange);
};
