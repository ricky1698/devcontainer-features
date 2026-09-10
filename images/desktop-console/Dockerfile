FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171

ARG DEBIAN_FRONTEND=noninteractive
ARG NOVNC_VERSION=1.6.0
ARG NOVNC_SHA256=5066103959ef4e9b10f37e5a148627360dd8414e4cf8a7db92bdbd022e728aaa
ARG WEBSOCKIFY_VERSION=0.10.0
ARG WEBSOCKIFY_SHA256=7bd99b727e0be230f6f47f65fbe4bd2ae8b2aa3568350148bdf5cf440c4c6b4a

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl --fail --location --show-error --silent \
        https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --yes --dearmor -o /etc/apt/keyrings/google-chrome.gpg \
    && chmod a+r /etc/apt/keyrings/google-chrome.gpg \
    && printf '%s\n' \
        'Types: deb' \
        'URIs: https://dl.google.com/linux/chrome-stable/deb/' \
        'Suites: stable' \
        'Components: main' \
        'Architectures: amd64' \
        'Signed-By: /etc/apt/keyrings/google-chrome.gpg' \
        >/etc/apt/sources.list.d/google-chrome.sources \
    && apt-get update \
    && apt-get install --yes --no-install-recommends \
        adwaita-icon-theme \
        dbus-x11 \
        fluxbox \
        fonts-noto \
        fonts-noto-cjk \
        fonts-noto-color-emoji \
        google-chrome-stable \
        gsettings-desktop-schemas \
        htop \
        libsecret-1-0 \
        mousepad \
        procps \
        python3 \
        python3-numpy \
        tigervnc-common \
        tigervnc-standalone-server \
        tigervnc-tools \
        tilix \
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

RUN groupadd --gid 10001 desktop \
    && useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash desktop \
    && install -d -o desktop -g desktop /opt/desktop-console

COPY --chown=desktop:desktop start-desktop.sh /opt/desktop-console/start-desktop.sh
COPY --chown=desktop:desktop fluxbox-startup /opt/desktop-console/fluxbox-startup
COPY --chown=desktop:desktop healthcheck.sh /opt/desktop-console/healthcheck.sh
COPY --chown=desktop:desktop set-resolution /opt/desktop-console/set-resolution
COPY --chown=desktop:desktop skel /opt/desktop-console/skel
COPY qnx-photon-dark /usr/share/fluxbox/styles/qnx-photon-dark
COPY mandatory.json defaults.json /opt/novnc/
RUN chmod 0755 \
        /opt/desktop-console/start-desktop.sh \
        /opt/desktop-console/fluxbox-startup \
        /opt/desktop-console/healthcheck.sh \
        /opt/desktop-console/set-resolution \
    && chmod -R a+rX /opt/desktop-console/skel \
    && chmod 0644 \
        /usr/share/fluxbox/styles/qnx-photon-dark \
        /opt/novnc/mandatory.json \
        /opt/novnc/defaults.json

USER 10001:10001
ENV DISPLAY=:1
EXPOSE 6080
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/desktop-console/start-desktop.sh"]
