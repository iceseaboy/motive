#!/bin/bash
set -e

# Build Release Script for Motive
# Creates separate DMGs for arm64 (Apple Silicon) and x86_64 (Intel)
#
# Usage:
#   ./build-release.sh                              # Build with current version
#   ./build-release.sh patch                        # Bump patch version (0.1.0 → 0.1.1)
#   ./build-release.sh minor                        # Bump minor version (0.1.0 → 0.2.0)
#   ./build-release.sh major                        # Bump major version (0.1.0 → 1.0.0)
#   ./build-release.sh --notarize                   # Build and notarize
#   ./build-release.sh --with-cloudkit              # Build with CloudKit/Push Notifications enabled
#   ./build-release.sh --arm64-only                 # Build only for Apple Silicon
#   ./build-release.sh --x86-only                   # Build only for Intel
#
# Environment Variables (can be set in shell profile or .env file):
#   APPLE_ID          - Apple ID email for notarization
#   TEAM_ID           - Team ID (e.g., XAA75S2V8H)
#   APP_PASSWORD      - App-specific password for notarization
#   MOTIVE_NOTARIZE   - Set to "1" to enable notarization by default
#   MOTIVE_CLOUDKIT   - Set to "1" to enable CloudKit by default

APP_NAME="Motive"
SCHEME="Motive"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
RELEASE_DIR="$PROJECT_DIR/release"
PBXPROJ="$PROJECT_DIR/$APP_NAME.xcodeproj/project.pbxproj"

# OpenCode release URLs (from anomalyco/opencode - the correct repo)
OPENCODE_ARM64_URL="https://github.com/anomalyco/opencode/releases/latest/download/opencode-darwin-arm64.zip"
OPENCODE_X64_URL="https://github.com/anomalyco/opencode/releases/latest/download/opencode-darwin-x64.zip"

# Settings from environment variables (with defaults)
NOTARIZE="${MOTIVE_NOTARIZE:-}"
WITH_CLOUDKIT="${MOTIVE_CLOUDKIT:-}"
APPLE_ID="${APPLE_ID:-}"
TEAM_ID="${TEAM_ID:-}"
APP_PASSWORD="${APP_PASSWORD:-}"

# Build targets (default: both architectures)
BUILD_ARM64="1"
BUILD_X86="1"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[BUILD]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
config() { echo -e "${CYAN}[CONFIG]${NC} $1"; }

# Parse command line arguments
parse_args() {
    BUMP_TYPE=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --notarize|-n)
                NOTARIZE="1"
                shift
                ;;
            --with-cloudkit|--cloudkit)
                WITH_CLOUDKIT="1"
                shift
                ;;
            --arm64-only)
                BUILD_ARM64="1"
                BUILD_X86=""
                shift
                ;;
            --x86-only|--intel-only)
                BUILD_ARM64=""
                BUILD_X86="1"
                shift
                ;;
            --apple-id)
                APPLE_ID="$2"
                shift 2
                ;;
            --team-id)
                TEAM_ID="$2"
                shift 2
                ;;
            --app-password)
                APP_PASSWORD="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            patch|minor|major)
                BUMP_TYPE="$1"
                shift
                ;;
            *)
                error "Unknown option: $1 (use --help for usage)"
                ;;
        esac
    done
}

