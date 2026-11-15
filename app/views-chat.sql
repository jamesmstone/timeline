-- The chat lane and the aggregates behind /chat, over the Synapse tables in the
-- chat snapshot. The snapshot's own `messages` view is not used: scanning it
-- sends DuckDB's rewrite of its LIKE ... ESCAPE to SQLite, which has no such
-- function, so the same shape is rebuilt here from the tables.
--
-- chat_events carries a network and a time and joins nothing, so the lane and
-- the aggregates never touch a body or a room. chat_messages adds the bodies,
-- and is read only by /chat/search and the SQL box.

CREATE OR REPLACE VIEW chat_events AS
  SELECT e.stream_ordering AS seq, e.event_id, e.room_id, e.origin_server_ts::BIGINT AS ts, e.sender,
         CASE
           WHEN e.sender LIKE '@whatsapp\_%'  ESCAPE '\' THEN 'whatsapp'
           WHEN e.sender LIKE '@signal\_%'    ESCAPE '\' THEN 'signal'
           WHEN e.sender LIKE '@telegram\_%'  ESCAPE '\' THEN 'telegram'
           WHEN e.sender LIKE '@gmessages\_%' ESCAPE '\' THEN 'sms'
           WHEN e.sender LIKE '@meta\_%'      ESCAPE '\' THEN 'messenger'
           WHEN e.sender LIKE '@slack\_%'     ESCAPE '\' THEN 'slack'
           ELSE 'local'
         END AS network
    FROM chat.events e
    WHERE e."type" = 'm.room.message' AND e.rejection_reason IS NULL AND coalesce(e.outlier::INTEGER, 0) = 0;

CREATE OR REPLACE VIEW chat_messages AS
  SELECT c.seq, c.event_id, c.room_id, c.ts, strftime(epoch_ms(c.ts), '%Y-%m-%d %H:%M:%S') AS sent_at,
         c.sender, p.displayname AS sender_name, c.network,
         json_extract_string(ej."json", '$.content.msgtype') AS msgtype,
         json_extract_string(ej."json", '$.content.body') AS body
    FROM chat_events c
    JOIN chat.event_json ej ON ej.event_id = c.event_id
    LEFT JOIN chat.profiles p ON p.full_user_id = c.sender;

CREATE OR REPLACE VIEW chat_points AS
  SELECT 'chat' AS lane, c.ts // 1000 AS t0, 1.0 AS value FROM chat_events c;

CREATE OR REPLACE VIEW chat_items AS
  SELECT 'chat' AS lane, c.ts // 1000 AS t0, c.ts // 1000 + 60 AS t1, 1.0 AS value, c.network || ' message' AS label
    FROM chat_events c;

CREATE OR REPLACE VIEW chat_daily AS
  SELECT strftime(epoch_ms(c.ts), '%Y-%m-%d') AS "day", c.network, count(*) AS messages
    FROM chat_events c GROUP BY ALL;
