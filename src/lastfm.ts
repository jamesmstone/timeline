import { errorDataItem, Loader } from "./main";
import { chunkRange, expandToMonth, Interval, overAWeek, Range } from "./range";
import { DataItem } from "vis-timeline";
import * as moment from "moment";
import { datasetteFetch } from "./datasette";

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

const interval: Interval = "month";

const loadLastfmSummary = async (dateRange: Range) => {
  const loadDateRange = expandToMonth(dateRange);
  const ranges = chunkRange(loadDateRange, interval);
  const data: PromiseSettledResult<listenDetail[]>[] = await Promise.allSettled(
    ranges.map(
      async ({ start, end }): Promise<listenDetail[]> =>
        await datasetteFetch(
          `https://lastfm.jamesst.one/music/listen_details.json?_json=image&_json=image:1&date_uts__lt=${end.unix()}&_sort_desc=date_uts&date_uts__gte=${start.unix()}&_shape=array`
        )
    )
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
type listenSummary = { day: string; count: number };
const loadLastfmDay = async (dateRange: Range) => {
  const loadDateRange = expandToMonth(dateRange);
  const ranges = chunkRange(loadDateRange, interval);
  const data: PromiseSettledResult<listenSummary[]>[] =
    await Promise.allSettled(
      ranges.map(async ({ start, end }): Promise<listenSummary[]> => {
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
        return await datasetteFetch(encodeURI(url));
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

export const loadLastfm: Loader = async (dateRange): Promise<DataItem[]> => {
  if (overAWeek(dateRange)) {
    return await loadLastfmSummary(dateRange);
  }
  return await loadLastfmDay(dateRange);
};
