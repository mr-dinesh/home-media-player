#!/usr/bin/liquidsoap

log.file := false
log.stdout := true
log.level := 3

settings.server.telnet := true
settings.server.telnet.bind_addr := "0.0.0.0"
settings.server.telnet.port := 1234

# Source password comes from the environment (see .env), never from this file.
source_password = environment.get("ICECAST_SOURCE_PASSWORD")

if source_password == "" then
  log("FATAL: ICECAST_SOURCE_PASSWORD is not set in the container environment.")
  shutdown()
end

radio = playlist(
  id="main_playlist",
  reload=10,
  reload_mode="watch",
  mode="randomize",
  "/playlists/default.m3u"
)

radio = mksafe(radio)

radio = source.on_metadata(radio, fun(m) ->
  begin
    log("Now playing: " ^ m["artist"] ^ " - " ^ m["title"])
  end
)

radio = normalize(radio)

output.icecast(
  %mp3(bitrate=128),
  id="icecast_out",
  host="icecast",
  port=8000,
  password=source_password,
  mount="/stream",
  name="My Home Radio",
  description="Personal playlist stream",
  genre="Mixed",
  url="http://localhost:3000",
  radio
)
