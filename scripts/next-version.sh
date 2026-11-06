#!/bin/zsh
# Prints the next release version and the last one, from the v* tags:
#
#   scripts/next-version.sh patch|minor|major|x.y.z   →   "0.2.1 0.2.0"
#
# The last version is "-" when there are no releases yet. It fails if the
# result already exists or would be lower than the last release. Used by
# release.sh and the Release workflow.
set -euo pipefail
die() { echo "error: $*" >&2; exit 1; }

BUMP=${1:?usage: next-version.sh patch|minor|major|x.y.z}

# Latest release by version order (not by date). versionsort.suffix makes
# 0.3.0-beta sort before 0.3.0.
LAST=$(git -c versionsort.suffix=- tag -l 'v*' --sort=-v:refname | head -1)
LAST=${LAST#v}
BASE=${${LAST:-0.0.0}%%-*}   # drop any pre-release suffix
IFS=. read -r MAJOR MINOR PATCH <<< "$BASE"

case $BUMP in
  patch)
    # After a pre-release (0.3.0-beta), "patch" ships it as 0.3.0.
    if [[ $LAST == *-* ]]; then NEXT=$BASE; else NEXT="$MAJOR.$MINOR.$((PATCH + 1))"; fi ;;
  minor) NEXT="$MAJOR.$((MINOR + 1)).0" ;;
  major) NEXT="$((MAJOR + 1)).0.0" ;;
  *)
    [[ $BUMP =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([.-].+)?$ ]] || die "expected patch, minor, major or x.y.z, got '$BUMP'"
    NEXT=${BUMP#v}
    ;;
esac

git rev-parse -q --verify "refs/tags/v$NEXT" >/dev/null && die "v$NEXT already exists"
if [[ -n $LAST ]]; then
  LOWEST=$(printf '%s\n' "${LAST%%-*}" "${NEXT%%-*}" | sort -V | head -1)
  [[ $LOWEST == "${LAST%%-*}" ]] || die "$NEXT is lower than the last release $LAST"
fi
echo "$NEXT ${LAST:--}"
