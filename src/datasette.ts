import { fetcher } from "./fetcher";

const parseLinkHeader = (link: string): Record<string, string> => {
  const linkexp =
    /<[^>]*>\s*(\s*;\s*[^()<>@,;:"\/\[\]?={} \t]+=(([^()<>@,;:"\/\[\]?={} \t]+)|("[^"]*")))*(,|$)/g;
  const paramexp =
    /[^()<>@,;:"\/\[\]?={} \t]+=(([^()<>@,;:"\/\[\]?={} \t]+)|("[^"]*"))/g;

  const matches = link.match(linkexp);
  let rels = {};
  for (let i = 0; i < matches.length; i++) {
    const split = matches[i].split(">");
    const href = split[0].substring(1);
    const ps = split[1];
    const s = ps.match(paramexp);
    for (let j = 0; j < s.length; j++) {
      const p = s[j];
      const paramSplit = p.split("=");
      const rel = paramSplit[1].replace(/["']/g, "");
      rels[rel] = href;
    }
  }
  return rels;
};
export const datasetteFetch = async (url: string) => {
  let json = [];
  while (url !== undefined) {
    const res = await fetcher(url);
    const newJson = await res.json();
    json = [...json, ...newJson];
    const linkHeader = res.headers.get("link");
    if (linkHeader !== null) {
      const linkHeaders = parseLinkHeader(linkHeader);
      url = linkHeaders?.next;
    } else {
      url = undefined;
    }
  }
  return json;
};
