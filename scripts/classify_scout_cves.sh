#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Gilles Henrard <contact@gilleshenrard.com>
# SPDX-License-Identifier: MIT
#
# Classify the CVEs of two Docker Scout SARIF reports (the published image and a
# fresh rebuild) and print a verdict for the monthly cron.
#
# Usage:
#   classify_scout_cves.sh <published.sarif.json> <rebuild.sarif.json>
#
# Both reports must come from the SAME Scout database (i.e. scanned in the same
# run). When Debian ships a fix, Scout reclassifies that CVE in the already-
# published image from "not fixed" to fixable, so "the published image has
# fixable CVEs" is exactly the signal that it is stale.
#
# Output: key=value lines on stdout, directly appendable to $GITHUB_OUTPUT:
#   verdict=<FAIL_FIXABLE_REMAINS|RELEASE|NOTHING_TO_DO>
#   fixed_cves=<space-separated ids fixed by the rebuild, or empty>
#   remaining_fixable=<space-separated ids still fixable after the rebuild>
#   new_unfixable=<space-separated non-fixable ids absent from the published image>
#
# Exit code: 0 whenever a verdict was computed, non-zero only if the script
# itself could not run (bad usage, missing file, invalid JSON). What to DO about
# the verdict -- warn, fail, release -- is the caller's decision.

set -euo pipefail

readonly NOT_FIXED_MARKER="not fixed"

#######################################
# Print the sorted, unique CVE ids of a Scout SARIF report, filtered by
# fixability. One entry per CVE lives in runs[0].tool.driver.rules[]
# (results[] holds one entry per affected file and would multi-count). A CVE
# is fixable when properties.fixed_version is anything but "not fixed"; a
# missing field counts as not fixed.
# Arguments:
#   $1: path to the SARIF report
#   $2: "fixable" or "unfixable"
# Outputs:
#   One CVE id per line on stdout
#######################################
cve_ids() {
    local sarif_path="$1"
    local wanted_kind="$2"

    jq -r --arg kind "${wanted_kind}" --arg marker "${NOT_FIXED_MARKER}" '
        (.runs[0].tool.driver.rules // [])[]
        | ((.properties.fixed_version // $marker) != $marker) as $is_fixable
        | select(($kind == "fixable") == $is_fixable)
        | .id
    ' "${sarif_path}" | sort -u
}

#######################################
# Join newline-separated lines from stdin into one space-separated line.
# Outputs:
#   The joined line on stdout (empty if stdin is empty)
#######################################
one_line() {
    paste -sd ' ' -
}

main() {
    if [[ $# -ne 2 ]]; then
        echo "Usage: $0 <published.sarif.json> <rebuild.sarif.json>" >&2
        return 1
    fi

    local -r published_sarif="$1"
    local -r rebuild_sarif="$2"

    local stale_fixable
    local remaining_fixable
    local new_unfixable
    stale_fixable=$(cve_ids "${published_sarif}" fixable | one_line)
    remaining_fixable=$(cve_ids "${rebuild_sarif}" fixable | one_line)
    new_unfixable=$(comm -13 \
        <(cve_ids "${published_sarif}" unfixable) \
        <(cve_ids "${rebuild_sarif}" unfixable) | one_line)

    # A fresh rebuild should pick up every available fix: if a fixable CVE
    # survives it, nothing is released until the source is fixed.
    local verdict="NOTHING_TO_DO"
    local fixed_cves=""
    if [[ -n "${remaining_fixable}" ]]; then
        verdict="FAIL_FIXABLE_REMAINS"
    elif [[ -n "${stale_fixable}" ]]; then
        verdict="RELEASE"
        fixed_cves="${stale_fixable}"
    fi

    echo "verdict=${verdict}"
    echo "fixed_cves=${fixed_cves}"
    echo "remaining_fixable=${remaining_fixable}"
    echo "new_unfixable=${new_unfixable}"
}

main "$@"
