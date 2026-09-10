FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171

ARG DEBIAN_FRONTEND=noninteractive
ARG NOVNC_VERSION=1.6.0
ARG NOVNC_SHA256=5066103959ef4e9b10f37e5a148627360dd8414e4cf8a7db92bdbd022e728aaa
ARG WEBSOCKIFY_VERSION=0.10.0
ARG WEBSOCKIFY_SHA256=7bd99b727e0be230f6f47f65fbe4bd2ae8b2aa3568350148bdf5cf440c4c6b4a

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        chromium \
        chromium-sandbox \
        curl \
        dbus-x11 \
        fluxbox \
        fonts-noto \
        fonts-noto-cjk \
        fonts-noto-color-emoji \
        openssl \
        python3 \
        python3-numpy \
        tigervnc-common \
        tigervnc-standalone-server \
        tigervnc-tools \
        tini \
        x11-utils \
        x11-xserver-utils \
        xdg-utils \
    && curl --fail --location --show-error --silent \
        "https://github.com/novnc/noVNC/archive/refs/tags/v${NOVNC_VERSION}.tar.gz" \
        --output /tmp/novnc.tar.gz \
    && echo "${NOVNC_SHA256}  /tmp/novnc.tar.gz" | sha256sum --check --strict \
    && install -d /opt/novnc \
    && tar --extract --gzip --file /tmp/novnc.tar.gz --strip-components=1 --directory /opt/novnc \
    && curl --fail --location --show-error --silent \
        "https://github.com/novnc/websockify/archive/refs/tags/v${WEBSOCKIFY_VERSION}.tar.gz" \
        --output /tmp/websockify.tar.gz \
    && echo "${WEBSOCKIFY_SHA256}  /tmp/websockify.tar.gz" | sha256sum --check --strict \
    && install -d /opt/websockify \
    && tar --extract --gzip --file /tmp/websockify.tar.gz --strip-components=1 --directory /opt/websockify \
    && ln -s /opt/websockify /opt/novnc/utils/websockify \
    && cp /opt/novnc/vnc.html /opt/novnc/index.html \
    && find /opt/novnc/tests /opt/websockify/tests -depth -delete \
    && rm -f /tmp/novnc.tar.gz /tmp/websockify.tar.gz \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 10001 browser \
    && useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash browser \
    && install -d -o browser -g browser \
        /opt/browser-console \
        /etc/chromium/policies/managed

COPY --chown=browser:browser start-desktop.sh /opt/browser-console/start-desktop.sh
COPY --chown=browser:browser fluxbox-startup /opt/browser-console/fluxbox-startup
COPY --chown=browser:browser healthcheck.sh /opt/browser-console/healthcheck.sh
COPY --chown=browser:browser policy-probe.py /opt/browser-console/policy-probe.py
COPY --chown=browser:browser browser_console_protocol.py /opt/browser-console/browser_console_protocol.py
COPY mandatory.json /opt/novnc/mandatory.json
RUN chmod 0755 \
        /opt/browser-console/start-desktop.sh \
        /opt/browser-console/fluxbox-startup \
        /opt/browser-console/healthcheck.sh \
        /opt/browser-console/policy-probe.py \
    && chmod 0644 \
        /opt/browser-console/browser_console_protocol.py \
        /opt/novnc/mandatory.json

USER 10001:10001
EXPOSE 6080
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/browser-console/start-desktop.sh"]
