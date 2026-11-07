# tng-php

Apache + mod_php **PHP 8.5** image for [TNG — The Next Generation of Genealogy Sitebuilding](https://tngsitebuilding.com),
running Bruce's site at `bb.bitcryptic.com` (container `nginx-PHP8-Genealogy`, host `unraid-wildwood`).

It replaces `tangramor/nginx-php8-fpm`, which stopped publishing after June 2026 and therefore never
received the **PHP2Shell** fix (CVE-2026-109618 / CVE-2026-109619, unauthenticated RCE, fixed in
**8.5.12**).

## Why this shape

* **`php:8.5-apache`** — official, maintained, gets every PHP patch automatically when the base tag moves.
* **mod_php instead of nginx + php-fpm** — one process, no sidecar, listens on 80 like the old image.
  TNG has no nginx-specific rules (every feature is a direct `*.php` URL), so nothing is lost.
* **`www-data` remapped to `101:101`** — the live web root already uses uid/gid 101, so cutover needs
  **no chown**, and rollback is just swapping the image tag back.
* **Config baked in** — no secrets in this image, nothing to mount: PHP ini values match the old
  container, plus `expose_php=Off` and Apache hardening (no version banners, `Options -Indexes`,
  dot-paths denied at any depth).

Only the extensions TNG actually uses are installed: `gd`, `mysqli`, `exif`, `zip`, `imagick`
(plus everything already in the official image: `curl`, `mbstring`, `openssl`, `iconv`, `opcache`, …).

## Tags

| Tag | Meaning |
|---|---|
| `8.5` | floating — always the newest build of this repo on PHP 8.5 |
| `YYYY.MM.DD` | dated build; same-day rebuilds get `-1`, `-2`, … and never overwrite |
| `<sha>` | optional, for pinning |

**amd64 only** by design (no arm64 target).

## How patches flow

`.github/workflows/build.yml` rebuilds with `--pull` on:

* every push to `main`,
* every Monday 03:17 UTC (scheduled),
* manually via **Actions → Build and push tng-php → Run workflow**.

Because the build always pulls `php:8.5-apache` first, each run picks up the newest 8.5 patch. Once a
new `8.5` image is pushed, the Unraid fleet **Update All** picks it up the same way it does for the
WordPress containers — no source changes needed.

## Required GitHub secrets

The workflow pushes with a Docker Hub token. **Create it yourself; it is never committed here.**

1. Docker Hub → **Account settings → Security → New Access Token**
   * Description: `tng-php GH Actions`
   * Permissions: **Read & Write** (scoped to `bitcryptic/tng-php` if the UI offers per-repo scoping)
2. GitHub → `bitcryptic-gw/tng-php` → **Settings → Secrets and variables → Actions → New repository secret**
   * `DOCKERHUB_USERNAME` = your Docker Hub username
   * `DOCKERHUB_TOKEN` = the token from step 1
3. Re-run the workflow once (**Actions → Run workflow**) to confirm the push succeeds.
   Revoke the token if it is ever pasted anywhere else.

Until the secrets exist, build and push manually (below).

## Manual build (arm64 Mac → amd64 image)

Always use `buildx` with an explicit platform — a plain `docker build` on Apple Silicon produces an
arm64 image that will not run on the host.

```sh
docker buildx build \
  --platform linux/amd64 \
  --pull --push \
  --tag bitcryptic/tng-php:8.5 \
  --tag bitcryptic/tng-php:$(date -u +%Y.%m.%d) \
  .
```

## Deploy / rollback

* Deploy: Unraid → Docker → `nginx-PHP8-Genealogy` → Edit → **Repository** = `bitcryptic/tng-php:8.5` → Apply.
  Nothing else changes (paths, port 80, Tailscale fields, State Directory all stay).
* Rollback: set **Repository** back to `tangramor/nginx-php8-fpm:<old tag>` → Apply. File ownership is
  unchanged because of the 101 remap, so there is nothing else to undo.

## Notes

* **Real client IP:** `mod_remoteip` trusts `X-Forwarded-For` from **caddy-linode only**
  (`100.76.221.87`), and the access log uses `%a`, so Apache and TNG see the visitor rather than
  the proxy. Without it every request logged as the proxy's address.

* **PDF thumbnails:** ghostscript is deliberately **not** installed. The old image never had it, so
  Imagick had no PDF decode delegate and PDF thumbnails never worked in production. TNG's
  `image_createThumb()` (`imageutils.php:77`) calls `new Imagick()` unguarded on the PDF branch, so a
  PDF upload throws an `ImagickException` — the same failure the live site produces today. Shipping a
  large PDF parser would add attack surface, not parity. If PDF thumbnails are ever wanted, install
  `ghostscript` in the final stage and re-test that path.
* **No build toolchain at runtime.** Extensions are compiled in a build stage against `-dev` packages;
  the final image installs runtime libraries only, and the base image's `PHPIZE_DEPS` (gcc, make,
  autoconf, …) are purged. Image size 843 MiB → 553 MiB.
* **Mail:** TNG's `usesmtp` is `0` and no MTA/relay is configured, so mail already failed on the old
  image. `sendmail_path` points at a stub that drains the message and exits 1, keeping `mail()`
  returning `false` without a PHP warning. To enable mail, configure SMTP in TNG admin (`usesmtp=1`).
* **Front controller:** the old nginx config fell back to `index.php` for unknown paths (which made
  missing files answer 200 with the homepage). Apache returns a real 404 — intentional.
