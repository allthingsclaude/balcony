#!/bin/bash

# Usage: ./Scripts/release.sh <version|keyword>
# Examples:
#   ./Scripts/release.sh 0.2.0
#   ./Scripts/release.sh patch
#   ./Scripts/release.sh minor
#   ./Scripts/release.sh major

set -e

if [ -z "$1" ]; then
  echo "Usage: ./Scripts/release.sh <version|keyword>"
  echo ""
  echo "Version: X.Y.Z (e.g., 0.2.0)"
  echo ""
  echo "Keywords:"
  echo "  major  - Bump major version (X.0.0)"
  echo "  minor  - Bump minor version (x.Y.0)"
  echo "  patch  - Bump patch version (x.y.Z)"
  exit 1
fi

INPUT="$1"
MAC_PLIST="BalconyMac/Resources/Info.plist"
IOS_PLIST="BalconyiOS/Resources/Info.plist"

# Get current version from macOS Info.plist
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$MAC_PLIST" 2>/dev/null)

if [ -z "$CURRENT_VERSION" ]; then
  echo "Error: Could not read current version from $MAC_PLIST"
  exit 1
fi

# Parse current version components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Check if input is a keyword or explicit version
case "$INPUT" in
  major)
    VERSION="$((MAJOR + 1)).0.0"
    echo "Bumping major: $CURRENT_VERSION -> $VERSION"
    ;;
  minor)
    VERSION="$MAJOR.$((MINOR + 1)).0"
    echo "Bumping minor: $CURRENT_VERSION -> $VERSION"
    ;;
  patch)
    VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
    echo "Bumping patch: $CURRENT_VERSION -> $VERSION"
    ;;
  *)
    VERSION="$INPUT"
    # Validate version format (semver without v prefix)
    if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "Error: Version must be in format X.Y.Z (e.g., 0.2.0) or a keyword (major/minor/patch)"
      exit 1
    fi
    echo "Setting version: $CURRENT_VERSION -> $VERSION"
    ;;
esac

echo ""
echo "Bumping version to $VERSION..."
echo ""

# Update macOS Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$MAC_PLIST"
echo "  Updated $MAC_PLIST"

# Update iOS Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$IOS_PLIST"
echo "  Updated $IOS_PLIST"

echo ""

# Commit the changes
git add "$MAC_PLIST" "$IOS_PLIST"
git commit -m "chore: bump version to $VERSION"
echo "  Committed version bump"

# Create the tag (but don't push it yet)
git tag "v$VERSION"
echo "  Created tag v$VERSION"

# Push commit to main
git push
echo "  Pushed commit to origin"

# Wait for CI to pass before pushing the tag
echo ""
echo "Waiting for CI to pass..."
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
COMMIT_SHA=$(git rev-parse HEAD)

# Poll until CI completes
while true; do
  STATUS=$(gh api "repos/$REPO/commits/$COMMIT_SHA/check-runs" \
    --jq '.check_runs[] | select(.name == "build-and-test") | .status + ":" + .conclusion' 2>/dev/null || echo "pending:")

  case "$STATUS" in
    completed:success)
      echo "  CI passed!"
      break
      ;;
    completed:*)
      CONCLUSION="${STATUS#completed:}"
      echo "  CI failed ($CONCLUSION). Aborting release."
      git tag -d "v$VERSION"
      exit 1
      ;;
    *)
      printf "."
      sleep 10
      ;;
  esac
done

# Now push the tag to trigger release workflows
git push origin "v$VERSION"
echo "  Pushed tag v$VERSION to origin"

echo ""
echo "Done! Version bumped to $VERSION"
echo "The release workflows will now build, sign, and publish v$VERSION."
