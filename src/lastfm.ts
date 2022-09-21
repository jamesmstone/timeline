import { errorDataItem, Loader } from "./main";
import {
  chunkRange,
  diff,
  expandToMonth,
  expandToYear,
  Interval,
  overAWeek,
  overDays,
  overWeeks,
  Range,
} from "./range";
import { DataItem } from "vis-timeline";
import * as moment from "moment";
import { addTTL, datasetteFetch } from "./datasette";

type listenDetail = {
  "url:1": string;
  image: string;
  "plays:1": number;
  "id:2": number;
  date_uts: string;
  mbid: string;
  plays: number;
  "id:1": number;
  "plays:2": number;
  "date_#text": string;
  "image:1": string;
  "@attr_nowplaying": null;
  url: string;
  "mbid:1": string;
  loved: string;
  streamable: string;
  artists_id: number;
  name: string;
  albums_id: number;
  id: number;
  tracks_id: number;
  "name:2": string;
  "name:1": string;
  "mbid:2": string;
};

type listenSummary = { day: string; count: number };

const interval: Interval = "month";

const firstLastFM = "2012-10-01";
const loadLastfmDay = async (dateRange: Range) => {
  const loadDateRange = expandToMonth(dateRange);
  const ranges = chunkRange(loadDateRange, interval);
  const data: PromiseSettledResult<listenDetail[]>[] = await Promise.allSettled(
    ranges.map(async ({ start, end }): Promise<listenDetail[]> => {
      if (end.isBefore(firstLastFM)) return [];
      return await datasetteFetch(
        addTTL(
          `https://lastfm.jamesst.one/music/listen_details.json?_json=image&_json=image:1&date_uts__lt=${end.unix()}&_sort_desc=date_uts&date_uts__gte=${start.unix()}&_shape=array`,
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
            group: "Music",
            content: d.reason,
            title: "Loading Error",
          },
          ranges[i]
        ),
      ];
    }
    return d.value.map((listenDetail) => {
      return {
        group: "Music",
        content: `<img alt="${listenDetail.name}" loading="lazy" src="${listenDetail.image[0]["#text"]}"/>${listenDetail.name} `,
        title: listenDetail.name,
        start: moment.unix(parseInt(listenDetail.date_uts)).toDate(),
        end: moment
          .unix(parseInt(listenDetail.date_uts))
          .add(3, "minute")
          .toDate(),
      };
    });
  });
};
const loadLastfmDaySummary = async (dateRange: Range) => {
  const loadDateRange = expandToMonth(dateRange);
  const ranges = chunkRange(loadDateRange, interval);
  const data: PromiseSettledResult<listenSummary[]>[] =
    await Promise.allSettled(
      ranges.map(async ({ start, end }): Promise<listenSummary[]> => {
        if (end.isBefore(firstLastFM)) return [];
        const url = `https://lastfm.jamesst.one/music.json?_shape=array&sql=select
  strftime(
    '%Y-%m-%d',
    datetime(date_uts, 'unixepoch', 'localtime')
  ) AS day,
  COUNT(rowid) AS count
from
  listens
where date_uts < ${end.unix()}
and date_uts >= ${start.unix()}
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
            group: "Music",
            content: d.reason,
            title: "Loading Error",
          },
          ranges[i]
        ),
      ];
    }
    return d.value.map((listenSummary) => ({
      group: "Music",
      content: `Listened to  ${listenSummary.count} songs on ${listenSummary.day} `,
      title: `Listens: ${listenSummary.count}`,
      start: moment(listenSummary.day).toDate(),
      end: moment(listenSummary.day).add(1, "day").startOf("day").toDate(),
    }));
  });
};

const loadLastfmMonthSummary = async (
  dateRange: Range
): Promise<DataItem[]> => {
  const loadDateRange = expandToYear(dateRange);
  const ranges = chunkRange(loadDateRange, "year");
  const data: PromiseSettledResult<listenSummary[]>[] =
    await Promise.allSettled(
      ranges.map(async ({ start, end }): Promise<listenSummary[]> => {
        if (end.isBefore(firstLastFM)) return [];
        const url = `https://lastfm.jamesst.one/music.json?_shape=array&sql=select
  strftime(
    '%Y-%m-01',
    datetime(date_uts, 'unixepoch', 'localtime')
  ) AS day,
  COUNT(rowid) AS count
from
  listens
where date_uts < ${end.unix()}
and date_uts >= ${start.unix()}
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
            group: "Music",
            content: d.reason,
            title: "Loading Error",
          },
          ranges[i]
        ),
      ];
    }
    return d.value.map((listenSummary) => ({
      group: "Music",
      content: `Listened to  ${listenSummary.count} songs during ${moment(
        listenSummary.day
      ).format("MMM YY")} `,
      title: `Listens: ${listenSummary.count}`,
      start: moment(listenSummary.day).toDate(),
      end: moment(listenSummary.day).add(1, "month").startOf("month").toDate(),
    }));
  });
};

export const loadLastfm: Loader = async (dateRange): Promise<DataItem[]> => {
  if (dateRange.end.isBefore(firstLastFM)) return [];
  if (overWeeks(6, dateRange)) {
    return await loadLastfmMonthSummary(dateRange);
  }
  if (overDays(5, dateRange)) {
    return await loadLastfmDaySummary(dateRange);
  }
  return await loadLastfmDay(dateRange);
};