show_help() {
    echo "Usage: $0 [patch|minor|major] [OPTIONS]"
    echo ""
    echo "Version bump:"
    echo "  patch                     Bump patch version (0.1.0 → 0.1.1)"
    echo "  minor                     Bump minor version (0.1.0 → 0.2.0)"
    echo "  major                     Bump major version (0.1.0 → 1.0.0)"
    echo ""
    echo "Build options:"
    echo "  --with-cloudkit           Include CloudKit & Push Notifications (requires provisioning profile)"
    echo "  --arm64-only              Build only for Apple Silicon"
    echo "  --x86-only, --intel-only  Build only for Intel"
    echo ""
    echo "Notarization options:"
    echo "  --notarize, -n            Enable notarization"
    echo "  --apple-id EMAIL          Apple ID for notarization"
    echo "  --team-id TEAM            Team ID (e.g., XAA75S2V8H)"
    echo "  --app-password PASSWORD   App-specific password"
    echo ""
    echo "Environment variables (set these to avoid prompts):"
    echo "  APPLE_ID                  Apple ID email"
    echo "  TEAM_ID                   Team ID"
    echo "  APP_PASSWORD              App-specific password"
    echo "  MOTIVE_NOTARIZE=1         Enable notarization by default"
    echo "  MOTIVE_CLOUDKIT=1         Enable CloudKit by default"
    echo ""
    echo "Examples:"
    echo "  $0                                    Build without notarization"
    echo "  $0 patch --notarize                   Bump patch and notarize"
    echo "  $0 --notarize --with-cloudkit         Build with CloudKit and notarize"
    echo "  $0 --arm64-only --notarize            Build only arm64 and notarize"
    echo ""
    echo "Tip: Add to ~/.zshrc or ~/.bashrc for persistent config:"
    echo "  export APPLE_ID='your@email.com'"
    echo "  export TEAM_ID='XAA75S2V8H'"
    echo "  export APP_PASSWORD='xxxx-xxxx-xxxx-xxxx'"
    echo "  export MOTIVE_NOTARIZE=1"
}

# Display current configuration
show_config() {
    echo ""
    config "Build Configuration:"
    config "  Notarization:  $([ "$NOTARIZE" = "1" ] && echo "✅ Enabled" || echo "❌ Disabled")"
    config "  CloudKit:      $([ "$WITH_CLOUDKIT" = "1" ] && echo "✅ Enabled" || echo "❌ Disabled")"
    config "  Architectures: $([ "$BUILD_ARM64" = "1" ] && echo "arm64 ")$([ "$BUILD_X86" = "1" ] && echo "x86_64")"
    if [ "$NOTARIZE" = "1" ]; then
        config "  Apple ID:      $([ -n "$APPLE_ID" ] && echo "${APPLE_ID}" || echo "(will prompt)")"
        config "  Team ID:       $([ -n "$TEAM_ID" ] && echo "${TEAM_ID}" || echo "(will prompt)")"
        config "  App Password:  $([ -n "$APP_PASSWORD" ] && echo "********" || echo "(will prompt)")"
    fi
    echo ""
}

# Prompt for notarization credentials if needed
prompt_notarization_credentials() {
    if [ "$NOTARIZE" != "1" ]; then
        return
    fi
    
    if [ -z "$APPLE_ID" ]; then
        read -p "Apple ID (email): " APPLE_ID
    fi
    
    if [ -z "$TEAM_ID" ]; then
        # Try to get from Developer ID certificate
        local detected_team=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*(\([A-Z0-9]*\)).*/\1/')
        if [ -n "$detected_team" ]; then
            info "Detected Team ID: $detected_team"
            read -p "Team ID [$detected_team]: " input_team
            TEAM_ID="${input_team:-$detected_team}"
        else
            read -p "Team ID: " TEAM_ID
        fi
    fi
    
    if [ -z "$APP_PASSWORD" ]; then
        echo "Get app-specific password from: https://appleid.apple.com → Sign-In and Security → App-Specific Passwords"
        read -sp "App-specific password: " APP_PASSWORD
        echo ""
    fi
    
    if [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ] || [ -z "$APP_PASSWORD" ]; then
        error "All credentials are required for notarization"
    fi
}

# Get entitlements path based on CloudKit setting
get_entitlements_path() {
    if [ "$WITH_CLOUDKIT" = "1" ]; then
        echo "$PROJECT_DIR/$APP_NAME/Entitlements/MotiveReleaseCloudKit.entitlements"
    else
        echo "$PROJECT_DIR/$APP_NAME/Entitlements/MotiveRelease.entitlements"
    fi
}

# Clean previous builds
clean() {
    log "Cleaning previous builds..."
    rm -rf "$BUILD_DIR"
    rm -rf "$RELEASE_DIR"
    mkdir -p "$BUILD_DIR"
    mkdir -p "$RELEASE_DIR"
}

