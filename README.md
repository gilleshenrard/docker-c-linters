# C Linting & Analysis Docker Image
 
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
 
A multi-stage Docker image providing a self-contained, reproducible environment for
static analysis, formatting, complexity measurement, license compliance checking, and
documentation generation — primarily targeting embedded C/C++ projects.
 
**Github:** [gilleshenrard/docker-c-linters](https://github.com/gilleshenrard/docker-c-linters)
**DockerHub:** [gilleshenrard/docker-c-linters/general](https://hub.docker.com/repository/docker/gilleshenrard/c-linters/general)
 
---
 
## Included Tools
 
> **Maintainer note:** Tool versions are hardcoded in this README. Remember to update
> this table whenever versions are bumped in the Dockerfile.
 
| Tool                                                                              | Version               | Purpose                                      |
|-----------------------------------------------------------------------------------|-----------------------|----------------------------------------------|
| [CppCheck](https://cppcheck.sourceforge.io/)                                      | 2.21.0                | Static analysis                              |
| [Clang-Format](https://clang.llvm.org/docs/ClangFormat.html)                      | 22.1.8                | Code formatting                              |
| [Clang-Tidy](https://clang.llvm.org/extra/clang-tidy/)                            | 22.1.8                | Linting and static analysis                  |
| [run-clang-tidy](https://clang.llvm.org/extra/clang-tidy/#using-clang-tidy)       | 22.1.8                | Parallel Clang-Tidy runner                   |
| [Lizard](https://github.com/terryyin/lizard)                                      | 1.24.0                | Cyclomatic complexity measurement            |
| [REUSE](https://reuse.software/)                                                  | 6.2.0                 | SPDX license compliance checker              |
| [Doxygen](https://www.doxygen.nl/)                                                | 1.18.0                | Documentation generation                     |
 
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
  --build-arg LIZARDVERSION="1.23.1" \
  --build-arg REUSEVERSION="6.3.0" \
  --build-arg DOXYGENVERSION="1.18.0" \
  -t <image_name>:<image_revision> .
```
 
---

## Vulnerability Scanning

Vulnerabilities can be checked using [Docker Scout](https://docs.docker.com/scout/).

> **Note:** Scout caches SBOMs locally, keyed by image digest. When re-scanning a
> freshly rebuilt image under the same tag, clear the cache first to avoid stale
> results.

```bash
# Clear Scout's local SBOM cache (non-interactive)
docker scout cache prune --sboms --force

# Generate a CVE report in Markdown format
docker scout cves <image_name>:<image_revision> --format markdown --output <image_name>_report.md
```

> [!WARNING]
> **Residual vulnerabilities are expected and are not fixable from this image.**
> The overwhelming majority of CVEs flagged by Docker Scout come from OS-level packages
> that are part of the `debian:trixie-slim` base image itself, not from anything
> installed by this Dockerfile. These vulnerabilities remain until Debian's security
> team ships a patch upstream; no build-arg override, `apt` flag, or workaround in this
> repository can resolve them. Rebuilding the image regularly will pick up upstream
> fixes as they become available, but a completely clean Scout report should **not** be
> expected as a baseline for this image.
>
> In practice, the security impact of this is limited: this image is meant to be run
> as a one-off tool (`docker run --rm ...`) rather than as a long-lived service, which
> significantly reduces the exposure window and attack surface these base-image CVEs
> would otherwise represent.

### Tracing a Flagged Package's Origin

To find out which installed package pulled in a given vulnerable dependency (e.g. a
package named in a Scout report), run the following against the built image, not a
fresh base image (dependency resolution can otherwise differ from what was actually
installed):

```bash
# 1. Scout's report may name a bare library (e.g. "tiff"); find the actual installed
#    Debian package name, since it is often versioned or prefixed differently (e.g.
#    "libtiff6")
docker run --rm <image_name>:<image_revision> bash -c "dpkg -l | grep -i <package>"

# 2. Once you have the real package name, trace which installed package depends on it
docker run --rm <image_name>:<image_revision> bash -c \
  "apt-get update -qq && apt-get install -y aptitude >/dev/null 2>&1 && aptitude why <real_package_name>"
```

---
 
## Image Architecture
 
The image uses a **two-stage build** to keep the final image lean:
 
```
+-----------------------------------------------+
| Stage 1 : build (debian:trixie-slim)          |
|                                               |
|  - Compile CppCheck from source               |
|  - Extract Clang binaries from LLVM release   |
|  - Install Doxygen from its Github repo       |
|  - Install Lizard + REUSE in Python venv      |
+------------------------|----------------------+
                         | COPY /opt
+------------------------|----------------------+
| Stage 2 : run (debian:trixie-slim)            |
|                                               |
|  - Install python3, git, file, graphviz,      |
|    ca-certificates                            |
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
| `/opt/doxygen/bin/`         | `doxygen`                                      |
 
All of the above are appended to `PATH`, so every tool is callable directly by name.
 
---
 
## License
 
This Dockerfile is distributed under the [MIT License](https://opensource.org/licenses/MIT).  
© 2026 Gilles Henrard <contact@gilleshenrard.com>