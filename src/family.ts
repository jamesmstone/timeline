import { Loader, TimelineDataItem } from "./main";
import { DataItem } from "vis-timeline/peer";
import { fetcher } from "./fetcher";
import moment = require("moment");

type event = {
  date: string | null;
  place: { place: string };
} | null;

type familyNode = {
  name: { fullName: string };
  death: (event & { died: boolean }) | null;
  birth: (event & { born: boolean }) | null;
  id: string;
};
type FamilyJSON = {
  data: {
    allIndividual: {
      nodes: familyNode[];
    };
  };
};
let cachedFamilyJson: FamilyJSON | null = null;
const fetchFamily = async (): Promise<FamilyJSON> => {
  if (cachedFamilyJson !== null) return cachedFamilyJson;
  const familyRes = await fetcher(
    "https://family.jamesst.one/individualsAPI.json"
  );

  cachedFamilyJson = await familyRes.json();
  return cachedFamilyJson;
};
export const loadFamily: Loader = async (
  dateRange,
  search
): Promise<TimelineDataItem> => {
  const familyJson = await fetchFamily();
  const data: DataItem[] = familyJson.data.allIndividual.nodes.flatMap((i) => {
    const hasDeathDate =
      i.death !== null &&
      i.death.hasOwnProperty("date") &&
      i.death.date !== null;
    const hasBirthDate =
      i.birth !== null &&
      i.birth.hasOwnProperty("date") &&
      i.birth.date !== null;
    const content = i.name.fullName;
    const title = i.name.fullName;
    if (hasBirthDate) {
      return [
        {
          id: i.id,
          content,
          title,
          group: "Family",
          start: moment(i.birth.date).toDate(),
          ...(hasDeathDate && {
            end: moment(i.death.date).toDate(),
          }),
        },
      ];
    }
    return [];
  });
  return {
    type: "timeline",
    data,
  };
};
