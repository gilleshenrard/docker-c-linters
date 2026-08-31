#!/usr/bin/env python3
"""Compare two Docker Scout SARIF CVE reports and decide whether a cron-triggered
release is warranted.

Schema reference (confirmed against a real `docker scout cves --format sarif`
report on 2026-08-31): each distinct CVE is one entry in
runs[0].tool.driver.rules[], identified by "id" (the CVE number). Severity lives
at rules[].properties.cvssV3_severity ("CRITICAL"|"HIGH"|"MEDIUM"|"LOW"|
"UNSPECIFIED"). Fixability is NOT a boolean: rules[].properties.fixed_version is
either an actual version string, or the literal string "not fixed".

The rules array is used rather than runs[0].results[] because results contains
one entry per affected file location, which would multiply-count a single CVE
that touches several files in the image.

Usage:
    compare_scout_reports.py <previous.sarif.json> <current.sarif.json>

This script's process exit code reflects ONLY whether it ran successfully --
0 if a verdict was computed, non-zero if it could not run at all (bad usage,
missing/unreadable file). The verdict itself -- what the caller should DO
about it, including whether to fail a CI job -- is entirely the caller's
decision, not this script's. The verdict is communicated as a plain, greppable
final line on stdout:

    VERDICT=<name>

where <name> is one of the Verdict enum members below. No environment
variables or CI-specific integration are involved, so this can be run and
inspected identically on a local machine (Windows, Linux, whatever) or inside
a GitHub Actions step -- only the caller differs in what it does with the line.
"""
import json
import sys
from enum import Enum


class Verdict(Enum):
    """Every possible outcome of comparing two Scout reports."""

    NO_RELEASE_CLEAN = "NO_RELEASE_CLEAN"
    """No change in critical/high non-fixable counts. Nothing to do."""

    RELEASE_CLEAN = "RELEASE_CLEAN"
    """Critical or high non-fixable count decreased, and neither increased."""

    FIXABLE_CVE_INTRODUCED = "FIXABLE_CVE_INTRODUCED"
    """The current build introduced a fixable CVE. Should never happen on an
    unmodified cron rebuild -- a build integrity problem, not a release
    trigger. Whether this should fail a CI job is the caller's decision."""

    REGRESSION_ONLY = "REGRESSION_ONLY"
    """No improvement anywhere, but a non-fixable critical/high count
    increased."""

    RELEASE_WITH_REGRESSION = "RELEASE_WITH_REGRESSION"
    """A critical/high non-fixable count decreased AND a different one
    increased at the same time."""


SEVERITIES_OF_INTEREST = ("CRITICAL", "HIGH")
NOT_FIXED_MARKER = "not fixed"


def load_rules(path):
    """Return the list of CVE rule entries from a Scout SARIF report."""
    with open(path, "r", encoding="utf-8") as handle:
        report = json.load(handle)
    return report["runs"][0]["tool"]["driver"]["rules"]


def is_fixable(rule):
    fixed_version = rule.get("properties", {}).get("fixed_version", NOT_FIXED_MARKER)
    return fixed_version != NOT_FIXED_MARKER


def severity_of(rule):
    return rule.get("properties", {}).get("cvssV3_severity", "UNSPECIFIED").upper()


def count_by_severity(rules, want_fixable):
    """Count CVEs per severity bucket (critical/high only), filtered by fixability."""
    counts = {severity: 0 for severity in SEVERITIES_OF_INTEREST}
    for rule in rules:
        severity = severity_of(rule)
        if severity in counts and is_fixable(rule) == want_fixable:
            counts[severity] += 1
    return counts


def determine_verdict(previous_rules, current_rules):
    current_fixable = count_by_severity(current_rules, want_fixable=True)
    total_fixable = sum(current_fixable.values())
    if total_fixable > 0:
        print(f"Cron rebuild introduced {total_fixable} fixable CVE(s): "
              f"{current_fixable}. This should not happen on an unmodified rebuild; "
              f"investigate before releasing.")
        return Verdict.FIXABLE_CVE_INTRODUCED

    previous_unfixable = count_by_severity(previous_rules, want_fixable=False)
    current_unfixable = count_by_severity(current_rules, want_fixable=False)

    for severity in SEVERITIES_OF_INTEREST:
        print(f"{severity}: {previous_unfixable[severity]} -> {current_unfixable[severity]}")

    critical_before = previous_unfixable["CRITICAL"]
    critical_after = current_unfixable["CRITICAL"]
    high_before = previous_unfixable["HIGH"]
    high_after = current_unfixable["HIGH"]

    # CRITICAL's movement takes strict priority: a fixed CRITICAL is always
    # worth releasing (even alongside a new HIGH), and a newly-appeared
    # CRITICAL always blocks a release (even alongside a fixed HIGH). HIGH
    # only gets to decide the verdict on its own when CRITICAL didn't move.
    if critical_after > critical_before:
        print("A non-fixable CRITICAL count increased -- this alone blocks any "
              "release, regardless of what HIGH did.")
        return Verdict.REGRESSION_ONLY

    if critical_after < critical_before:
        if high_after > high_before:
            print("A non-fixable CRITICAL count decreased, but a non-fixable "
                  "HIGH count increased. Releasing the CRITICAL fix, but "
                  "flagging the HIGH regression.")
            return Verdict.RELEASE_WITH_REGRESSION
        print("A non-fixable CRITICAL count decreased, with no HIGH regression.")
        return Verdict.RELEASE_CLEAN

    # CRITICAL unchanged: HIGH decides the verdict on its own.
    if high_after < high_before:
        print("CRITICAL unchanged; a non-fixable HIGH count decreased.")
        return Verdict.RELEASE_CLEAN

    if high_after > high_before:
        print("CRITICAL unchanged; a non-fixable HIGH count increased.")
        return Verdict.REGRESSION_ONLY

    print("No change in critical/high non-fixable counts.")
    return Verdict.NO_RELEASE_CLEAN


def main():
    if len(sys.argv) != 3:
        print("Usage: compare_scout_reports.py <previous.sarif.json> <current.sarif.json>",
              file=sys.stderr)
        return 1

    previous_rules = load_rules(sys.argv[1])
    current_rules = load_rules(sys.argv[2])

    verdict = determine_verdict(previous_rules, current_rules)
    print(f"VERDICT={verdict.value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())