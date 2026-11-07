# syntax=docker/dockerfile:1
#
# tng-php — maintained Apache/mod_php image for The Next Generation of Genealogy Sitebuilding
#
# Replaces tangramor/nginx-php8-fpm (nginx + php-fpm, unpublished since June 2026) with the
# official php:8.5-apache image, which keeps receiving PHP security patches (PHP2Shell,
# CVE-2026-109618/9, fixed in 8.5.12+).
#
# Two stages: the build stage compiles the extensions against the -dev packages, the final
# stage keeps only the runtime libraries. No compilers, no headers, no package lists shipped.
#
# Deliberate omissions:
#   * ghostscript — the old image never had it, so Imagick had no PDF decode delegate and
#     PDF thumbnails never worked live (verified: queryFormats("PDF") == none,
#     "no decode delegate for this image format"). Shipping a large PDF parser would be new
#     attack surface, not parity. TNG's imageutils.php:77 PDF branch therefore throws the
#     same ImagickException it throws today.
#   * sendmail/MTA — no relay exists and TNG's usesmtp is "0"; see conf/tng-sendmail-disabled.

# ---------------------------------------------------------------------------
# Stage 1 — build extensions
# ---------------------------------------------------------------------------
FROM php:8.5-apache AS ext

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev \
        libmagickwand-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" gd mysqli exif zip; \
    pecl install imagick; \
    docker-php-ext-enable imagick; \
    rm -rf /var/lib/apt/lists/* /tmp/pear ~/.pearrc

# ---------------------------------------------------------------------------
# Stage 2 — runtime
# ---------------------------------------------------------------------------
FROM php:8.5-apache

LABEL org.opencontainers.image.title="tng-php" \
      org.opencontainers.image.description="Apache + mod_php 8.5 image for TNG (The Next Generation of Genealogy Sitebuilding)" \
      org.opencontainers.image.source="https://github.com/bitcryptic-gw/tng-php" \
      org.opencontainers.image.licenses="MIT"

# Only runtime libraries — no -dev packages, no compilers.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libfreetype6 \
        libjpeg62-turbo \
        libpng16-16t64 \
        libwebp7 \
        libzip5 \
        imagemagick-7-common \
        libmagickcore-7.q16-10-extra \
        libmagickwand-7.q16-10; \
    rm -rf /var/lib/apt/lists/*

# The official php image ships $PHPIZE_DEPS (gcc, g++, make, autoconf, re2c, pkg-config,
# dpkg-dev, linux-libc-dev) so that docker-php-ext-install works at build time. Nothing at
# runtime needs a compiler, and a C toolchain in a web container is free escalation surface,
# so drop it here. The extensions are already built .so files by this point.
RUN set -eux; \
    apt-get purge -y --auto-remove \
        gcc g++ make autoconf re2c pkg-config dpkg-dev linux-libc-dev libc-dev-bin; \
    rm -rf /var/lib/apt/lists/*

# Extensions compiled in stage 1 (same base image, same ABI) plus their ini files.
COPY --from=ext /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=ext \
     /usr/local/etc/php/conf.d/docker-php-ext-gd.ini \
     /usr/local/etc/php/conf.d/docker-php-ext-mysqli.ini \
     /usr/local/etc/php/conf.d/docker-php-ext-exif.ini \
     /usr/local/etc/php/conf.d/docker-php-ext-zip.ini \
     /usr/local/etc/php/conf.d/docker-php-ext-imagick.ini \
     /usr/local/etc/php/conf.d/

# ---------------------------------------------------------------------------
# Remap www-data to 101:101 (the uid/gid the live web root already uses)
# ---------------------------------------------------------------------------
RUN set -eux; \
    groupmod -o -g 101 www-data; \
    usermod -o -u 101 -g 101 www-data; \
    id www-data

# ---------------------------------------------------------------------------
# Configuration: PHP ini + Apache hardening (no secrets, nothing mounted)
# ---------------------------------------------------------------------------
COPY conf/php-tng.ini /usr/local/etc/php/conf.d/zz-tng.ini
COPY conf/apache-tng.conf /etc/apache2/conf-available/zz-tng.conf
COPY conf/tng-sendmail-disabled /usr/local/bin/tng-sendmail-disabled

RUN set -eux; \
    chmod 0755 /usr/local/bin/tng-sendmail-disabled; \
    a2enconf zz-tng; \
    a2dismod -f autoindex; \
    a2dismod status || true; \
    php -m | grep -qx mysqli; \
    php -m | grep -qx gd; \
    php -m | grep -qx imagick; \
    php -m | grep -qx exif; \
    php -m | grep -qx zip; \
    apache2ctl -t

# Logs to stdout/stderr are the stock behaviour of this image
# (CustomLog /proc/self/fd/1, ErrorLog /proc/self/fd/2).
WORKDIR /var/www/html
EXPOSE 80
