#!/bin/zsh
# Tags the next version and pushes the tag, which triggers the Release workflow.
#
#   scripts/release.sh patch        0.2.0 → 0.2.1
#   scripts/release.sh minor        0.2.1 → 0.3.0
#   scripts/release.sh major        0.3.0 → 1.0.0
#   scripts/release.sh 0.4.0-beta   an explicit version
#
# Options: -y (don't ask for confirmation), -n (show what would happen, change nothing).
set -euo pipefail
cd "${0:A:h}/.."

YES=0
DRY=0
BUMP=""
for arg in "$@"; do
  case $arg in
    -y) YES=1 ;;
    -n) DRY=1 ;;
    -*) echo "unknown option $arg"; exit 2 ;;
    *) BUMP=$arg ;;
  esac
done
[[ -n $BUMP ]] || { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

die() { echo "error: $*" >&2; exit 1; }

# Release only what's on origin/main, so the tag points at a pushed commit.
[[ "$(git branch --show-current)" == main ]] || die "switch to main first"
[[ -z "$(git status --porcelain)" ]] || die "working tree isn't clean"
git fetch -q --tags origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
  || die "main isn't in sync with origin/main (push or pull first)"

# Latest release tag by version order (not by date), ignoring the v prefix.
LAST=$(git tag -l 'v*' --sort=-v:refname | head -1)
LAST=${LAST#v}
BASE=${${LAST:-0.0.0}%%-*}   # drop any pre-release suffix
IFS=. read -r MAJOR MINOR PATCH <<< "$BASE"

case $BUMP in
  patch) NEXT="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  minor) NEXT="$MAJOR.$((MINOR + 1)).0" ;;
  major) NEXT="$((MAJOR + 1)).0.0" ;;
  *)
    [[ $BUMP =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([.-].+)?$ ]] || die "expected patch, minor, major or x.y.z, got '$BUMP'"
    NEXT=${BUMP#v}
    ;;
esac
TAG="v$NEXT"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "$TAG already exists"

if [[ -n $LAST ]]; then
  # Refuse to go backwards (pre-releases of the same base are fine).
  LOWEST=$(printf '%s\n' "${LAST%%-*}" "${NEXT%%-*}" | sort -V | head -1)
  [[ $LOWEST == "${LAST%%-*}" ]] || die "$NEXT is lower than the last release $LAST"
  COMMITS=$(git rev-list --count "v$LAST"..HEAD)
  echo "Last release:  v$LAST ($COMMITS commits since)"
else
  echo "Last release:  none"
fi
echo "Next release:  $TAG at $(git log -1 --format='%h %s')"

if (( DRY )); then
  echo "(dry run: nothing tagged)"
  exit 0
fi
if (( ! YES )); then
  [[ -t 0 ]] || die "not a terminal; pass -y to confirm"
  read -q "REPLY?Tag and push $TAG? [y/N] " || { echo; exit 1; }
  echo
fi

git tag -a "$TAG" -m "tingjian $NEXT"
git push -q origin "$TAG"
REPO=$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
echo "Pushed $TAG. The Release workflow is building it:"
echo "  https://github.com/$REPO/actions/workflows/release.yml"
echo "  https://github.com/$REPO/releases/tag/$TAG (once it finishes)"
