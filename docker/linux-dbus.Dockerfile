# Linux testing container with D-Bus support
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # D-Bus and notification daemon
    dbus \
    libdbus-1-dev \
    notification-daemon \
    dunst \
    # X11 for headless testing
    xvfb \
    x11-utils \
    # Build tools
    wget \
    xz-utils \
    git \
    # Cleanup
    && rm -rf /var/lib/apt/lists/*

# Install Zig (same version as development)
ARG ZIG_VERSION=0.15.1
RUN wget --progress=bar:force https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz \
    && tar -xf zig-x86_64-linux-${ZIG_VERSION}.tar.xz \
    && mv zig-x86_64-linux-${ZIG_VERSION} /usr/local/zig \
    && ln -s /usr/local/zig/zig /usr/local/bin/zig \
    && rm zig-x86_64-linux-${ZIG_VERSION}.tar.xz

# Setup D-Bus directories
RUN mkdir -p /var/run/dbus

# Setup working directory
WORKDIR /workspace

# Setup D-Bus session environment
ENV DBUS_SESSION_BUS_ADDRESS=unix:path=/var/run/dbus/session_bus_socket
ENV DISPLAY=:99

# Copy entrypoint script
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Run as root to avoid permission issues
ENTRYPOINT ["/entrypoint.sh"]
CMD ["zig", "build", "test", "--cache-dir", "/tmp/zig-cache"]
