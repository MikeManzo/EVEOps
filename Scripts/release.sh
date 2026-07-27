#!/bin/bash
# ============================================================
#  EVEOps — Local Release Script
#  Usage: ./Scripts/release.sh 1.0.0
# ============================================================

set -eo pipefail

# ── Helpers ──────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}==>${NC} $1"; }
warning() { echo -e "${YELLOW}Warning:${NC} $1"; }
error()   { echo -e "${RED}Error:${NC} $1"; exit 1; }

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
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > /dev/null 2>&1 || \
  error "Notarization keychain profile '$NOTARY_PROFILE' not found. Run this once to set it up:
  xcrun notarytool store-credentials \"EVEOpsRelease\" --apple-id \"$APPLE_ID\" --team-id \"$TEAM_ID\""

# ── Paths ────────────────────────────────────────────────────
WORK_DIR=~/Desktop/EVEOpsRelease
ARCHIVE_PATH="$WORK_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$WORK_DIR/export"
APP_PATH="$EXPORT_PATH/$SCHEME.app"
DMG_PATH="$WORK_DIR/$SCHEME.dmg"
APPCAST_DIR="$WORK_DIR/appcast"

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

# ── Draft release notes ──────────────────────────────────────
# Done early (before the long archive/notarize pipeline) so an aborted or
# empty edit fails fast. Drafted from commits since the last tag, then handed
# to $EDITOR for review — the same content later drives both the Sparkle
# appcast item and the GitHub release body.
info "Drafting release notes..."
PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
NOTES_DRAFT=$(mktemp "${TMPDIR:-/tmp}/eveops-notes-XXXXXX.md")

if [ -n "$PREV_TAG" ]; then
  git log "$PREV_TAG"..HEAD --pretty=format:"- %s" | grep -v "^- Update appcast" > "$NOTES_DRAFT" || true
else
  echo "- Initial release" > "$NOTES_DRAFT"
fi

"${EDITOR:-nano}" "$NOTES_DRAFT"

[ -s "$NOTES_DRAFT" ] || error "Release notes are empty — aborting release."
info "Release notes finalized ✓"

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

# Retries xcrun stapler staple up to 5 times with 30s back-off.
# Apple's CDN can take up to ~60s to propagate a ticket after notarytool
# reports success, so a bare `stapler staple` often hits "Record not found".
staple_with_retry() {
  local target="$1"
  local attempts=5
  for i in $(seq 1 $attempts); do
    xcrun stapler staple "$target" && return 0
    [ $i -lt $attempts ] && { warning "Staple attempt $i failed — retrying in 30s..."; sleep 30; }
  done
  error "Stapling failed after $attempts attempts for $target"
}

# Submits a file for notarization and polls until Apple accepts or rejects it.
#
# Both `--wait` and `--output-format json` crash with SIGBUS in some Xcode
# builds — the former in the polling thread, the latter before the connection
# even opens. Use plain-text output (the default) piped through `tee` so the
# user sees progress, then parse the "id: <uuid>" line with grep/awk.
notarize_and_wait() {
  local target="$1"
  local label="$2"

  local out_tmp
  out_tmp=$(mktemp)

  info "Submitting $label for notarization..."
  # tee lets us show live output AND capture it. Without --wait or --output-format,
  # notarytool prints the submission ID and exits immediately after upload.
  #
  # notarytool crashes with SIGBUS in its own exit handler on some Xcode builds,
  # even after the submission completes successfully. `|| true` absorbs that
  # pipeline failure; the ID check below still catches genuine failures where
  # no submission ID was ever printed.
  xcrun notarytool submit "$target" \
    --keychain-profile "$NOTARY_PROFILE" \
    | tee "$out_tmp" || true

  # Text format: "  id: <uuid>" indented under "Submission ID received"
  local sub_id
  sub_id=$(grep -E "^\s+id:" "$out_tmp" | awk '{print $2}' | head -1)
  rm -f "$out_tmp"
  [ -n "$sub_id" ] || error "Failed to parse submission ID from notarytool output above"

  info "Waiting for notarization (ID: $sub_id)..."
  local info_tmp
  while true; do
    info_tmp=$(mktemp)
    # `notarytool info` doesn't poll — it just queries once and exits cleanly.
    xcrun notarytool info "$sub_id" \
      --keychain-profile "$NOTARY_PROFILE" \
      | tee "$info_tmp"
    local status
    # Text format: "  status: Accepted"
    status=$(grep -E "^\s+status:" "$info_tmp" | awk '{print $2}' | head -1)
    rm -f "$info_tmp"
    case "$status" in
      Accepted)
        info "$label notarized ✓"
        return 0
        ;;
      Invalid|Rejected)
        error "Notarization $status. Fetch the log with: xcrun notarytool log $sub_id --keychain-profile $NOTARY_PROFILE"
        ;;
      *)
        info "  Status: ${status:-unknown} — checking again in 30s..."
        sleep 30
        ;;
    esac
  done
}

# ── Notarize .app bundle so it carries a stapled ticket ──────
# Stapling the ticket directly to the .app means Gatekeeper can verify
# the binary offline after the user drags it from the DMG. Without this,
# users who are offline or behind strict firewalls get a "cannot verify"
# block on first launch because Gatekeeper must phone home.
NOTARIZE_ZIP="$WORK_DIR/$SCHEME-notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
notarize_and_wait "$NOTARIZE_ZIP" "app bundle"
info "Stapling notarization ticket to app bundle..."
staple_with_retry "$APP_PATH"

# ── Create DMG (with already-stapled .app inside) ────────────
info "Creating DMG..."
hdiutil create \
  -volname "$SCHEME" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  "$DMG_PATH"

