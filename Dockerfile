# syntax=docker/dockerfile:1.7
#
# Multi-stage build for the September 11 Digital Archive static site.
# Stage 1 builds the Hugo site + the Pagefind search index; stage 2 serves it
# with Caddy. Media (/files/*) is NOT served here — the fronting web server
# redirects /files/* to object storage (URLs are emitted root-relative).

FROM stagex/pallet-nodejs AS build-stage

# stagex/user-hugo-extended ships the binary inside a directory at
# /usr/bin/hugo/, named "hugo_exended" (sic — the missing 'x' is upstream's).
# Copy the actual file so /usr/local/bin/hugo is an executable, not a dir.
COPY --from=stagex/user-hugo-extended /usr/bin/hugo/hugo_exended /usr/local/bin/hugo

# Hugo build flags come from CI, not from here. The reusable workflow
# (chnm/.github hugo--build-release-deploy.yml) sets hugobuildargs per branch
# via --build-arg — prod gets `--environment production --minify --baseURL <prod-url>`,
# devl gets the development/draft flags. No default, so CI stays the single source
# of truth (a baked-in default would silently mask a missing build-arg).
ARG hugobuildargs
ENV HUGO_BUILD_ARGS=$hugobuildargs

WORKDIR /app
COPY . .

RUN npm ci
RUN hugo ${HUGO_BUILD_ARGS}
# Build the Pagefind search index. Restrict the walk to real item pages
# (items/<id>/index.html — the single-segment glob skips browse/collection/tag
# pages and keeps the 70k-item index build within memory). The item template
# marks only its content region with data-pagefind-body.
RUN npx --no-install pagefind --site public --glob "items/*/index.html"

FROM stagex/user-caddy

COPY --from=stagex/core-musl / /
COPY --from=build-stage /app/public /srv
# Legacy-URL 301s (map {path} fragment). On the CHNM deploy path this container's
# Caddyfile is discarded — the pipeline extracts /srv and the target host's Caddy
# imports redirects.caddy from the deployed content root. So it MUST live inside
# /srv (as in teachinghistory, where it ships via Hugo's static/ -> public/);
# anywhere else and it's absent from the release artifact and every legacy URL 404s.
# Landing it at /srv/redirects.caddy also gives `docker run` local-dev parity below.
COPY --from=build-stage /app/redirects.caddy /srv/redirects.caddy

COPY <<'EOF' /etc/caddy/Caddyfile
{
	auto_https off
	admin off
}

:80 {
	root * /srv
	encode gzip zstd

	# Legacy Omeka URL redirects (301s). Kept first so they win before
	# file_server. /files/* is intentionally absent — the fronting web
	# server redirects /files/* to the object-storage bucket.
	import /srv/redirects.caddy

	file_server
}
EOF

ENV XDG_CONFIG_HOME=/tmp/caddy-config \
    XDG_DATA_HOME=/tmp/caddy-data

EXPOSE 80
ENTRYPOINT ["/usr/bin/caddy"]
CMD ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
