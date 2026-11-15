-- A slice of Synapse's schema as the chat snapshot carries it. The bodies are
-- canaries: only /chat/search and the SQL box of the private instance may
-- ever show them.
CREATE TABLE events(stream_ordering INTEGER, event_id TEXT, room_id TEXT, origin_server_ts INTEGER,
  sender TEXT, type TEXT, rejection_reason TEXT, outlier INTEGER);
CREATE TABLE event_json(event_id TEXT, json TEXT);
CREATE TABLE profiles(full_user_id TEXT, displayname TEXT);

-- 2026-01-10 09:00:00, 09:05:00 and 2026-01-12 18:00:00 UTC, in milliseconds.
INSERT INTO events VALUES
  (1, 'e1', '!r1:x', 1768035600000, '@whatsapp_1:x', 'm.room.message', NULL, 0),
  (2, 'e2', '!r1:x', 1768035900000, '@james:x',      'm.room.message', NULL, 0),
  (3, 'e3', '!r2:x', 1768240800000, '@signal_2:x',   'm.room.message', NULL, 0),
  (4, 'e4', '!r2:x', 1768240900000, '@signal_2:x',   'm.room.member',  NULL, 0);
INSERT INTO event_json VALUES
  ('e1', '{"content":{"msgtype":"m.text","body":"CHAT-BODY-CANARY hello needle"}}'),
  ('e2', '{"content":{"msgtype":"m.text","body":"CHAT-BODY-CANARY <b>reply</b>"}}'),
  ('e3', '{"content":{"msgtype":"m.text","body":"unrelated"}}'),
  ('e4', '{"content":{"membership":"join"}}');
INSERT INTO profiles VALUES ('@whatsapp_1:x', 'Alice'), ('@signal_2:x', 'Bob');
