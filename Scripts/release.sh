#!/bin/bash
# ============================================================
#  EVEOps — Local Release Script
#  Usage: ./Scripts/release.sh 1.0.0
# ============================================================

set -e

# ── Config ───────────────────────────────────────────────────
SCHEME="EVEOps"
PROJECT="EVEOps.xcodeproj"
BUNDLE_ID="CitizenCoder.EVEOps"
GITHUB_REPO="MikeManzo/EVEOps"
RELEASE_BRANCH="main"
SPARKLE_BIN="./bin"

# ── Credentials (loaded from .env + Keychain) ───────────────
ENV_FILE="$(dirname "$0")/../.env"
if [ ! -f "$ENV_FILE" ]; then
  error "Missing .env file at project root. Copy env.example to .env and fill in your credentials."
fi
source "$ENV_FILE"

# Validate .env vars
[ -z "$APPLE_ID" ] && error "APPLE_ID is not set in .env"
[ -z "$TEAM_ID" ]  && error "TEAM_ID is not set in .env"
[ "$APPLE_ID" = "your@email.com" ] && error "APPLE_ID is still the placeholder value in .env"

# Notarization uses a stored keychain profile (Apple's recommended approach).
# Set it up once with:
#   xcrun notarytool store-credentials "EVEOpsRelease" \
#     --apple-id "$APPLE_ID" --team-id "$TEAM_ID"
# (It will prompt for your app-specific password and save everything securely.)
NOTARY_PROFILE="EVEOpsRelease"

# Verify the profile exists
xcrun notarytool info --keychain-profile "$NOTARY_PROFILE" 2>&1 | grep -q "error" && \
  error "Notarization keychain profile '$NOTARY_PROFILE' not found. Run this once to set it up:
  xcrun notarytool store-credentials \"EVEOpsRelease\" --apple-id \"$APPLE_ID\" --team-id \"$TEAM_ID\""

# ── Paths ────────────────────────────────────────────────────
WORK_DIR=~/Desktop/EVEOpsRelease
ARCHIVE_PATH="$WORK_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$WORK_DIR/export"
APP_PATH="$EXPORT_PATH/$SCHEME.app"
DMG_PATH="$WORK_DIR/$SCHEME.dmg"
NOTARIZE_ZIP="$WORK_DIR/$SCHEME-notarize.zip"
APPCAST_DIR="$WORK_DIR/appcast"
SPARKLE_KEY="$WORK_DIR/sparkle_ed_key"

# ── Helpers ──────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}==>${NC} $1"; }
warning() { echo -e "${YELLOW}Warning:${NC} $1"; }
error()   { echo -e "${RED}Error:${NC} $1"; exit 1; }

# ── Validate version argument ────────────────────────────────
VERSION=$1
if [ -z "$VERSION" ]; then
  error "No version specified. Usage: ./Scripts/release.sh 1.0.0"
fi

TAG="v$VERSION"
DOWNLOAD_URL_PREFIX="https://github.com/$GITHUB_REPO/releases/download/$TAG/"

# ── Check current branch ─────────────────────────────────────
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]; then
  echo ""
  warning "You are on branch '$CURRENT_BRANCH', not '$RELEASE_BRANCH'."
  read -p "Continue releasing from '$CURRENT_BRANCH'? (y/n) " -n 1 -r
  echo ""
  [[ $REPLY =~ ^[Yy]$ ]] || exit 0
fi

# ── Check dependencies ───────────────────────────────────────
info "Checking dependencies..."
command -v gh >/dev/null 2>&1       || error "GitHub CLI not found. Run: brew install gh"
command -v xcpretty >/dev/null 2>&1 || warning "xcpretty not found. Run: sudo gem install xcpretty"
[ -f "$SPARKLE_BIN/generate_keys" ] || error "Sparkle bin not found at $SPARKLE_BIN. Are you running from your project root?"

# ── Confirm before proceeding ────────────────────────────────
echo ""
echo -e "${YELLOW}About to release:${NC}"
echo "  Version : $TAG"
echo "  Repo    : $GITHUB_REPO"
echo "  Bundle  : $BUNDLE_ID"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
[[ $REPLY =~ ^[Yy]$ ]] || exit 0

