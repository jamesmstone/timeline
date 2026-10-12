import { parseEmbedParams } from "./params";
import { LaneData, renderEmbed } from "./render";

export type LoadLanes = (range: {
  start: Date;
  end: Date;
}) => Promise<LaneData[]>;

const minute = 60 * 1000;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
};

const imageHeaders = {
  ...cors,
  "Content-Type": "image/svg+xml; charset=utf-8",
  // end=now moves every minute, so shared caches may only hold a few.
  "Cache-Control": "public, max-age=60, s-maxage=300",
  "X-Content-Type-Options": "nosniff",
  // Opened directly rather than through <img>, an SVG is a document that
  // could run script; this one never needs to.
  "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'",
  "Cross-Origin-Resource-Policy": "cross-origin",
};

export const createEmbedHandler =
  ({ load, now = () => new Date() }: { load: LoadLanes; now?: () => Date }) =>
  async (request: Request): Promise<Response> => {
    const url = new URL(request.url);
    if (url.pathname !== "/embed.svg")
      return new Response("Not found\n", { status: 404, headers: cors });
    if (request.method === "OPTIONS")
      return new Response(null, { status: 204, headers: cors });
    if (request.method !== "GET" && request.method !== "HEAD")
      return new Response("Method not allowed\n", {
        status: 405,
        headers: { ...cors, Allow: "GET, HEAD, OPTIONS" },
      });

    // Rounding "now" to the minute lets every request in that minute share one
    // load of the data sources, and one cache key downstream.
    const current = new Date(Math.floor(now().getTime() / minute) * minute);
    const parsed = parseEmbedParams(url.searchParams, current);
    if (!parsed.ok)
      return new Response(
        request.method === "HEAD" ? null : `${parsed.error}\n`,
        {
          status: 400,
          headers: { ...cors, "Content-Type": "text/plain; charset=utf-8" },
        },
      );
    const { start, end } = parsed.params;
    const svg = renderEmbed(await load({ start, end }), parsed.params, current);
    return new Response(request.method === "HEAD" ? null : svg, {
      headers: imageHeaders,
    });
  };
