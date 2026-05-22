ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE}

ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG ALL_PROXY
ARG NO_PROXY
ARG http_proxy
ARG https_proxy
ARG all_proxy
ARG no_proxy

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN set -eux; \
  export http_proxy="${http_proxy:-${HTTP_PROXY:-}}"; \
  export https_proxy="${https_proxy:-${HTTPS_PROXY:-}}"; \
  export all_proxy="${all_proxy:-${ALL_PROXY:-}}"; \
  export no_proxy="${no_proxy:-${NO_PROXY:-localhost,127.0.0.1,::1}}"; \
  apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    ccache \
    cmake \
    curl \
    git \
    locales \
    ninja-build \
    pkg-config \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-venv \
    unzip \
    && locale-gen C.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    export http_proxy="${http_proxy:-${HTTP_PROXY:-}}"; \
    export https_proxy="${https_proxy:-${HTTPS_PROXY:-}}"; \
    export all_proxy="${all_proxy:-${ALL_PROXY:-}}"; \
    export no_proxy="${no_proxy:-${NO_PROXY:-localhost,127.0.0.1,::1}}"; \
    python3 -m pip install --no-cache-dir --upgrade pip wheel \
    && python3 -m pip install --no-cache-dir \
      colcon-common-extensions \
      empy==3.3.4 \
      lark \
      catkin_pkg \
      packaging \
      PyYAML \
      setuptools==59.6.0 \
      vcstool

ENV PATH=/usr/lib/ccache:${PATH}

WORKDIR /work