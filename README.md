# C Linting & Analysis Docker Image
 
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
 
A multi-stage Docker image providing a self-contained, reproducible environment for
static analysis, formatting, complexity measurement, license compliance checking, and
documentation generation — primarily targeting embedded C/C++ projects.
 
**Source:** [gilleshenrard/docker-c-linters](https://github.com/gilleshenrard/docker-c-linters)
 
---
 
## Included Tools
 
> **Maintainer note:** Tool versions are hardcoded in this README. Remember to update
> this table whenever versions are bumped in the Dockerfile.
 
| Tool                                                                              | Version               | Purpose                                      |
|-----------------------------------------------------------------------------------|-----------------------|----------------------------------------------|
| [CppCheck](https://cppcheck.sourceforge.io/)                                      | 2.20.0                | Static analysis (built from source)          |
| [Clang-Format](https://clang.llvm.org/docs/ClangFormat.html)                      | 22.1.0                | Code formatting                              |
| [Clang-Tidy](https://clang.llvm.org/extra/clang-tidy/)                            | 22.1.0                | Linting and static analysis                  |
| [run-clang-tidy](https://clang.llvm.org/extra/clang-tidy/#using-clang-tidy)       | 22.1.0                | Parallel Clang-Tidy runner                   |
| [Lizard](https://github.com/terryyin/lizard)                                      | 1.23.0                | Cyclomatic complexity measurement            |
| [REUSE](https://reuse.software/)                                                  | 6.2.0                 | SPDX license compliance checker              |
| [Doxygen](https://www.doxygen.nl/)                                                | latest at build time  | Documentation generation (via apt)           |
 
---
 
## Pulling the Image
 
The image is hosted on Docker Hub and can be pulled with:
 
```bash
docker pull gilleshenrard/c-linters:latest
```
 
---
 
## Usage
 
### Run a one-off tool
 
```bash
# Static analysis
docker run --rm -v "$(pwd)":/src <image_name>:<image_revision> cppcheck --enable=all /src
 
# Format check
docker run --rm -v "$(pwd)":/src <image_name>:<image_revision> clang-format --dry-run --Werror /src/main.c
 
# Complexity report
docker run --rm -v "$(pwd)":/src <image_name>:<image_revision> lizard /src
 
# License compliance
docker run --rm -v "$(pwd)":/src <image_name>:<image_revision> reuse lint
```
 
### Interactive shell
 
```bash
docker run --rm -it -v "$(pwd)":/src <image_name>:<image_revision> bash
```
 
---
 
## GitHub Actions Integration
 
```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    container:
      image: gilleshenrard/c-linters:latest
 
    steps:
      - uses: actions/checkout@v4
 
      - name: Static analysis (CppCheck)
        run: cppcheck --enable=all --error-exitcode=1 src/
 
      - name: Format check (Clang-Format)
        run: |
          find src/ -name '*.c' -o -name '*.h' | \
          xargs clang-format --dry-run --Werror
 
      - name: Linting (Clang-Tidy)
        run: run-clang-tidy -p build/
 
      - name: Complexity (Lizard)
        run: lizard src/ --CCN 10 --length 50 --arguments 5
 
      - name: License compliance (REUSE)
        run: reuse lint
 
      - name: Documentation (Doxygen)
        run: doxygen Doxyfile
```
 
---
 
## Building the Image
 
```bash
docker build -t <image_name>:<image_revision> .
```
 
### Overriding Tool Versions
 
All versions are declared as `ARG` at the top of the Dockerfile and can be overridden
at build time:
 
```bash
docker build \
  --build-arg CPPCHECKVERSION="2.21.0" \
  --build-arg CLANGVERSION="22.2.0" \
  --build-arg CLANGVERSIONMAJOR="22" \
  --build-arg LIZARDVERSION="1.23.1" \
  --build-arg REUSEVERSION="6.3.0" \
  -t <image_name>:<image_revision> .
```
 
> **Note:** `CLANGVERSIONMAJOR` must match the major version component of
> `CLANGVERSION` (e.g. `22` for `22.1.0`). They are kept separate because the LLVM
> archive uses the full version string in its path, while the internal header directory
> uses the major version only.
 
---
 
## Image Architecture
 
The image uses a **two-stage build** to keep the final image lean:
 
```
+-----------------------------------------------+
| Stage 1 : build (debian:trixie-slim)          |
|                                               |
|  - Compile CppCheck from source               |
|  - Extract Clang binaries from LLVM release   |
|  - Install Lizard + REUSE in Python venv      |
+------------------------|----------------------+
                         | COPY /opt
+------------------------|----------------------+
| Stage 2 : run (debian:trixie-slim)            |
|                                               |
|  - Install python3, doxygen, git,             |
|    file, ca-certificates                      |
|  - Append tool paths to PATH                  |
+-----------------------------------------------+
```
 
No build toolchain (cmake, ninja, wget, gcc…) is present in the final image.
 
---
 
## Tool Locations at Runtime
 
| Path                        | Contents                                       |
|-----------------------------|------------------------------------------------|
| `/opt/cppcheck/bin/`        | `cppcheck` binary                              |
| `/opt/clang/bin/`           | `clang-format`, `clang-tidy`, `run-clang-tidy` |
| `/opt/clang/lib/clang/22/`  | Clang built-in headers                         |
| `/opt/pip-packages/bin/`    | `lizard`, `reuse`                              |
 
All of the above are appended to `PATH`, so every tool is callable directly by name.
 
---
 
## License
 
This Dockerfile is distributed under the [MIT License](https://opensource.org/licenses/MIT).  
© 2026 Gilles Henrard <contact@gilleshenrard.com>
