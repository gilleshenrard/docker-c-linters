# SPDX-FileCopyrightText: 2026 Gilles Henrard <contact@gilleshenrard.com>
#
# SPDX-License-Identifier: MIT

ARG CPPCHECKVERSION="2.20.0"
ARG CLANGVERSIONMAJOR="22"
ARG CLANGVERSION="22.1.0"
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

#Install prerequisites
RUN apt-get update && apt-get install -y wget build-essential cmake ninja-build python3 python3-pip python3-venv

#Install CppCheck
RUN wget -O cppcheck.tar.gz "https://github.com/cppcheck-opensource/cppcheck/archive/refs/tags/${CPPCHECKVERSION}.tar.gz"
RUN mkdir -p /opt/cppcheck /tmp/cppcheck
RUN tar --strip-components=1 -xvf cppcheck.tar.gz -C /tmp/cppcheck
RUN rm cppcheck.tar.gz
RUN cd /tmp/cppcheck
RUN cmake -S /tmp/cppcheck -B /tmp/cppcheck/build -DCMAKE_INSTALL_PREFIX=/opt/cppcheck
RUN cmake --build /tmp/cppcheck/build
RUN cmake --install /tmp/cppcheck/build

#Install Clang tools
RUN wget -O llvm_clang.tar.gz "https://github.com/llvm/llvm-project/releases/download/llvmorg-${CLANGVERSION}/LLVM-${CLANGVERSION}-Linux-X64.tar.xz"
RUN mkdir -p /opt/clang/bin
RUN mkdir -p /opt/clang/lib/clang/${CLANGVERSIONMAJOR}/include/
RUN tar -xvf llvm_clang.tar.gz \
        --strip-components=2 \
        -C /opt/clang/bin \
        LLVM-${CLANGVERSION}-Linux-X64/bin/clang-format \
        LLVM-${CLANGVERSION}-Linux-X64/bin/clang-tidy \
        LLVM-${CLANGVERSION}-Linux-X64/bin/run-clang-tidy
RUN tar -xvf llvm_clang.tar.gz \
        --strip-components=4 \
        -C /opt/clang/lib/clang/${CLANGVERSIONMAJOR}/ \
        LLVM-${CLANGVERSION}-Linux-X64/lib/clang/${CLANGVERSIONMAJOR}/include/
RUN rm llvm_clang.tar.gz

#Install lizard and REUSE
RUN python3 -m venv /opt/pip-packages
RUN /opt/pip-packages/bin/pip install lizard==${LIZARDVERSION} reuse==${REUSEVERSION}
RUN rm -rf /opt/pip-packages/bin/pip*


##################################################################################################################################
# 2. Run stage
##################################################################################################################################
FROM debian:trixie-slim AS run

#Install prerequisites
RUN apt-get update \
    && apt-get install \
        -y --no-install-recommends \
        python3 \
        doxygen \
        git \
        file \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

#Copy Python tools and make them globally available
COPY --from=build /opt /opt
ENV PATH="$PATH:/opt/cppcheck/bin/:/opt/clang/bin/:/opt/pip-packages/bin"