# Download OpenCode binary for specific architecture
download_opencode() {
    local arch=$1
    local url=$2
    local zipfile="$BUILD_DIR/opencode-$arch.zip"
    local dest="$BUILD_DIR/opencode-$arch"
    
    log "Downloading OpenCode for $arch..."
    curl -L -f "$url" -o "$zipfile" || error "Failed to download OpenCode for $arch"
    
    log "Extracting OpenCode for $arch..."
    unzip -o "$zipfile" -d "$BUILD_DIR"
    mv "$BUILD_DIR/opencode" "$dest"
    rm "$zipfile"
    
    chmod +x "$dest"
    log "Downloaded and extracted OpenCode for $arch"
}

# Build app for specific architecture
build_app() {
    local arch=$1
    local build_path="$BUILD_DIR/$arch"
    
    log "Building $APP_NAME for $arch..."
    
    xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration Release \
        -arch "$arch" \
        -derivedDataPath "$build_path" \
        ONLY_ACTIVE_ARCH=NO \
        MACOSX_DEPLOYMENT_TARGET=15.0 \
        clean build
    
    log "Build complete for $arch"
}

# Copy OpenCode binary into app bundle
inject_opencode() {
    local arch=$1
    local build_path="$BUILD_DIR/$arch"
    local app_path="$build_path/Build/Products/Release/$APP_NAME.app"
    local resources_path="$app_path/Contents/Resources"
    local opencode_src="$BUILD_DIR/opencode-$arch"
    
    log "Injecting OpenCode binary into $arch app bundle..."
    
    if [ ! -d "$app_path" ]; then
        error "App not found at $app_path"
    fi
    
    mkdir -p "$resources_path"
    cp "$opencode_src" "$resources_path/opencode"
    chmod +x "$resources_path/opencode"
    
    # Sign the binary
    log "Signing OpenCode binary..."
    codesign --remove-signature "$resources_path/opencode" 2>/dev/null || true
    codesign --force --sign - "$resources_path/opencode"
    
    log "OpenCode injected for $arch"
}

# Re-sign the entire app bundle
sign_app() {
    local arch=$1
    local build_path="$BUILD_DIR/$arch"
    local app_path="$build_path/Build/Products/Release/$APP_NAME.app"
    local entitlements_path=$(get_entitlements_path)
    
    log "Signing app bundle for $arch..."
    log "Using entitlements: $(basename "$entitlements_path")"
    
    # Check if Developer ID is available
    local signing_identity=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')
    
    if [ -n "$signing_identity" ]; then
        log "Signing with Developer ID: $signing_identity"
        
        # Sign all embedded binaries first (inside-out signing)
        local resources_path="$app_path/Contents/Resources"
        
        # Sign OpenCode binary
        local opencode_path="$resources_path/opencode"
        if [ -f "$opencode_path" ]; then
            log "Signing OpenCode binary..."
            codesign --force --options runtime --timestamp \
                --sign "$signing_identity" "$opencode_path"
        fi
        
        # Sign browser-use-sidecar (Python bundle)
        # CRITICAL: Must include entitlements with disable-library-validation
        # because PyInstaller extracts libpython3.12.dylib (signed by Python.org)
        # at runtime, and Hardened Runtime would reject the different Team ID.
        local sidecar_path="$resources_path/browser-use-sidecar"
        local sidecar_entitlements="$PROJECT_DIR/$APP_NAME/Entitlements/Sidecar.entitlements"
        if [ -d "$sidecar_path" ]; then
            log "Signing browser-use-sidecar (directory)..."
            # Sign all binaries inside the sidecar directory
            find "$sidecar_path" -type f -perm +111 | while read binary; do
                codesign --force --options runtime --timestamp \
                    --entitlements "$sidecar_entitlements" \
                    --sign "$signing_identity" "$binary" 2>/dev/null || true
            done
            # Sign .so and .dylib files
            find "$sidecar_path" -type f \( -name "*.so" -o -name "*.dylib" \) | while read lib; do
                codesign --force --options runtime --timestamp \
                    --entitlements "$sidecar_entitlements" \
                    --sign "$signing_identity" "$lib" 2>/dev/null || true
            done
            # Sign the main sidecar binary/directory
            codesign --force --options runtime --timestamp \
                --entitlements "$sidecar_entitlements" \
                --sign "$signing_identity" "$sidecar_path" 2>/dev/null || true
        elif [ -f "$sidecar_path" ]; then
            log "Signing browser-use-sidecar (single file)..."
            codesign --force --options runtime --timestamp \
                --entitlements "$sidecar_entitlements" \
                --sign "$signing_identity" "$sidecar_path"
        fi
        
        # Sign any other binaries in Resources
        find "$resources_path" -maxdepth 1 -type f -perm +111 ! -name "opencode" ! -name "browser-use-sidecar" | while read binary; do
            log "Signing $(basename "$binary")..."
            codesign --force --options runtime --timestamp \
                --sign "$signing_identity" "$binary" 2>/dev/null || true
        done
        
        # Sign the app bundle with entitlements
        log "Signing main app bundle..."
        codesign --force --deep --options runtime --timestamp \
            --entitlements "$entitlements_path" \
            --sign "$signing_identity" \
            "$app_path"
        
        log "App signed with Developer ID for $arch"
    else
        warn "No Developer ID found, using ad-hoc signature (distribution not possible)"
        codesign --force --deep --sign - "$app_path"
        log "App signed with ad-hoc signature for $arch"
    fi
}

