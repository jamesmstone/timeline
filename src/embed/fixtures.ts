import { LaneData } from "./render";

const at = (iso: string) => new Date(iso);

const daily = (group: string, values: number[]) =>
  values.map((y, i) => {
    const start = at(`2026-10-0${i + 5}T00:00:00Z`);
    return {
      group,
      x: start,
      y,
      start,
      end: new Date(start.getTime() + 24 * 60 * 60 * 1000),
      content: "",
    };
  });

export const range = {
  start: at("2026-10-05T12:00:00Z"),
  end: at("2026-10-12T12:00:00Z"),
};

export const now = at("2026-10-12T12:00:00Z");

// A week as the loaders shape it, with hostile text where the sources carry
// free text: track names and reading titles are not ours to trust.
export const lanes: LaneData[] = [
  {
    group: "Heart rate",
    result: {
      type: "graph",
      graphOptions: { style: "line" },
      data: daily("Heart rate", [61, 64, 70, 63, 66, 62, 65]),
    },
  },
  {
    group: "Stress level",
    result: {
      type: "graph",
      graphOptions: { style: "line" },
      data: [
        ...daily("Stress level", [30, 41, 35, 38, 33, 36, 34]),
        {
          group: "Stress level",
          x: at("2026-10-11T00:00:00Z"),
          y: null,
          content: "",
        },
      ],
    },
  },
  {
    group: "Sleep",
    result: {
      type: "graph",
      data: daily("Sleep", [7.5, 6.2, 8.1, 5.9, 7, 7.7, 6.8]),
    },
  },
  { group: "Steps", result: null },
  {
    group: "Music",
    result: {
      type: "timeline",
      data: [
        {
          group: "Music",
          content: '<img src="x"/>ignored',
          title: `</text><script>alert("x")</script> & "quotes" 'too'\u0001`,
          start: at("2026-10-08T10:00:00Z"),
          end: at("2026-10-09T10:00:00Z"),
        },
      ],
    },
  },
  {
    group: "Family",
    result: {
      type: "timeline",
      data: Array.from({ length: 40 }, (_, i) => ({
        group: "Family",
        content: `Relative ${i}`,
        title: `Relative ${i}`,
        start: at("1960-01-01T00:00:00Z"),
        end: at("2026-10-12T12:00:00Z"),
      })),
    },
  },
  {
    group: "Read",
    result: {
      type: "timeline",
      data: [
        {
          group: "Read",
          content: "<img/>",
          title: "A <b>bold</b> claim & more",
          start: at("2026-10-07T09:00:00Z"),
        },
      ],
    },
  },
];
