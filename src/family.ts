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
  const data: DataItem[] = familyJson.data.allIndividual.nodes.flatMap(
    ({ id, name: { fullName }, death, birth }) => {
      const matchesSearch = fullName
        .toLowerCase()
        .includes(search.toLowerCase());
      const hasSearch = search !== undefined;
      if (!matchesSearch && hasSearch) return [];
      const hasDeathDate =
        death !== null && death.hasOwnProperty("date") && death.date !== null;
      const hasBirthDate =
        birth !== null && birth.hasOwnProperty("date") && birth.date !== null;
      const content = fullName;
      const title = fullName;
      if (hasBirthDate) {
        return [
          {
            id,
            content,
            title,
            group: "Family",
            start: moment(birth.date).toDate(),
            ...(hasDeathDate && {
              end: moment(death.date).toDate(),
            }),
          },
        ];
      }
      return [];
    }
  );
  return {
    type: "timeline",
    data,
  };
};
