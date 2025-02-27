# Dockerfile for the 2025 eCTF
# Make any changes here to set up your build environment (e.g., installing crypto
# libraries, dependencies, the compiler for a different language)

FROM ubuntu:24.04

LABEL version="0.2"
LABEL description="Example Decoder Docker Container for the 2025 eCTF"

ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /root

# Install Requisite Packages
# do this first because it takes the longest
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    gdb \
    gdb-multiarch \
    gcc-arm-none-eabi \
    binutils-arm-none-eabi \
    make \
    python3.10 \
    git \
    wget \
    libtool \
    texinfo \
    unzip \
    curl \
    xz-utils

# Install MSDK
RUN apt-get install -y unzip && \
    wget https://github.com/analogdevicesinc/msdk/archive/refs/tags/v2024_02.zip && \
    unzip v2024_02.zip && \
    rm -f v2024_02.zip

RUN curl -L "https://ziglang.org/download/0.13.0/zig-linux-$(uname -m)-0.13.0.tar.xz" -o zig.tar.xz && \
    tar -xf zig.tar.xz && \
    mv zig-linux-$(uname -m)-0.13.0 /usr/local/zig && \
    ln -s /usr/local/zig/zig /usr/local/bin/zig && \
    chmod +x /usr/local/zig/zig && \
    rm zig.tar.xz

ENV MAXIM_PATH=/root/msdk-2024_02

RUN curl -L "https://github.com/orlp/ed25519/archive/refs/heads/master.zip" -o ed25519.zip && \
    unzip ed25519.zip && \
    rm ed25519.zip

ENV ED25519_PATH=/root/ed25519-master

ENV ZIG_LOCAL_CACHE_DIR=/root/zig-cache
ENV SECRETS_PATH=/global.secrets

WORKDIR /decoder

ENTRYPOINT ["bash", "-c", "make release DECODER_ID=${DECODER_ID}"]
