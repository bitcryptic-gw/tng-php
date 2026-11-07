# syntax=docker/dockerfile:1
#
# tng-php — maintained Apache/mod_php image for The Next Generation of Genealogy Sitebuilding
#
# Replaces tangramor/nginx-php8-fpm (nginx + php-fpm, unpublished since June 2026) with the
# official php:8.5-apache image, which keeps receiving PHP security patches (PHP2Shell,
# CVE-2026-109618/9, fixed in 8.5.12+).
#
# Design notes:
#   * mod_php: one process instead of nginx + php-fpm + supervisor.
#   * www-data is remapped to 101:101 so existing file ownership on the live web root
#     (config.php 101:101 640, media dirs) keeps working with no chown at cutover.
#   * Only the extensions TNG provably uses are installed (see README / inventory).

FROM php:8.5-apache

LABEL org.opencontainers.image.title="tng-php" \
      org.opencontainers.image.description="Apache + mod_php 8.5 image for TNG (The Next Generation of Genealogy Sitebuilding)" \
      org.opencontainers.image.source="https://github.com/bitcryptic-gw/tng-php" \
      org.opencontainers.image.licenses="MIT"

# ---------------------------------------------------------------------------
# PHP extensions
#   mysqli  - TNG's DB driver
#   gd      - thumbnails, small-image AJAX, map markers (freetype + jpeg)
#   exif    - photo orientation on upload/import
#   zip     - GEDCOM export/import bundles, template importer
#   imagick - unguarded PDF-thumbnail branch in imageutils.php (needs ghostscript)
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev \
        libmagickwand-dev \
        ghostscript; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" gd mysqli exif zip; \
    pecl install imagick; \
    docker-php-ext-enable imagick; \
    rm -rf /var/lib/apt/lists/* /tmp/pear ~/.pearrc

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
    apache2ctl -t

# Logs to stdout/stderr are the stock behaviour of this image
# (CustomLog /proc/self/fd/1, ErrorLog /proc/self/fd/2).
WORKDIR /var/www/html
EXPOSE 80