# ── Auto-increment build number ─────────────────────────────
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PROJECT/project.pbxproj" | sed 's/[^0-9]//g')
NEW_BUILD=$((CURRENT_BUILD + 1))
info "Bumping build number: $CURRENT_BUILD → $NEW_BUILD"
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $NEW_BUILD/" "$PROJECT/project.pbxproj"

# ── Set marketing version ───────────────────────────────────
info "Setting MARKETING_VERSION = $VERSION"
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $VERSION/" "$PROJECT/project.pbxproj"

# ── Prepare work directory ───────────────────────────────────
info "Preparing work directory..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$APPCAST_DIR"

# ── Archive ──────────────────────────────────────────────────
info "Archiving $SCHEME..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "generic/platform=macOS" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  | xcpretty

[ -d "$ARCHIVE_PATH" ] || error "Archive failed — .xcarchive not found"
info "Archive succeeded ✓"

# ── Export ───────────────────────────────────────────────────
info "Exporting archive..."
cat > "$WORK_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$WORK_DIR/ExportOptions.plist"

[ -d "$APP_PATH" ] || error "Export failed — .app not found"
info "Export succeeded ✓"

# ── Notarize ─────────────────────────────────────────────────
info "Notarizing app (this may take a few minutes)..."
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

xcrun notarytool submit "$NOTARIZE_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

info "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
info "Notarization succeeded ✓"

# ── Create DMG ───────────────────────────────────────────────
info "Creating DMG..."
hdiutil create \
  -volname "$SCHEME" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  "$DMG_PATH"

[ -f "$DMG_PATH" ] || error "DMG creation failed"
info "DMG created ✓"

# ── Generate Appcast ─────────────────────────────────────────
info "Generating appcast..."
"$SPARKLE_BIN/generate_keys" -x "$SPARKLE_KEY"
chmod 600 "$SPARKLE_KEY"

cp "$DMG_PATH" "$APPCAST_DIR/"

"$SPARKLE_BIN/generate_appcast" \
  --ed-key-file "$SPARKLE_KEY" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  "$APPCAST_DIR/"

rm "$SPARKLE_KEY"
[ -f "$APPCAST_DIR/appcast.xml" ] || error "Appcast generation failed"
info "Appcast generated ✓"

# ── Commit Appcast to main branch ────────────────────────────
info "Committing appcast.xml to $RELEASE_BRANCH..."
CURRENT_BRANCH=$(git branch --show-current)
cp "$APPCAST_DIR/appcast.xml" ./appcast.xml

if [ "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]; then
  git stash --include-untracked -q 2>/dev/null
  git checkout "$RELEASE_BRANCH"
  git pull origin "$RELEASE_BRANCH" --ff-only
  cp "$APPCAST_DIR/appcast.xml" ./appcast.xml
fi

git add appcast.xml
if git diff --cached --quiet; then
  info "No changes to appcast.xml, skipping commit"
else
  git commit -m "Update appcast for $TAG"
  git push origin "$RELEASE_BRANCH"
  info "Appcast committed to $RELEASE_BRANCH ✓"
fi

if [ "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]; then
  git checkout "$CURRENT_BRANCH"
  git stash pop -q 2>/dev/null || true
  cp "$APPCAST_DIR/appcast.xml" ./appcast.xml
  git add appcast.xml
  git diff --cached --quiet || git commit -m "Update appcast for $TAG"
fi

# ── Tag & Push ───────────────────────────────────────────────
info "Tagging release $TAG..."
git tag "$TAG"
git push origin "$TAG"

# ── Publish GitHub Release ───────────────────────────────────
info "Publishing GitHub Release..."
gh release create "$TAG" \
  "$DMG_PATH" \
  "$APPCAST_DIR/appcast.xml" \
  --title "$TAG" \
  --notes "Release $TAG"

info "Release $TAG published successfully ✓"

# ── Cleanup ──────────────────────────────────────────────────
info "Cleaning up..."
rm -rf "$WORK_DIR"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  $SCHEME $TAG released successfully!${NC}"
echo -e "${GREEN}  DMG + appcast.xml uploaded to GitHub     ${NC}"
echo -e "${GREEN}  Sparkle will detect the update           ${NC}"
echo -e "${GREEN}============================================${NC}"
