# SPDX-FileCopyrightText: 2026 Gilles Henrard <contact@gilleshenrard.com>
#
# SPDX-License-Identifier: MIT

ARG CPPCHECKVERSION="2.21.0"
ARG CLANGVERSIONMAJOR="22"
ARG CLANGVERSION="22.1.8"
ARG LIZARDVERSION="1.23.0"
ARG REUSEVERSION="6.2.0"


##################################################################################################################################
# 1. Build stage
##################################################################################################################################
FROM debian:trixie-slim AS build
SHELL ["/bin/bash", "-c"]

#Redefine arguments so they're available in this step
ARG CPPCHECKVERSION
ARG CLANGVERSIONMAJOR
ARG CLANGVERSION
ARG LIZARDVERSION
ARG REUSEVERSION

#Install prerequisites and update base OS packages
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get dist-upgrade -y \
    && apt-get autoremove -y \
    && apt-get install -y \
        wget \
        build-essential \
        cmake \
        ninja-build \
        python3 \
        python3-venv

#Install CppCheck from its Github repo
RUN wget -O cppcheck.tar.gz "https://github.com/cppcheck-opensource/cppcheck/archive/refs/tags/${CPPCHECKVERSION}.tar.gz" \
    && mkdir -p /opt/cppcheck /tmp/cppcheck \
    && tar --strip-components=1 -xvf cppcheck.tar.gz -C /tmp/cppcheck \
    && rm cppcheck.tar.gz \
    && cmake -S /tmp/cppcheck -B /tmp/cppcheck/build -DCMAKE_INSTALL_PREFIX=/opt/cppcheck \
    && cmake --build /tmp/cppcheck/build --parallel $(nproc) \
    && cmake --install /tmp/cppcheck/build

#Install Clang tools from their Github repo
RUN wget -O llvm_clang.tar.gz "https://github.com/llvm/llvm-project/releases/download/llvmorg-${CLANGVERSION}/LLVM-${CLANGVERSION}-Linux-X64.tar.xz" \
    && mkdir -p /opt/clang/bin \
    && mkdir -p /opt/clang/lib/clang/${CLANGVERSIONMAJOR}/include/ \
    && tar -xvf llvm_clang.tar.gz \
        --strip-components=2 \
        -C /opt/clang/bin \
        LLVM-${CLANGVERSION}-Linux-X64/bin/clang-format \
        LLVM-${CLANGVERSION}-Linux-X64/bin/clang-tidy \
        LLVM-${CLANGVERSION}-Linux-X64/bin/run-clang-tidy \
    && tar -xvf llvm_clang.tar.gz \
        --strip-components=4 \
        -C /opt/clang/lib/clang/${CLANGVERSIONMAJOR}/ \
        LLVM-${CLANGVERSION}-Linux-X64/lib/clang/${CLANGVERSIONMAJOR}/include/ \
    && rm llvm_clang.tar.gz

#Create a Python 3 venv
RUN python3 -m venv /opt/pip-packages

#Install pip (official script is used to install latest version and fix vulnerabilities)
RUN wget -O get-pip.py "https://bootstrap.pypa.io/get-pip.py" \
    && /opt/pip-packages/bin/python3 get-pip.py \
    && rm get-pip.py

#Install lizard and REUSE, and upgrade dependencies to fix vulnerabilities
RUN /opt/pip-packages/bin/pip install lizard==${LIZARDVERSION} reuse==${REUSEVERSION} \
    && /opt/pip-packages/bin/pip install --upgrade "setuptools>=78.1.1" "msgpack>=1.2.1"

#Cleanup pip's directories in the venv (install is leaner and fixes vulnerabilities)
RUN rm -rf /opt/pip-packages/bin/pip* /opt/pip-packages/lib/python*/site-packages/pip


##################################################################################################################################
# 2. Run stage
##################################################################################################################################
FROM debian:trixie-slim AS run

#Install prerequisites and Doxygen
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get dist-upgrade -y \
    && apt-get autoremove -y \
    && apt-get install \
        -y --no-install-recommends \
        python3 \
        doxygen \
        git \
        file \
        xz-utils \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

#Copy previously installed tools and make them globally available
COPY --from=build /opt /opt
ENV PATH="$PATH:/opt/cppcheck/bin/:/opt/clang/bin/:/opt/pip-packages/bin"
