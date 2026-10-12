import { Loader, TimelineDataItem } from "./data";
import { DataItem } from "vis-timeline/peer";
import { fetcher } from "./fetcher";
import moment from "moment";

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
// The embed server lives far longer than a page view, so the tree has to
// expire there rather than be fetched once for the life of the process.
const familyTTL = 60 * 60 * 1000;
let cachedFamilyJson: { json: FamilyJSON; at: number } | null = null;
const fetchFamily = async (): Promise<FamilyJSON> => {
  if (cachedFamilyJson !== null && Date.now() - cachedFamilyJson.at < familyTTL)
    return cachedFamilyJson.json;
  const familyRes = await fetcher(
    "https://family.jamesst.one/individualsAPI.json",
  );

  cachedFamilyJson = { json: await familyRes.json(), at: Date.now() };
  return cachedFamilyJson.json;
};
export const loadFamily: Loader = async (
  dateRange,
  search,
): Promise<TimelineDataItem> => {
  const familyJson = await fetchFamily();
  const data: DataItem[] = familyJson.data.allIndividual.nodes.flatMap(
    ({ id, name: { fullName }, death, birth }) => {
      const matchesSearch = fullName
        .toLowerCase()
        .includes(search.toLowerCase());
      const hasSearch = search !== undefined;
      if (!matchesSearch && hasSearch) return [];
      const hasDied = death !== null && death.died;
      const hasDeathDate =
        hasDied && death.hasOwnProperty("date") && death.date !== null;
      const hasBirthDate =
        birth !== null && birth.hasOwnProperty("date") && birth.date !== null;
      const content = fullName;
      const title = fullName;
      const haveEndDate = hasDeathDate || !hasDied;
      if (hasBirthDate) {
        return [
          {
            id,
            content,
            title,
            group: "Family",
            start: moment(birth.date).toDate(),
            ...(haveEndDate && {
              end: hasDeathDate
                ? moment(death.date).toDate()
                : moment().toDate(),
            }),
          },
        ];
      }
      return [];
    },
  );
  return {
    result: {
      type: "timeline",
      data,
    },
    options: {
      search,
      dateRange: dateRange,
    },
  };
};
