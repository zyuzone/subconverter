# ============================================================
# Stage 1: Build dependencies (QuickJS, libcron, toml11)
# ============================================================
FROM alpine:3.19 AS deps

ARG THREADS=4

RUN apk add --no-cache \
    git g++ build-base linux-headers cmake make python3

# ---- QuickJS / quickjspp ----
RUN git clone https://github.com/ftk/quickjspp --depth=1 /build/quickjspp && \
    cd /build/quickjspp && \
    git submodule update --init && \
    cmake -DCMAKE_BUILD_TYPE=Release . && \
    make quickjs -j${THREADS} && \
    install -d /usr/lib/quickjs/ && \
    install -m644 quickjs/libquickjs.a /usr/lib/quickjs/ && \
    install -d /usr/include/quickjs/ && \
    install -m644 quickjs/quickjs.h quickjs/quickjs-libc.h /usr/include/quickjs/ && \
    install -m644 quickjspp.hpp /usr/include/

# ---- libcron ----
RUN git clone https://github.com/PerMalmberg/libcron --depth=1 /build/libcron && \
    cd /build/libcron && \
    git submodule update --init && \
    cmake -DCMAKE_BUILD_TYPE=Release . && \
    make libcron -j${THREADS} && \
    install -m644 libcron/out/Release/liblibcron.a /usr/lib/ && \
    install -d /usr/include/libcron/ && \
    install -m644 libcron/include/libcron/* /usr/include/libcron/ && \
    install -d /usr/include/date/ && \
    install -m644 libcron/externals/date/include/date/* /usr/include/date/

# ---- toml11 ----
RUN git clone https://github.com/ToruNiina/toml11 --branch=v4.3.0 --depth=1 /build/toml11 && \
    cd /build/toml11 && \
    cmake -DCMAKE_CXX_STANDARD=11 . && \
    make install -j${THREADS}

# ============================================================
# Stage 2: Build subconverter from local source
# ============================================================
FROM deps AS builder

ARG THREADS=4

# System libraries needed for building
RUN apk add --no-cache \
    curl-dev rapidjson-dev pcre2-dev yaml-cpp-dev

# Copy local source (your patched version with proxy_github support)
WORKDIR /src
COPY . .

RUN cmake -DCMAKE_BUILD_TYPE=Release . && \
    make -j${THREADS}

# ============================================================
# Stage 3: Minimal runtime image
# ============================================================
FROM alpine:3.19

LABEL maintainer="subconverter"
LABEL description="Subscription converter with GitHub proxy support"

# Runtime dependencies only
RUN apk add --no-cache pcre2 libcurl yaml-cpp ca-certificates tzdata

# Copy binary and base config files
COPY --from=builder /src/subconverter /usr/bin/subconverter
COPY --from=builder /src/base /base

# -------- Proxy environment variables --------
# GitHub proxy — used for all access to api.github.com,
# raw.githubusercontent.com, gist.githubusercontent.com, etc.
# Format examples:
#   http://127.0.0.1:7890
#   http://user:pass@proxy.example.com:8080
#   socks5://127.0.0.1:1080
#   socks5://user:pass@proxy.example.com:1080
ENV GITHUB_PROXY=""

# General proxy used for config/ruleset/subscription fetching.
# Mirrors the proxy_config / proxy_ruleset / proxy_subscription
# settings; set to SYSTEM to use system proxy, NONE to disable.
ENV PROXY_CONFIG="NONE"
ENV PROXY_RULESET="NONE"
ENV PROXY_SUBSCRIPTION="NONE"

# Listen port (can also be overridden via pref.ini)
ENV PORT=25500

# Timezone
ENV TZ=Asia/Shanghai
RUN ln -sf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Entrypoint script — applies ENV vars into pref.ini before starting
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /base
EXPOSE 25500/tcp

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["subconverter"]
