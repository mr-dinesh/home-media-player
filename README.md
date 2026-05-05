# RadioStack — Self-Hosted Personal Radio Server

**Four Docker containers, a web admin UI, and a surprisingly working home radio stream.**

Part of the [Vibe Coding series](https://mrdee.in/vibecoding/vibecoding-008-home-radio-server/)

---

## Stack

| Service | Role |
|---|---|
| Liquidsoap | Reads playlist, normalises audio, encodes MP3 128kbps, streams to Icecast |
| Icecast2 | Serves the stream to listeners |
| Node.js Express | Web admin UI — upload, manage playlist, skip tracks |
| Navidrome | Music library indexer (Subsonic-compatible API) |

## Run

```bash
cd radiostack
docker compose up -d
docker compose logs -f liquidsoap   # debug audio
```

## Endpoints

| Service | URL |
|---|---|
| Web admin UI | http://localhost:3000 |
| Listener player | http://localhost:3000/listen.html |
| Raw stream | http://localhost:8000/stream |
| Icecast admin | http://localhost:8000/admin |
| Navidrome | http://localhost:4533 |

## Notes

- Music files mount from `/home/tester/Music` on the host
- Paths in `.m3u` files must use the Docker container path (`/music/filename.mp3`)
- `icecast.xml` and `radio.liq` contain hardcoded passwords — change before any external deployment