[ -f "$DMG_PATH" ] || error "DMG creation failed"
info "DMG created ✓"

# ── Notarize DMG ─────────────────────────────────────────────
notarize_and_wait "$DMG_PATH" "DMG"
info "Stapling notarization ticket to DMG..."
staple_with_retry "$DMG_PATH"
info "DMG notarized ✓"

# ── Generate Appcast ─────────────────────────────────────────
# generate_appcast reads the private key from the macOS Keychain automatically
# (the key that matches SUPublicEDKey in Info.plist, stored there by the one-time
# `generate_keys` setup). Never call `generate_keys` here — that would create a
# new key pair and invalidate the public key embedded in all previously shipped builds.
info "Generating appcast..."

# generate_appcast picks up release notes automatically from an .html/.txt file
# that shares the archive's base filename — write ours before the DMG lands
# next to it. No DOCTYPE/body tags means it's embedded inline as CDATA rather
# than treated as a standalone linked page.
NOTES_HTML="$APPCAST_DIR/$SCHEME.html"
python3 -c '
import html, sys
lines = open(sys.argv[1]).read().splitlines()
out, in_list = [], False
for line in lines:
    line = line.strip()
    if line.startswith("- "):
        if not in_list:
            out.append("<ul>")
            in_list = True
        out.append(f"<li>{html.escape(line[2:])}</li>")
    else:
        if in_list:
            out.append("</ul>")
            in_list = False
        if line:
            out.append(f"<p>{html.escape(line)}</p>")
if in_list:
    out.append("</ul>")
open(sys.argv[2], "w").write("\n".join(out))
' "$NOTES_DRAFT" "$NOTES_HTML"

cp "$DMG_PATH" "$APPCAST_DIR/"

"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  "$APPCAST_DIR/"

[ -f "$APPCAST_DIR/appcast.xml" ] || error "Appcast generation failed"
info "Appcast generated ✓"

# ── Commit Appcast + Release Notes to main branch ────────────
info "Committing appcast.xml and release notes to $RELEASE_BRANCH..."
CURRENT_BRANCH=$(git branch --show-current)
NOTES_REPO_PATH="Scripts/releasenotes/$VERSION.md"
mkdir -p "$(dirname "$NOTES_REPO_PATH")"
cp "$APPCAST_DIR/appcast.xml" ./appcast.xml
cp "$NOTES_DRAFT" "$NOTES_REPO_PATH"

if [ "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]; then
  git stash --include-untracked -q 2>/dev/null
  git checkout "$RELEASE_BRANCH"
  git pull origin "$RELEASE_BRANCH" --ff-only
  mkdir -p "$(dirname "$NOTES_REPO_PATH")"
  cp "$APPCAST_DIR/appcast.xml" ./appcast.xml
  cp "$NOTES_DRAFT" "$NOTES_REPO_PATH"
fi

git add appcast.xml "$NOTES_REPO_PATH"
if git diff --cached --quiet; then
  info "No changes to appcast.xml or release notes, skipping commit"
else
  git commit -m "Update appcast for $TAG"
  git push origin "$RELEASE_BRANCH"
  info "Appcast and release notes committed to $RELEASE_BRANCH ✓"
fi

if [ "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]; then
  git checkout "$CURRENT_BRANCH"
  git stash pop -q 2>/dev/null || true
  cp "$APPCAST_DIR/appcast.xml" ./appcast.xml
  cp "$NOTES_DRAFT" "$NOTES_REPO_PATH"
  git add appcast.xml "$NOTES_REPO_PATH"
  git diff --cached --quiet || git commit -m "Update appcast for $TAG"
fi

# ── Tag & Push ───────────────────────────────────────────────
info "Tagging release $TAG..."
if git rev-parse "$TAG" >/dev/null 2>&1; then
  info "Tag $TAG already exists locally — skipping"
else
  git tag "$TAG"
fi
if git ls-remote --tags origin "$TAG" | grep -q "$TAG"; then
  info "Tag $TAG already exists on remote — skipping push"
else
  git push origin "$TAG"
fi

# ── Publish GitHub Release ───────────────────────────────────
info "Publishing GitHub Release..."

# Create the release without assets first so a failed upload doesn't
# leave a half-created release that can't be retried.
if gh release view "$TAG" &>/dev/null; then
  info "GitHub release $TAG already exists — uploading missing assets..."
else
  gh release create "$TAG" \
    --title "$TAG" \
    --notes-file "$NOTES_DRAFT"
fi

# Upload each asset with retry logic — large DMGs over a flaky
# connection can hit transient TLS errors (bad record MAC) mid-stream.
upload_asset() {
  local file="$1"
  local label="$(basename "$file")"
  local attempts=5
  local delay=15
  for i in $(seq 1 $attempts); do
    info "Uploading $label (attempt $i/$attempts)..."
    if gh release upload "$TAG" "$file" --clobber; then
      info "$label uploaded ✓"
      return 0
    fi
    if [ "$i" -lt "$attempts" ]; then
      info "Upload failed — retrying in ${delay}s..."
      sleep "$delay"
      delay=$((delay * 2))
    fi
  done
  error "Upload of $label failed after $attempts attempts"
}

upload_asset "$DMG_PATH"
upload_asset "$APPCAST_DIR/appcast.xml"

info "Release $TAG published successfully ✓"

# ── Cleanup ──────────────────────────────────────────────────
info "Cleaning up..."
rm -rf "$WORK_DIR"
rm -f "$NOTES_DRAFT"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  $SCHEME $TAG released successfully!${NC}"
echo -e "${GREEN}  DMG + appcast.xml uploaded to GitHub     ${NC}"
echo -e "${GREEN}  Sparkle will detect the update           ${NC}"
echo -e "${GREEN}============================================${NC}"
