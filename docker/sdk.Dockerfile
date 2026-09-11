FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ssh make gcc gcc-multilib g++-multilib module-assistant expect \
    g++ gawk texinfo libssl-dev bison flex fakeroot cmake unzip gperf \
    autoconf device-tree-compiler libncurses5-dev pkg-config bc \
    python3 python-is-python3 passwd openssl openssh-server openssh-client \
    vim file cpio rsync ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /work
ENTRYPOINT ["/bin/bash"]
