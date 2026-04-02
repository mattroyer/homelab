# Homelab Starter

This repo is a Docker Compose based homelab starter that bundles the layout, service definitions, and app-side configuration I use to run a single-host lab behind Traefik.

You can clone it, generate local config, and bring up the stack without needing Cloudflare, Pangolin, or a pre-existing `/mnt/storage/media` layout.

## What is here

- `docker-compose.yml` is the root entrypoint.
- `compose/` contains one file per service or service group.
- `apps/` holds mounted config and app-side files for services that need them.
- `scripts/bootstrap.sh` creates `.env`, renders service config files, and prepares local directories.
- `scripts/render-configs.sh` regenerates Traefik, Glance, and Pi-hole config from `.env`.
- `scripts/doctor.sh` checks local prerequisites and the current `.env` choices.

## Quick start

1. Run `./scripts/bootstrap.sh` (or `make bootstrap`)
2. Run `./scripts/doctor.sh` (or `make doctor`).
3. Start the starter stack with `docker compose up -d` (or `make up`).
4. Open `https://glance.<your DOMAIN_NAME>`.

For example, if bootstrap chose `DOMAIN_NAME=192-168-1-10.sslip.io`, open `https://glance.192-168-1-10.sslip.io`.
If you change `DOMAIN_NAME`, `./scripts/render-configs.sh` will update the generated hostnames and local config, but it will not publish DNS for you.
An arbitrary name like `awesomeness.sslip.io` will not resolve via public `sslip.io` unless that name already maps to your server IP.
If you later enable Pi-hole from this repo and point your clients at it for DNS, the generated Pi-hole rule can make `${DOMAIN_NAME}` and its subdomains resolve locally to `HOMELAB_HOST_IP`.

Bootstrap writes the default `DOMAIN_NAME` into `.env`.
By default it uses `<your-host-ip>.sslip.io`, so a machine on your LAN can usually resolve the starter URLs without local DNS setup.

## What starts by default

The root compose file starts the main stack, including the media apps:

- Glance
- Traefik
- Dozzle
- File Browser
- Jellyfin
- Jellyseerr
- Jellystat
- Prowlarr
- Radarr
- Sonarr
- Bazarr
- SABnzbd
- Audiobookshelf
- ReadMeABook
- Immich
- Vaultwarden
- RSSHub
- n8n
- NocoDB
- Miniflux
- Grocy
- Homebox
- IT-Tools

`cloudflare-ddns`, `newt`, and other more environment-specific services are still in `compose/`, but they are not part of the default first boot.

## What belongs in git

The repo is intended to be safe to fork and publish without committing machine-specific service state.

- Use `./scripts/bootstrap.sh` to create missing local directories.
- Use `./scripts/render-configs.sh` to regenerate files that depend on `.env`.
- Ignore known runtime, secret, and generated paths under `apps/`, while leaving the rest of `apps/` available for tracked service config or app code.

That split keeps the repo portable without making `apps/` unusable for people who want to track their own files there.
Git will not automatically remove local files from `apps/` for you before a commit, and `.gitignore` will not protect files you explicitly add or already track.
Review `git status` before publishing your own fork or branch.

## Storage layout

By default, the media stack uses `MEDIA_ROOT=./data/media`.

That means a fresh clone gets a runnable local directory tree like this:

- `./data/media/movies`
- `./data/media/tvseries`
- `./data/media/downloads/complete`
- `./data/media/downloads/incomplete`
- `./data/media/audiobooks`
- `./data/media/podcasts`
- `./data/media/books`
- `./data/media/magazines`
- `./data/media/youtube`

If you already have storage elsewhere, change `MEDIA_ROOT` in `.env`. Example:

```dotenv
MEDIA_ROOT=/mnt/storage/media
```

That single variable is the main setting for adapting the repo to a real NAS or mounted disk.

## Changing settings

Most changes are in `.env`.

After changing values in `.env`, run:

```bash
./scripts/render-configs.sh
./scripts/doctor.sh
```

## First run behavior

The stack should come up without you having to redesign the file layout first.

