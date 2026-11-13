# SIGNAL — Home Radio Streaming Server

A self-hosted Icecast2 streaming server with a web-based playlist manager.
Runs entirely on Docker. No cloud costs. Works on any Linux laptop/PC.

```
Architecture:
  Music files (local) → Liquidsoap (encoder) → Icecast2 (stream server)
                                                      ↓
                                        Listeners (browser / VLC / any player)
                                        Admin UI  (playlist manager)
```

---

## Prerequisites

- Ubuntu/Debian Linux (20.04+)
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

## One-time Setup

### 1. Clone / copy this directory to your server

```bash
mkdir ~/radiostack
# copy all files here
cd ~/radiostack
```

### 2. Set passwords (important!)

Credentials live in `.env`, which is gitignored. No password is stored in any
config file.

```bash
cp .env.example .env
openssl rand -base64 24        # generate a value for each password
${EDITOR:-nano} .env           # fill in all four variables
```

Then render the Icecast config from its template:

```bash
./scripts/gen-icecast-config.sh
```

This writes `icecast/icecast.xml` (mode 600) from `icecast/icecast.xml.template`.
Re-run it any time you change `.env`.

Liquidsoap reads `ICECAST_SOURCE_PASSWORD` straight from its container
environment — Compose passes it through from `.env` and refuses to start if it
is unset.

Avoid `&`, `<`, and `>` in these values; they go into XML text nodes unescaped,
and the generator will reject them.

### 3. Start the stack

```bash
docker compose up -d
```

That's it. Three containers start:
- **icecast** on port 8000  — the actual stream server
- **liquidsoap**            — reads playlists, encodes, sends to Icecast
- **radio-web** on port 3000 — playlist manager UI

---

## Using the Web UI

Open `http://localhost:3000` in your browser.

**Admin console (playlist manager):**
- Upload music via the library panel (right side)
- Create playlists, add tracks from the library
- Click **Broadcast** to make a playlist go live
- Liquidsoap detects the change within ~10 seconds

**Listener player:**
- `http://localhost:3000/listen.html`
- Share this with anyone on your network

**Raw stream URL (for VLC, apps, etc.):**
- `http://YOUR_IP:8000/stream`

**Icecast admin UI:**
- `http://localhost:8000/admin`
- Login: admin / your admin password

---

## Listening from outside your home (Tailscale)

No port forwarding or dynamic DNS: the box and the phone are on the same
Tailscale network, so the stream is reachable at the box's Tailscale IP
from anywhere, and nowhere else.

1. Install Tailscale on the server and the phone, signed in to the same account.
2. `radio up` prints the address, e.g. `http://100.x.y.z:8000/stream`.
3. On the phone, VLC → Open network stream → that URL (works on mobile data).

Port 4533 is Navidrome (for Subsonic apps like Symfonium/Tempo), not a VLC stream.

---

## Adding Music

**Via web UI:** Upload directly from the Library panel.

**Via command line (bulk add):**
```bash
# Copy music into the music folder
cp ~/Music/*.mp3 ~/radiostack/music/

# Restart liquidsoap to rescan
docker compose restart liquidsoap
```

**Supported formats:** MP3, AAC, OGG, FLAC, M4A

---

## Useful Commands

```bash
# Start everything
docker compose up -d

# Stop everything
docker compose down

# View logs
docker compose logs -f liquidsoap
docker compose logs -f icecast

# Restart just Liquidsoap (e.g. after adding music manually)
docker compose restart liquidsoap

# Check what's running
docker compose ps
```

---

## Directory Structure

```
radiostack/
├── docker-compose.yml       ← the whole stack
├── icecast/
│   └── icecast.xml          ← Icecast2 config (passwords here)
├── liquidsoap/
│   └── radio.liq            ← playlist engine config
├── web/
│   ├── server.js            ← Node.js API + web server
│   ├── package.json
│   └── public/
│       ├── index.html       ← admin playlist manager
│       └── listen.html      ← public listener player
├── music/                   ← your audio files live here
├── playlists/               ← .m3u playlist files live here
└── scripts/
    ├── radio.sh             ← `radio` command (up/down/status/skip/play)
    └── gen-icecast-config.sh ← renders icecast.xml from .env
```

---

## Troubleshooting

**Liquidsoap won't connect to Icecast:**
- Make sure the password in `radio.liq` matches `icecast.xml`
- Check logs: `docker compose logs liquidsoap`

**Stream is silent / no source:**
- Check that `playlists/default.m3u` has valid file paths
- File paths inside .m3u must be `/music/filename.mp3` (Docker mount path)
- Check: `docker compose logs liquidsoap`

**Can't reach from outside:**
- Verify port forwarding on router
- Test with: `curl http://YOUR_PUBLIC_IP:8000/` from a different network
- Check if ACT is blocking: try from mobile data

**Web UI uploads fail:**
- Check disk space: `df -h`
- Check music dir permissions: `ls -la music/`
