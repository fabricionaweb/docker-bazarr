# syntax=docker/dockerfile:1-labs
FROM public.ecr.aws/docker/library/alpine:3.19 AS base
ENV TZ=UTC
WORKDIR /src

# source stage =================================================================
FROM base AS source

# get and extract source from git
ARG BRANCH
ARG VERSION
ADD https://github.com/morpheus65535/bazarr.git#${BRANCH:-v$VERSION} ./

# bazarr versioning
RUN echo "v$VERSION" > VERSION

# unrar stage ==================================================================
FROM base as build-unrar

# dependencies
RUN apk add --no-cache build-base

# get and extract
ARG UNRAR_VERSION=6.2.8
RUN wget -qO- https://www.rarlab.com/rar/unrarsrc-$UNRAR_VERSION.tar.gz | tar xz --strip-component 1

# build
RUN make && make install

# frontend stage ===============================================================
FROM base AS build-frontend

# dependencies
RUN apk add --no-cache nodejs-current && corepack enable npm

# node_modules
COPY --from=source /src/frontend/package*.json /src/frontend/tsconfig.json ./
RUN npm ci --fund=false --audit=false

# frontend source and build
COPY --from=source /src/frontend ./
RUN npm run build && \
    find ./ -name "*.map" -type f -delete

# virtual env stage ============================================================
FROM base AS build-venv

# dependencies
RUN apk add --no-cache build-base python3-dev openblas-dev

# copy requirements
COPY --from=source /src/requirements.txt /src/postgres-requirements.txt ./

# creates python env
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install -r postgres-requirements.txt -r requirements.txt

# runtime stage ================================================================
FROM base

ENV S6_VERBOSITY=0 S6_BEHAVIOUR_IF_STAGE2_FAILS=2 PUID=65534 PGID=65534
WORKDIR /config
VOLUME /config
EXPOSE 6767

# copy files
COPY --from=source /src/bazarr /app/bazarr
COPY --from=source /src/libs /app/libs
COPY --from=source /src/migrations /app/migrations
COPY --from=source /src/bazarr.py /src/VERSION /app/
COPY --from=build-unrar /usr/bin/unrar /usr/bin/
COPY --from=build-frontend /src/build /app/frontend/build
COPY --from=build-venv /opt/venv /opt/venv
COPY ./rootfs/. /

# runtime dependencies
RUN apk add --no-cache tzdata s6-overlay ffmpeg mediainfo openblas python3 curl

# creates python env
ENV PATH="/opt/venv/bin:$PATH"

# run using s6-overlay
ENTRYPOINT ["/init"]
