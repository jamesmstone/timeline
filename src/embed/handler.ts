import { parseEmbedParams } from "./params";
import { LaneData, renderEmbed } from "./render";
import { el, escapeXml, text } from "./svg";

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

// An <img> shows a 400's body when it is an image, so the reason lands where
// the embedder is looking instead of as a broken-image icon.
const errorImage = (message: string): string =>
  el(
    "svg",
    {
      xmlns: "http://www.w3.org/2000/svg",
      width: 480,
      height: 60,
      viewBox: "0 0 480 60",
      role: "img",
      "aria-labelledby": "title",
    },
    el("title", { id: "title" }, escapeXml(`Timeline: ${message}`)),
    el("rect", {
      x: 0.5,
      y: 0.5,
      width: 479,
      height: 59,
      rx: 10,
      fill: "#fff",
      stroke: "#d3dae5",
    }),
    text(
      {
        x: 16,
        y: 26,
        "font-size": 13,
        "font-weight": 700,
        fill: "#0f172a",
        "font-family": "sans-serif",
      },
      "Timeline embed",
    ),
    text(
      {
        x: 16,
        y: 44,
        "font-size": 11,
        fill: "#5b6b7c",
        "font-family": "sans-serif",
      },
      message,
    ),
  );

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
        request.method === "HEAD" ? null : errorImage(parsed.error),
        { status: 400, headers: imageHeaders },
      );
    const { start, end } = parsed.params;
    const svg = renderEmbed(await load({ start, end }), parsed.params, current);
    return new Response(request.method === "HEAD" ? null : svg, {
      headers: imageHeaders,
    });
  };
