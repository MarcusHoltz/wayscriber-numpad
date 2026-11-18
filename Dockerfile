# Disposable build environment for every supported host (Arch, Debian 13+,
# Fedora). Nothing here touches the host: Rust, headers and both upstream
# git clones live in this image. Only the finished wayscriber binary and the
# built keyd tree leave the container (see docker-compose.yml), into ./dist/.
#
# One image for all distros: the binary links against the host's system
# libraries, so it is built on the oldest glibc we support (Debian 13,
# glibc 2.41). Arch and Fedora have the same or newer glibc and run it as-is.
FROM rust:1-slim-trixie

ARG WAYSCRIBER_REF=main
ARG KEYD_REF=v2.6.0

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential git curl ca-certificates pkg-config \
      libcairo2-dev libpango1.0-dev libwayland-dev libxkbcommon-dev \
      libgtk-4-dev libgtk4-layer-shell-dev libadwaita-1-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch "${WAYSCRIBER_REF}" --depth 1 \
    https://github.com/devmobasa/wayscriber.git /src
WORKDIR /src

RUN rust_channel=$(grep -m1 '^channel' rust-toolchain.toml | sed -E 's/.*"([^"]+)".*/\1/') \
    && rustup toolchain install "$rust_channel" --profile minimal

# Rust 1.99's LLVM backend can segfault under parallel release codegen on
# small build containers; a bigger rustc stack and lower job count avoid it.
ENV RUST_MIN_STACK=33554432
ENV CARGO_BUILD_JOBS=2
RUN cargo build --release

# Fedora has no keyd package. Build the pinned upstream release here so the
# Fedora host only needs `make install` (no compiler, no git clone). Arch
# and Debian install keyd from their own repos and ignore this tree.
RUN git clone --branch "${KEYD_REF}" --depth 1 \
    https://github.com/rvaiya/keyd.git /keyd \
    && cd /keyd && make

# `docker compose run` copies the artifacts into the bind-mounted /out.
# keyd's Makefile reads README.md during `make install`, so it must be staged
# along with the built binaries and support files.
CMD ["sh", "-c", "cp /src/target/release/wayscriber /out/wayscriber && chmod 755 /out/wayscriber && mkdir -p /out/keyd && cp -a /keyd/bin /keyd/data /keyd/docs /keyd/examples /keyd/layouts /keyd/keyd.service.in /keyd/Makefile /keyd/README.md /out/keyd/"]
