FROM ubuntu:22.04

RUN apt-get update

RUN apt-get install -y software-properties-common && \
    add-apt-repository ppa:deadsnakes/ppa -y
RUN DEBIAN_FRONTEND=noninteractive TZ=Europe/Zurich \
    apt-get install -y tzdata wget curl python3.10-dev

RUN update-alternatives --install /usr/local/bin/python3 python3 /usr/bin/python3.10 20 && \
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3 && \
    python3 -m pip install numpy polars networkx jupyter ipykernel \
         black tqdm distfit plotly.express seaborn conan

RUN wget https://github.com/llvm/llvm-project/releases/download/llvmorg-15.0.2/clang+llvm-15.0.2-x86_64-unknown-linux-gnu-rhel86.tar.xz && \
    tar -xf clang+llvm-15.0.2-x86_64-unknown-linux-gnu-rhel86.tar.xz && \
    mv clang+llvm-15.0.2-x86_64-unknown-linux-gnu /clang+llvm-15 && \
    rm clang+llvm-15.0.2-x86_64-unknown-linux-gnu-rhel86.tar.xz

RUN wget https://download.swift.org/swift-6.0.3-release/ubuntu2204/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE-ubuntu22.04.tar.gz && \
    tar -xf swift-6.0.3-RELEASE-ubuntu22.04.tar.gz && \
    mv swift-6.0.3-RELEASE-ubuntu22.04 /swift-5 && \
    rm swift-6.0.3-RELEASE-ubuntu22.04.tar.gz

RUN wget https://nodejs.org/dist/v18.16.1/node-v18.16.1-linux-x64.tar.xz && \
    tar -xf node-v18.16.1-linux-x64.tar.xz && \
    mv node-v18.16.1-linux-x64 /node && \
    rm node-v18.16.1-linux-x64.tar.xz

RUN apt-get install -y linux-tools-generic build-essential \
    fish git bat fd-find hyperfine ripgrep cargo rustc clangd jq \
    strace ltrace automake cmake meson ninja-build bear \
    libtool pkg-config perl flex bison ruby zlib1g-dev libyaml-dev \
    gfortran re2c openjdk-11-jdk libffi-dev libbz2-dev libsqlite3-dev libxml2-dev libssl-dev libncurses-dev

RUN export PATH=/node/bin/:$PATH && \
    /node/bin/npm install -g yarn express body-parser @iarna/toml minimist && \
    yarn --version

ENV PATH="/clang+llvm-15/bin:/swift-5/usr/bin:/node/bin:${PATH}"
