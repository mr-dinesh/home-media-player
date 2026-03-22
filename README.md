# SIGNAL — Home Radio & Media Server

A self-hosted music streaming stack for your home server or Linux laptop.
Two services in one: a live radio broadcaster (Icecast) and an on-demand
media player (Navidrome). Runs entirely on Docker.

```
Your Music Files
      │
      ├─► Navidrome (:4533)     — on-demand player, click any track
      │
      └─► Liquidsoap
                │
                └─► Icecast (:8000)  — live radio stream
                          │
                          └─► Admin UI (:3000) + Listener page
```

---

## Prerequisites

- Ubuntu / Debian Linux (20.04+)
- Docker + Docker Compose

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose plugin
sudo apt install docker-compose-plugin -y
```

---

## Quick Start

### 1. Put your music in the music folder

```bash
cp ~/Music/*.mp3 ./music/
# or symlink your existing folder — see "Custom music path" below
```

### 2. Generate a playlist

```bash
bash scripts/gen-playlist.sh
```

### 3. Start everything

```bash
docker compose up -d
```

### 4. Open the interfaces

| URL | What it is |
|---|---|
| `http://localhost:4533` | Navidrome — on-demand player |
| `http://localhost:3000` | Radio admin console |
| `http://localhost:3000/listen.html` | Radio listener page |
| `http://localhost:8000/stream` | Raw stream URL (VLC, apps) |

Navidrome will scan your music on first launch. Create an admin account
when prompted — it only asks once.

---

## Custom Music Path

If your music is already somewhere else (e.g. `/home/tester/Music`),
edit `docker-compose.yml` and replace `./music:/music` with the
absolute path to your folder in the `liquidsoap`, `web`, and
`navidrome` services:

```yaml
volumes:
  - /home/tester/Music:/music:ro
```

Then regenerate the playlist pointing to that path:

```bash
find /home/tester/Music -name "*.mp3" | sort | \
  sed 's|/home/tester/Music|/music|g' > playlists/default.m3u
```

---

## Using the Radio Admin UI (:3000)

1. **Create a playlist** — click `+ New` in the sidebar
2. **Add tracks** — click any track in the Library panel (right side)
3. **Save** — click Save
4. **Go live** — click Broadcast
5. **Skip track** — click the ⏭ Skip button in the top bar
6. **Share stream** — click the URL pill to copy `http://YOUR_IP:8000/stream`

---

## Using Navidrome (:4533)

- Click any track to play it instantly
- Create playlists, shuffle, repeat
- Works with mobile apps via Subsonic API:
  - Android: **Symfonium**, **Ultrasonic**, **DSub**
  - iOS: **Substreamer**, **play:Sub**
- Add album art: see "Album Art" section below

---

## Album Art

**Option 1 — Auto-fetch from iTunes (bulk)**

```bash
# Install eyeD3
pip3 install eyeD3 --break-system-packages
export PATH="$HOME/.local/bin:$PATH"

# Run the fetcher
python3 scripts/fetch-art.py ./music
```

Then rescan in Navidrome: Settings → Scanning → Scan Now

**Option 2 — Drop cover.jpg in music folder**

Navidrome reads `cover.jpg`, `folder.jpg`, or `album.jpg` from the
same directory as the music files.

---

## Accessing from Outside Your Home

### Via Tailscale (recommended — no port forwarding needed)

```bash
# Install on your server
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Get your Tailscale IP
tailscale ip -4
```

Install Tailscale on your phone/laptop and sign in with the same account.
Access everything at `http://TAILSCALE_IP:PORT`.

Enable MagicDNS in the Tailscale admin console for clean URLs like
`http://lab:4533` (where "lab" is your machine hostname).

### Via DuckDNS (dynamic DNS for ACT / home ISP)

```bash
# Fill in your subdomain and token
nano scripts/duckdns.sh
chmod +x scripts/duckdns.sh

# Run every 5 minutes
crontab -e
# Add: */5 * * * * /home/tester/Desktop/.../scripts/duckdns.sh
```

Also forward ports 3000, 4533, 8000 on your router to your server's
local IP. ACT Fibernet generally doesn't block inbound ports.

---

## Common Commands

```bash
# Start all services
docker compose up -d

# Start only Navidrome (media player)
docker compose up -d navidrome

# Stop everything
docker compose down

# Restart just the radio stack
docker compose restart liquidsoap web

# View logs
docker compose logs -f liquidsoap
docker compose logs -f navidrome

# Check status
docker compose ps

# Skip current track (via telnet)
python3 -c "
import socket, time
s = socket.socket()
s.connect(('localhost', 1234))
time.sleep(0.5)
s.send(b'main_playlist.skip\n')
time.sleep(1)
print(s.recv(1024).decode())
s.close()
"
```

---

## Troubleshooting

**No audio / silent stream**
- Check playlist paths: must be `/music/filename.mp3` not `/home/user/Music/...`
- Regenerate: `bash scripts/gen-playlist.sh`
- Check logs: `docker compose logs liquidsoap`

**Liquidsoap won't connect to Icecast (401)**
- Password mismatch — `liquidsoap/radio.liq` password must match `icecast/icecast.xml` source-password
- Both default to `radio123`

**Navidrome shows no music**
- Check volume mount in docker-compose.yml points to correct music path
- Trigger manual scan: Settings → Scanning → Scan Now

**Skip button not working**
- Check telnet port: `docker compose ps` should show port 1234 mapped
- Test: `python3 -c "import socket; s=socket.socket(); s.connect(('localhost',1234)); print('OK')"`

**Can't reach from outside**
- Test from mobile data: `curl http://YOUR_PUBLIC_IP:8000/`
- If blocked by ISP: use Tailscale tunnel instead

---

## Directory Structure

```
signal-radio/
├── docker-compose.yml          ← entire stack definition
├── icecast/
│   └── icecast.xml             ← Icecast config (passwords)
├── liquidsoap/
│   └── radio.liq               ← playlist engine
├── web/
│   ├── server.js               ← Node.js API server
│   ├── package.json
│   └── public/
│       ├── index.html          ← admin console
│       └── listen.html         ← listener player
├── music/                      ← put your MP3s here
├── playlists/                  ← .m3u playlist files
├── navidrome/
│   └── data/                   ← Navidrome database (auto-created)
└── scripts/
    ├── gen-playlist.sh         ← auto-generate playlist from music folder
    ├── fetch-art.py            ← auto-fetch and embed cover art
    └── duckdns.sh              ← dynamic DNS updater
```

---

## Passwords

Default passwords (change before exposing to internet):

| Setting | File | Default |
|---|---|---|
| Icecast source password | `icecast/icecast.xml` | `radio123` |
| Icecast admin password | `icecast/icecast.xml` | `admin123` |
| Liquidsoap → Icecast | `liquidsoap/radio.liq` | `radio123` |
| Navidrome admin | Set on first login | your choice |

After changing passwords, restart: `docker compose down && docker compose up -d`
 Media Server
