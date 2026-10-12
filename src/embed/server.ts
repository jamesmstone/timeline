import { parseArgs } from "util";
import { createEmbedHandler } from "./handler";
import { cached, loadLanes } from "./load";

const { values } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    host: { type: "string", default: "127.0.0.1" },
    port: { type: "string", default: "8790" },
  },
  strict: true,
});

const handler = createEmbedHandler({ load: cached(loadLanes) });

const server = Bun.serve({
  hostname: values.host,
  port: Number(values.port),
  fetch: async (request) => {
    try {
      return await handler(request);
    } catch (e) {
      console.error("embed: render failed:", e);
      return new Response("Internal server error\n", {
        status: 500,
        headers: { "Cache-Control": "no-store" },
      });
    }
  },
});

console.log(`timeline embed listening on ${server.url}`);