# Notarize the app
notarize_app() {
    local arch=$1
    local build_path="$BUILD_DIR/$arch"
    local app_path="$build_path/Build/Products/Release/$APP_NAME.app"
    
    if [ "$NOTARIZE" != "1" ]; then
        info "Skipping notarization (use --notarize to enable)"
        return
    fi
    
    log "Creating ZIP for notarization..."
    local zip_path="$BUILD_DIR/$APP_NAME-$arch-notarize.zip"
    ditto -c -k --keepParent "$app_path" "$zip_path"
    
    log "Submitting to Apple for notarization (this may take a few minutes)..."
    local notarize_output
    notarize_output=$(xcrun notarytool submit "$zip_path" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait 2>&1)
    local notarize_status=$?
    
    echo "$notarize_output"
    
    # Check if notarization was accepted
    if echo "$notarize_output" | grep -q "status: Accepted"; then
        log "Notarization accepted! Stapling ticket..."
        
        # Try stapling with retries (Apple CDN may need time to sync)
        local staple_success=false
        for i in 1 2 3; do
            if xcrun stapler staple "$app_path" 2>/dev/null; then
                staple_success=true
                break
            fi
            if [ $i -lt 3 ]; then
                warn "Staple attempt $i failed, waiting 30 seconds..."
                sleep 30
            fi
        done
        
        if [ "$staple_success" = true ]; then
            log "Notarization and stapling complete for $arch"
        else
            warn "Stapling failed (notarization succeeded). Users will need internet for first launch."
            warn "You can manually staple later: xcrun stapler staple \"$app_path\""
        fi
    elif [ $notarize_status -eq 0 ]; then
        # Exit code 0 but not "Accepted" - check for Invalid
        if echo "$notarize_output" | grep -q "status: Invalid"; then
            error "Notarization rejected for $arch. Run: xcrun notarytool log <submission-id> --apple-id $APPLE_ID --team-id $TEAM_ID --password <password>"
        else
            warn "Notarization status unclear for $arch"
        fi
    else
        error "Notarization submission failed for $arch"
    fi
    
    rm -f "$zip_path"
}

# Create DMG
create_dmg() {
    local arch=$1
    local build_path="$BUILD_DIR/$arch"
    local app_path="$build_path/Build/Products/Release/$APP_NAME.app"
    local dmg_name="$APP_NAME-$arch.dmg"
    local dmg_path="$RELEASE_DIR/$dmg_name"
    local staging_dir="$BUILD_DIR/dmg-staging-$arch"
    
    log "Creating DMG for $arch..."
    
    # Create staging directory
    rm -rf "$staging_dir"
    mkdir -p "$staging_dir"
    
    # Copy app
    cp -R "$app_path" "$staging_dir/"
    
    # Create symbolic link to Applications
    ln -s /Applications "$staging_dir/Applications"
    
    # Create DMG
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$staging_dir" \
        -ov -format UDZO \
        "$dmg_path"
    
    # Clean up
    rm -rf "$staging_dir"
    
    log "DMG created: $dmg_path"
    
    # Notarize DMG if enabled
    if [ "$NOTARIZE" == "1" ]; then
        log "Submitting DMG for notarization..."
        xcrun notarytool submit "$dmg_path" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --password "$APP_PASSWORD" \
            --wait
        
        if [ $? -eq 0 ]; then
            xcrun stapler staple "$dmg_path"
            log "DMG notarization complete"
        else
            warn "DMG notarization failed (app still notarized)"
        fi
    fi
}

