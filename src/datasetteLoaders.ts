import {
  errorDataItem,
  GraphDataItem,
  graphErrorDataItem,
  GraphTimelineDataItem,
  Group,
  Loader,
  TimelineDataItem,
} from "./main";
import {
  capNow,
  chunkRange,
  expandToDecade,
  expandToInterval,
  ExpandToInterval,
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

type Search = string | undefined;

type DateFormat = "ISO" | "unix_epoch";

const dayDateFormatter = (
  date: moment.Moment,
  dateFormat: DateFormat,
): string => {
  if (dateFormat === "ISO") {
    return "'" + date.format("YYYY-MM-DD HH:mm:ss") + "'";
  }
  return date.unix().toString();
};

const fixedEncodeURI = (uri) => encodeURI(uri).replaceAll("+", "%2B");
const escapeSQLString = (string) => string.replaceAll("'", "''");
const loadDay = async <Detail extends BaseDetail, Summary extends BaseSummary>(
  dateRange: Range,
  search: Search = "",
  options: DatasetteOptions<Detail, Summary>,
): Promise<TimelineDataItem["result"]> => {
  const {
    group,
    baseAPI,
    baseSQL,
    start: dataStart,
    end: dataEnd,
    detailContentFormatter,
    detailTitleFormatter,
    graphOptions,
    detailType = "timeline",
    expandToInterval: expandInterval = "month",
    chunkInterval = "month",
    dateFormat = "unix_epoch",
  } = options;
  const loadDateRange = expandToInterval(dateRange, expandInterval);
  const ranges = chunkRange(loadDateRange, chunkInterval);
  const data: PromiseSettledResult<Detail[]>[] = await Promise.allSettled(
    ranges.map(async ({ start, end }): Promise<Detail[]> => {
      if (end.isBefore(dataStart) || start.isAfter(dataEnd)) return [];

      const sql = `${baseSQL} select *
from data
where date_time < ${dayDateFormatter(end, dateFormat)}
  and date_time >= ${dayDateFormatter(start, dateFormat)}
  and search like '%${escapeSQLString(search)}%'
order by date_time desc`;
      return await datasetteFetch(
        addTTL(
          fixedEncodeURI(`${baseAPI}?&_shape=array&sql=${sql}`),
          dateRange,
        ),
      );
    }),
  );
  if (detailType === "timeline") {
    return {
      type: "timeline",
      data: data.flatMap((d, i): DataItem[] => {
        if (d.status === "rejected") {
          return [
            errorDataItem(
              {
                group: group,
                content: d.reason,
                title: "Loading Error",
              },
              ranges[i],
            ),
          ];
        }
        return d.value.map((detail) => {
          return {
            group: group,
            content: detailContentFormatter(detail, options),
            title: detailTitleFormatter(detail, options),
            start:
              dateFormat === "ISO"
                ? moment(detail.date_time).toDate()
                : moment.unix(detail.date_time).toDate(),
            ...(detail.hasOwnProperty("date_time_end") && {
              end:
                dateFormat === "ISO"
                  ? moment(detail.date_time_end).toDate()
                  : moment.unix(detail.date_time_end).toDate(),
            }),
          };
        });
      }),
    };
  }
  return {
    type: detailType,
    graphOptions,
    data: data.flatMap((d, i): GraphDataItem[] => {
      if (d.status === "rejected") {
        return [
          graphErrorDataItem(
            {
              group: group,
              content: d.reason,
              title: "Loading Error",
            },
            ranges[i],
          ),
        ];
      }
      return d.value.map((detail): GraphDataItem => {
        const start =
          dateFormat === "ISO"
            ? moment(detail.date_time).toDate()
            : moment.unix(detail.date_time).toDate();
        return {
          x: start,
          y: detail.value,
          group: group,
          content: detailContentFormatter(detail, options),
          title: detailTitleFormatter(detail, options),
          start,
          ...(detail.hasOwnProperty("date_time_end") && {
            end:
              dateFormat === "ISO"
                ? moment(detail.date_time_end).toDate()
                : moment.unix(detail.date_time_end).toDate(),
          }),
        };
      });
    }),
  };
};
const loadDaySummary = async <
  Detail extends BaseDetail,
  Summary extends BaseSummary,
>(
  dateRange: Range,
  search: Search = "",
  options: DatasetteOptions<Detail, Summary>,
): Promise<GraphTimelineDataItem> => {
  const {
    group,
    baseAPI,
    baseSQL,
    start: dataStart,
    end: dataEnd,
    summaryContentFormatter,
    summaryTitleFormatter,
    aggregateFunction = "count",
    graphOptions,
    dateFormat = "unix_epoch",
  } = options;
  const loadDateRange = expandToMonth(dateRange);
  const ranges = chunkRange(loadDateRange, "month");
  const data: PromiseSettledResult<Summary[]>[] = await Promise.allSettled(
    ranges.map(async ({ start, end }): Promise<Summary[]> => {
      if (end.isBefore(dataStart) || start.isAfter(dataEnd)) return [];
      const sql = `${baseSQL} select
  strftime('%Y-%m-%d', ${dateFormat === "unix_epoch" ? "datetime(date_time, 'unixepoch')" : "date_time"}  ) AS day,
  ${aggregateFunction}(value) AS aggregate
from
  data
where date_time < ${dayDateFormatter(end, dateFormat)}
and date_time >= ${dayDateFormatter(start, dateFormat)}
and search like '%${escapeSQLString(search)}%'
group by
  1
order by
  1 desc`;
      const url = `${baseAPI}?&_shape=array&sql=${sql}`;
      return await datasetteFetch(addTTL(fixedEncodeURI(url), dateRange));
    }),
  );
  return {
    type: "graph",
    graphOptions,
    data: data.flatMap((d, i): GraphDataItem[] => {
      if (d.status === "rejected") {
        return [
          graphErrorDataItem(
            {
              group: group,
              content: d.reason,
              title: "Loading Error",
            },
            ranges[i],
          ),
        ];
      }
      return d.value.map((d) => {
        const start = moment(d.day).toDate();
        const periodLabel = moment(d.day).format("D MMM YY");
        return {
          group,
          content: summaryContentFormatter(d, periodLabel, options),
          title: summaryTitleFormatter(d, periodLabel, options),
          x: start,
          y: d.aggregate,
          start,
          end: capNow(moment(d.day).add(1, "day").startOf("day")).toDate(),
        };
      });
    }),
  };
};

const loadMonthSummary = async <
  Detail extends BaseDetail,
  Summary extends BaseSummary,
>(
  dateRange: Range,
  search: Search = "",
  options: DatasetteOptions<Detail, Summary>,
): Promise<GraphTimelineDataItem> => {
  const {
    group,
    baseAPI,
    baseSQL,
    start: dataStart,
    end: dataEnd,
    summaryContentFormatter,
    summaryTitleFormatter,
    aggregateFunction = "count",
    graphOptions,
    dateFormat = "unix_epoch",
  } = options;
  const loadDateRange = expandToYear(dateRange);
  const ranges = chunkRange(loadDateRange, "year");
  const data: PromiseSettledResult<Summary[]>[] = await Promise.allSettled(
    ranges.map(async ({ start, end }): Promise<Summary[]> => {
      if (end.isBefore(dataStart) || start.isAfter(dataEnd)) return [];
      const sql = `${baseSQL}select
  strftime('%Y-%m-01', ${dateFormat === "unix_epoch" ? "datetime(date_time, 'unixepoch')" : "date_time"}  ) AS day,
  ${aggregateFunction}(value) AS aggregate
from
  data
 where date_time < ${dayDateFormatter(end, dateFormat)}
   and date_time >= ${dayDateFormatter(start, dateFormat)}
and search like '%${escapeSQLString(search)}%'
group by
  1
order by
  1 desc`;
      const url = `${baseAPI}?&_shape=array&sql=${sql}`;
      return await datasetteFetch(addTTL(fixedEncodeURI(url), dateRange));
    }),
  );
  return {
    type: "graph",
    graphOptions,
    data: data.flatMap((d, i): GraphDataItem[] => {
      if (d.status === "rejected") {
        return [
          graphErrorDataItem(
            {
              group: group,
              content: d.reason,
              title: "Loading Error",
            },
            ranges[i],
          ),
        ];
      }
      return d.value.map((d) => {
        const start = moment(d.day).toDate();
        const periodLabel = moment(d.day).format("MMM YY");
        return {
          group,
          content: summaryContentFormatter(d, periodLabel, options),
          title: summaryTitleFormatter(d, periodLabel, options),
          x: start,
          y: d.aggregate,
          start,
          end: capNow(moment(d.day).add(1, "month").startOf("month")).toDate(),
        };
      });
    }),
  };
};

const loadYearSummary = async <
  Detail extends BaseDetail,
  Summary extends BaseSummary,
>(
  dateRange: Range,
  search: Search = "",
  options: DatasetteOptions<Detail, Summary>,
): Promise<GraphTimelineDataItem> => {
  const {
    group,
    baseAPI,
    baseSQL,
    start: dataStart,
    end: dataEnd,
    summaryContentFormatter,
    summaryTitleFormatter,
    aggregateFunction = "count",
    graphOptions,
    dateFormat = "unix_epoch",
  } = options;
  const loadDateRange = expandToDecade(dateRange);
  const ranges = chunkRange(loadDateRange, "year");
  const data: PromiseSettledResult<Summary[]>[] = await Promise.allSettled(
    ranges.map(async ({ start, end }): Promise<Summary[]> => {
      if (end.isBefore(dataStart) || start.isAfter(dataEnd)) return [];
      const sql = `${baseSQL} select
  strftime('%Y-01-01', ${dateFormat === "unix_epoch" ? "datetime(date_time, 'unixepoch')" : "date_time"}  ) AS day,
  ${aggregateFunction}(value) AS aggregate
from
  data
where date_time < ${dayDateFormatter(end, dateFormat)}
  and date_time >= ${dayDateFormatter(start, dateFormat)}
and search like '%${escapeSQLString(search)}%'
group by
  1
order by
  1 desc`;
      const url = `${baseAPI}?&_shape=array&sql=${sql}`;
      return await datasetteFetch(addTTL(fixedEncodeURI(url), dateRange));
    }),
  );
  return {
    type: "graph",
    graphOptions,
    data: data.flatMap((d, i): GraphDataItem[] => {
      if (d.status === "rejected") {
        return [
          graphErrorDataItem(
            {
              group: group,
              content: d.reason,
              title: "Loading Error",
            },
            ranges[i],
          ),
        ];
      }
      return d.value.map((d) => {
        const start = moment(d.day).toDate();
        const periodLabel = moment(d.day).format("YYYY");
        return {
          group,
          content: summaryContentFormatter(d, periodLabel, options),
          title: summaryTitleFormatter(d, periodLabel, options),
          x: start,
          y: d.aggregate,
          start,
          end: capNow(moment(d.day).add(1, "year").startOf("year")).toDate(),
        };
      });
    }),
  };
};

type BaseDetail = { date_time: number; date_time_end?: number; value: number };
type BaseSummary = { day: string; aggregate: number };
type AggregateFunction = "count" | "sum" | "avg";
type DatasetteOptions<
  Detail extends BaseDetail,
  Summary extends BaseSummary,
> = Partial<{
  dateFormat: DateFormat;
  expandToInterval: ExpandToInterval;
  chunkInterval: Interval;
  detailType: TimelineDataItem["result"]["type"];
  graphOptions: GraphTimelineDataItem["graphOptions"];
  aggregateFunction: AggregateFunction;
  start: moment.Moment;
  end: moment.Moment;
  summaryContentFormatter: (
    summary: Summary,
    periodLabel: string,
    options: DatasetteOptions<Detail, Summary>,
  ) => GraphDataItem["content"];
  summaryTitleFormatter: (
    summary: Summary,
    periodLabel: string,
    options: DatasetteOptions<Detail, Summary>,
  ) => GraphDataItem["title"];
  detailContentFormatter: (
    detail: Detail,
    options: DatasetteOptions<Detail, Summary>,
  ) => DataItem["content"];
  detailTitleFormatter: (
    detail: Detail,
    options: DatasetteOptions<Detail, Summary>,
  ) => DataItem["title"];
}> & { baseAPI: string; baseSQL: string; group: Group };

const getDatasetteLoader = <
  Detail extends BaseDetail,
  Summary extends BaseSummary,
>(
  options: DatasetteOptions<Detail, Summary>,
): Loader => {
  const { start, end } = options;
  return async (dateRange, search): Promise<TimelineDataItem> => {
    if (dateRange.end.isBefore(start) || dateRange.start.isAfter(end)) {
      return {
        options: { dateRange, search },
        result: { type: "timeline", data: [] },
      };
    }
    if (overWeeks(52 * 5, dateRange)) {
      return {
        options: { dateRange, search },
        result: await loadYearSummary(dateRange, search, options),
      };
    }
    if (overWeeks(52, dateRange)) {
      return {
        options: { dateRange, search },
        result: await loadMonthSummary(dateRange, search, options),
      };
    }
    if (overDays(5, dateRange)) {
      return {
        options: { dateRange, search },
        result: await loadDaySummary(dateRange, search, options),
      };
    }
    return {
      options: { dateRange, search },
      result: await loadDay(dateRange, search, options),
    };
  };
};

type readDetail = {
  date: string;
  value: number;
  image: string;
  date_time: number;
  hnurl: string;
  description: string;
  title: string;
  url: string;
};

type readSummary = { day: string; aggregate: number };

export const loadRead: Loader = getDatasetteLoader<readDetail, readSummary>({
  baseAPI: "https://api-read.jamesst.one/readingList.json",
  baseSQL: `with data as (select
                  unixepoch(date)   as date_time,
                  title || '
' || description                    as search,
                  1                 as value,
                  title             as title,
                  case 
                    when screenshot = '' then image
                    else screenshot 
                  end               as image
              from read)`,
  group: "Read",
  start: moment("2012-10-01"),
  end: moment(),
  detailContentFormatter: (detail) => {
    const truncatedTitle = detail.title.slice(0, 30);
    return `<img height="34px" alt="${
      detail.title
    }" loading="lazy" src="https://read.jamesst.one/${encodeURIComponent(
      detail.image,
    )}"/>${truncatedTitle}`;
  },
  detailTitleFormatter: ({ title }) => title,
  summaryContentFormatter: (summary, periodLabel) =>
    `Read  ${summary.aggregate} articles during ${periodLabel}`,
  summaryTitleFormatter: (summary, periodLabel) => `Read  ${summary.aggregate}`,
});

type listenDetail = {
  value: number;
  date_time: number;
  date_time_end: number;
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

type listenSummary = { day: string; aggregate: number };

export const loadLastfm: Loader = getDatasetteLoader<
  listenDetail,
  listenSummary
>({
  baseAPI: "https://lastfm.jamesst.one/music.json?_json=image&_json=image:1",
  baseSQL: `with data as (select date_uts as date_time, case when avg_estimated_duration is null then date_uts + 5 * 60 else date_uts + avg_estimated_duration end as date_time_end,
                     name || '
' || "name:2" as search,
1 as value,
                  *
              from listen_details)`,
  group: "Music",
  start: moment("2012-10-01"),
  end: moment(),
  detailContentFormatter: (listenDetail) => {
    return `<img height="34px" alt="${listenDetail.name}" loading="lazy" src="${listenDetail.image[0]["#text"]}"/>${listenDetail.name} ${listenDetail["name:1"]} `;
  },
  detailTitleFormatter: ({ name }) => name,
  summaryContentFormatter: (summary, periodLabel) =>
    `Listened to ${summary.aggregate} songs during ${periodLabel}`,
  summaryTitleFormatter: (summary, periodLabel) =>
    `Listened:  ${summary.aggregate}`,
});

const getGarminLoader = ({
  baseAPI,
  baseSQL,
  group,
  dateFormat,
  start,
  aggregateFunction = "avg",
}: {
  baseSQL: string;
  baseAPI: string;
  group: Group;
  start: moment.Moment;
  aggregateFunction?: AggregateFunction;
} & {
  dateFormat?: DatasetteOptions<BaseDetail, BaseSummary>["dateFormat"];
}): Loader =>
  getDatasetteLoader<BaseDetail, BaseSummary>({
    baseAPI,
    baseSQL,
    dateFormat,
    group,
    detailType: "graph",
    expandToInterval: "day",
    chunkInterval: "hour",
    graphOptions: { style: "line" },
    aggregateFunction,
    start,
    end: moment(),
    detailContentFormatter: (detail, { group }) =>
      group + " " + detail.date_time,
    detailTitleFormatter: (detail, { group }) => group + " " + detail.date_time,
    summaryContentFormatter: (summary, periodLabel) =>
      `Listened to ${summary.aggregate} songs during ${periodLabel}`,
    summaryTitleFormatter: (summary, periodLabel) =>
      `Listened:  ${summary.aggregate}`,
  });
export const loadHeartRate: Loader = getGarminLoader({
  dateFormat: "ISO",
  baseAPI: "https://garmin.jamesst.one/garmin_monitoring.json",
  baseSQL: `with data as (select timestamp as date_time,
                'heart_rate' as search,
                hr.heart_rate as value
              from monitoring_hr hr)`,
  group: "Heart rate",
  start: moment.unix(1464933600 - 1),
});
export const loadStressLevel: Loader = getGarminLoader({
  dateFormat: "ISO",
  baseAPI: "https://garmin.jamesst.one/garmin.json",
  baseSQL: `with data as (select
                            timestamp as date_time,
                            'stress_level' as search,
                            case
                              when stress <= 0 then null
                              else stress
                              end as value
                          from
                            stress)`,
  group: "Stress level",
  start: moment.unix(1506186180 - 1),
});

export const loadSteps: Loader = getGarminLoader({
  baseAPI: "https://garmin.jamesst.one/garmin_monitoring.json",
  baseSQL: `with data as (select
                            timestamp as date_time,
                            'steps' as search,
                            case
                              when steps is null then 0
                              else steps
                              end as value
                          from
                            monitoring)`,
  group: "Steps",
  start: moment.unix(1506186180 - 1),
  dateFormat: "ISO",
  aggregateFunction: "sum",
});
const getLanguageLoader = (language: Group): Loader =>
  getDatasetteLoader<BaseDetail, BaseSummary>({
    baseAPI: "https://wakatime.jamesst.one/wakatime.json",
    baseSQL: `with data as (select
    unixepoch(date) as date_time,
    unixepoch(date, '+1 day') as date_time_end,
    '${language}' as search,
    ${language} as value
  from
    languages
  where
    ${language} is not null
  )`,
    group: language,
    detailType: "graph",
    graphOptions: { style: "line" },
    aggregateFunction: "sum",
    start: moment("2019-03-01"),
    end: moment(),
    detailContentFormatter: (detail, { group }) =>
      group + " " + detail.date_time,
    detailTitleFormatter: (detail, { group }) => group + " " + detail.date_time,
    summaryContentFormatter: (summary, periodLabel) =>
      `Listened to ${summary.aggregate} songs during ${periodLabel}`,
    summaryTitleFormatter: (summary, periodLabel) =>
      `Listened:  ${summary.aggregate}`,
  });
export const loadJS = getLanguageLoader("JavaScript");
export const loadJava = getLanguageLoader("Java");
export const loadSQL = getLanguageLoader("SQL");
export const loadTS = getLanguageLoader("TypeScript");
