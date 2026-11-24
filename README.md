# timeline

Duckweb pages over the scraped SQLite databases, as two instances on hermanii.

## Private homepage

On the private instance `/` is a sideways strip of `/embed.svg` tiles, newest at the right,
with no script. Each tile is an `<img loading=lazy>`, so the browser fetches it as it nears the
viewport. Older time is a lazy `<iframe>` at the left: the same page, one `more` shorter, which
loads once you scroll to it and brings its own tiles and older frame. The innermost page ends in
an "Earlier" link that reopens the view further back. Zoom links set the time a tile spans.
Parameters: `end` (default now), `step` (`Nh`/`Nd`/`Nw`, default 1w), `count` tiles a page
(26), `more` older pages (8, at most 20), `w` and `h` a tile. The draggable lanes page is at
`/?view=lanes`.

## Embedding

`/embed.svg` on the private instance is the lane timeline as a self-contained
image, for other sites to embed with `<img>`: heart rate and stress samples,
sleep, steps, music, family and reading.

| Parameter  | Meaning                                                                  |
| ---------- | ------------------------------------------------------------------------ |
| `start`    | ISO 8601 time, or `now`.                                                 |
| `end`      | ISO 8601 time, or `now`.                                                 |
| `duration` | `24h`, `30d`, `1w`. Used when only one of `start` and `end` is given.    |
| `width`    | Pixels, 200 to 2400. Defaults to 1200.                                   |
| `maxWidth` | Caps `width`; `600px` and `600` both work.                               |
| `height`   | Pixels, 200 to 2400. Defaults to 520; stretches the lanes, not the text. |

`start` and `end` together win; with one, `duration` (default a week) fills in
the other; with neither, the week ending now. A range runs from an hour to five
years. Always the horizontal layout.

## Public instance

`services.timeline` (in `nixosModules.default`, x86_64-linux) runs duckweb, which
renders each response from SQL over the public-safe sources: Last.fm, the
reading list, parkrun, chess, and sanitised Garmin rollups. `/` is the lane
timeline: the server draws an SVG three viewports wide and the page script pans
it by moving the viewBox, fetching a fresh window from `/lanes.svg` near an edge.
Without script the page is the same drawing at a fixed range, navigable by the
zoom links. `/sql` is a page shell: the server runs none of the visitor's SQL.
The page boots duckweb's browser worker, which attaches the exports (below) by
range request and renders the same routes there, with example queries and charts.

`nixosModules.default` does not import duckweb's NixOS module; the instances set
`services.duckweb`, so the consuming configuration must import
`duckweb.nixosModules.duckweb` itself.

The attach set is the permission boundary. The process is handed only the
`services.timeline.sources` files and a Garmin file produced by
`timeline-garmin-public`, which keeps sleep nights and daily aggregates and
nothing with a coordinate or a sub-day sample. `enable_external_access` is
switched off before the first request (DuckDB cannot turn it back on), and the unit
is capped by `MemoryMax`, `CPUQuota` and DuckDB's `memory_limit`. DuckDB has no
statement timeout, so those caps are the limit on an expensive query.

## Private instance

`services.timeline-private` is the same lane timeline over every source, for the
tailnet: `address` must be one interface (a wildcard fails evaluation) and no
public name points at it. It attaches the public sources and the Garmin rollups,
and for the SQL box the full Garmin snapshots (`garmin_full`, `garmin_summary`,
`garmin_activities`, `garmin_monitoring`), the chat snapshot (`chat`, a copy of
Synapse's database), optionally the chat `archive`, and `purifier`. It runs as
its own unit with its own state, looser caps, and the supplementary groups its
files need.

Four more lanes join the public ones: chat volume, PM2.5, family and, drawn only by `/embed.svg`, raw heart rate and stress. `/chat` shows
message counts by network and never a body; bodies are reachable through
`/chat/search?q=` (a plain substring of at least three characters, the newest
50 matches) and the SQL box (`chat_messages`). The public instance has neither
route.

The purifier recorder opens its DuckDB file read-write every minute, and a
reader's lock makes that tick fail, so the server never holds it. It attaches
`purifier.snapshot`, a SQLite file, which `timeline-purifier-snapshot
<status.duckdb> <out.sqlite>` writes by copy-then-rename; evaluation fails if
that option names a `.duckdb` file. The units that run the snapshot, and the
Garmin and chat snapshots arriving, are the host's: the server waits up to a
minute for its files at start and retries every 30 seconds after that.

`nix flake check` boots both modules in one NixOS VM (`checks.<system>.site-vm`)
over fixture databases, and asserts the lanes draw, the Garmin file carries no
location, the SQL box refuses writes, file access, `ATTACH` and reconfiguration,
the private instance sees the private catalogs and the public one still does
not, and no body, archive row or coordinate reaches a lane or the chat page.
`bun test web` covers the pan arithmetic.

## Quack

`services.timeline-private.quack` serves DuckDB's Quack protocol from the
private instance's own DuckDB, on the tailnet address, with a token read from
`tokenFile` as a systemd credential. Quack has no read-only token: whoever holds
it can run SQL over every attached catalog, raw Garmin and chat bodies included.
The process is what keeps it read-only (sources attached `READ_ONLY`, file
access off), and the public instance has no Quack listener.

## Exports

`services.timeline-export` writes `<outDirectory>/v/<hash>/` with one `.duckdb` per
public source (`lastfm`, `reading`, `parkrun`, `chess`, `garmin`) and `app.duckdb`, the
page's macros built against them, then `version` naming the newest. Serve
`outDirectory` as `/data` with range requests. Each page reads `version` first, so
macros and tables always come from one export; three versions are kept. A source
that is not readable yet keeps its file from the previous export. It refuses raw
Garmin, chat, archive and purifier sources; Garmin goes out as the sanitised
rollups only.