- Jellyfin, Radarr, Sonarr, Bazarr, SABnzbd, Audiobookshelf, ReadMeABook, and File Browser will all mount the repo-default media tree.
- If those directories are empty, the apps will still run. They will be empty until you add files or hook up indexers and downloader credentials.
- Jellyseerr, Prowlarr, Radarr, and Sonarr still need to be linked together inside their UIs.
- ReadMeABook fills the same role for audiobooks that Jellyseerr fills for movies and TV.
- Cloudflare is optional. Local HTTPS works in `selfsigned` mode, and `cloudflare` mode is there when you want real public certs.

## TLS modes

- `TRAEFIK_TLS_MODE=selfsigned` is the default. If `openssl` is installed, bootstrap generates a local wildcard cert for your chosen domain. If not, Traefik falls back to its built-in default cert.
- `TRAEFIK_TLS_MODE=cloudflare` is for a real public domain and Cloudflare DNS challenge.
- `TRAEFIK_TLS_MODE=provided` uses `LOCAL_CERT_FILE` and `LOCAL_CERT_KEY_FILE`, which must point to certificate files that already exist on disk.

If you stay on `selfsigned`, browser certificate warnings are normal.

## Local domain setup

If you want local URLs like `https://jellyfin.your-domain.com`, you need two things:

- a wildcard certificate for your domain
- local DNS that resolves your homelab subdomains to your server

The setup I use is:

- Traefik for routing
- Cloudflare DNS-01 for wildcard certificates
- Pi-hole as local DNS for the network
- a second Pi-hole on a Raspberry Pi as backup DNS in case the main server is down

That setup gives local services HTTPS on names like `jellyfin.your-domain.com` instead of raw IP addresses or self-signed hostnames.

This repo does not require that setup. The default path uses `sslip.io` and local cert options so you can get the stack running first.
`sslip.io` helps the hostname resolve back to your server IP, but it does not give you a trusted public certificate by itself.
If you want a custom local domain later, point your router's DNS at Pi-hole or another local DNS server and update the relevant values in `.env`.

## Adapting the stack

Once the base stack is healthy, add optional services one at a time. For example:

```bash
docker compose -f docker-compose.yml -f compose/home-assistant.yml up -d
docker compose -f docker-compose.yml -f compose/jellyfin.yml -f compose/sonarr.yml up -d
```

That is the better pattern for services that need extra host setup or external accounts.

## First things to customize

- Change `MEDIA_ROOT` if your files live somewhere other than `./data/media`.
- If you want real certs, set `TRAEFIK_TLS_MODE=cloudflare`, provide `CF_DNS_API_TOKEN`, and use a real `DOMAIN_NAME`.
- If you want local-only usage, leave `TRAEFIK_TLS_MODE=selfsigned`.
- Add your Usenet server inside SABnzbd.
- Add your indexers in Prowlarr.
- Connect Prowlarr to Radarr and Sonarr.
- Connect Jellyseerr to Jellyfin and then to Radarr and Sonarr.
- Open ReadMeABook if you want an audiobook request and download flow.
- Point Jellyfin libraries at `/movies`, `/tv`, `/audiobooks`, or whatever subset you actually want.

## Media setup

Use this order after the containers are running:

1. Open SABnzbd and add your Usenet server.
2. Open Prowlarr and add your indexers.
3. In Prowlarr, connect Radarr and Sonarr under `Settings` -> `Apps`.
4. In Radarr, set the root folder to `/movies`.
5. In Sonarr, set the root folder to `/tv`.
6. In Jellyfin, add libraries for `/movies`, `/tv`, `/audiobooks`, or the folders you want to use.
7. In Jellyseerr, connect Jellyfin, then connect Radarr and Sonarr.
8. In ReadMeABook, configure the downloader and audiobook library paths if you want a separate audiobook workflow.

## Notes

- This repo expects Docker Compose v2.
- Pi-hole is optional, is not started by default, and its generated DNS config points your homelab domain back to the machine running this stack if you decide to enable it.
- Tailscale is not required for this repo, but it is a useful rabbit hole if you want private remote access to your homelab without exposing services directly to the public internet.
- Pangolin is also not part of this repo. In my own setup, Pangolin runs separately on a DigitalOcean Droplet and acts as part of the public access layer, but you do not need it to use this starter.
- Several optional services still expect external credentials or extra host setup. The generated `.env` file marks the obvious ones.

## Common commands

- `make bootstrap`
- `make doctor`
- `make render`
- `make validate`
- `make up`
- `make down`
- `make backup`
