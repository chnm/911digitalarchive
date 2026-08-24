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

ARG hugobuildargs=--environment production
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
# Legacy-URL 301s (map {path} fragment). NOTE: on the CHNM deploy path this
# container's Caddyfile is discarded — the pipeline extracts /srv and the target
# host's Caddy imports redirects.caddy itself. The COPY + import below only give
# `docker run` of this image local-dev parity with production.
COPY --from=build-stage /app/redirects.caddy /etc/caddy/redirects.caddy

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
	import /etc/caddy/redirects.caddy

	file_server
}
EOF

ENV XDG_CONFIG_HOME=/tmp/caddy-config \
    XDG_DATA_HOME=/tmp/caddy-data

EXPOSE 80
ENTRYPOINT ["/usr/bin/caddy"]
CMD ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