# Get current version from project.pbxproj
get_version() {
    local version=$(grep "MARKETING_VERSION" "$PBXPROJ" | head -1 | sed 's/.*= *\([^;]*\);/\1/' | tr -d ' ')
    echo "${version:-0.1.0}"
}

# Bump version based on type (patch/minor/major)
bump_version() {
    local current=$1
    local bump_type=$2
    
    # Parse version components
    local major=$(echo "$current" | cut -d. -f1)
    local minor=$(echo "$current" | cut -d. -f2)
    local patch=$(echo "$current" | cut -d. -f3)
    
    # Default to 0 if not present
    major=${major:-0}
    minor=${minor:-0}
    patch=${patch:-0}
    
    case $bump_type in
        patch)
            patch=$((patch + 1))
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        *)
            error "Invalid bump type: $bump_type (use: patch, minor, major)"
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Update version in project.pbxproj
set_version() {
    local new_version=$1
    
    log "Updating version to $new_version in project.pbxproj..."
    
    # Replace all MARKETING_VERSION occurrences
    sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $new_version;/g" "$PBXPROJ"
    
    log "Version updated to $new_version"
}

# Main build process
main() {
    # Parse command line arguments
    parse_args "$@"
    
    log "Starting release build for $APP_NAME"
    log "Project directory: $PROJECT_DIR"
    
    # Show configuration
    show_config
    
    # Prompt for notarization credentials if needed
    prompt_notarization_credentials
    
    # CloudKit warning
    if [ "$WITH_CLOUDKIT" = "1" ]; then
        warn "CloudKit enabled: Make sure you have a valid provisioning profile configured"
        warn "Without proper provisioning, the app will fail to launch with 'Error 163'"
    fi
    
    # Get current version
    CURRENT_VERSION=$(get_version)
    info "Current version: $CURRENT_VERSION"
    
    # Bump version if requested
    if [ -n "$BUMP_TYPE" ]; then
        VERSION=$(bump_version "$CURRENT_VERSION" "$BUMP_TYPE")
        set_version "$VERSION"
        log "Version bumped: $CURRENT_VERSION → $VERSION ($BUMP_TYPE)"
    else
        VERSION="$CURRENT_VERSION"
        info "Building with current version: $VERSION"
    fi
    
    # Clean
    clean
    
    # Download OpenCode binaries based on target architectures
    if [ "$BUILD_ARM64" = "1" ]; then
        download_opencode "arm64" "$OPENCODE_ARM64_URL"
    fi
    if [ "$BUILD_X86" = "1" ]; then
        download_opencode "x86_64" "$OPENCODE_X64_URL"
    fi
    
    # Build for arm64 (Apple Silicon)
    if [ "$BUILD_ARM64" = "1" ]; then
        log "=== Building for Apple Silicon (arm64) ==="
        build_app "arm64"
        inject_opencode "arm64"
        sign_app "arm64"
        notarize_app "arm64"
        create_dmg "arm64"
    fi
    
    # Build for x86_64 (Intel)
    if [ "$BUILD_X86" = "1" ]; then
        log "=== Building for Intel (x86_64) ==="
        build_app "x86_64"
        inject_opencode "x86_64"
        sign_app "x86_64"
        notarize_app "x86_64"
        create_dmg "x86_64"
    fi
    
    log "=== Build Complete ==="
    log "Release files:"
    ls -la "$RELEASE_DIR"
    
    echo ""
    info "Build summary:"
    info "  CloudKit:      $([ "$WITH_CLOUDKIT" = "1" ] && echo "✅ Enabled" || echo "❌ Disabled (default)")"
    info "  Notarization:  $([ "$NOTARIZE" = "1" ] && echo "✅ Done" || echo "❌ Skipped")"
}

# Run
main "$@"
