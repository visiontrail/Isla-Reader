#!/bin/bash

################################################################################
# LanRead - App Store Review Preflight
# Purpose: Run practical release checks before App Store submission
# Usage:
#   ./scripts/preflight-app-review.sh
#   ./scripts/preflight-app-review.sh --full
################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$PROJECT_DIR"

FULL_MODE=false

for arg in "$@"; do
    case "$arg" in
        --full)
            FULL_MODE=true
            ;;
        -h|--help)
            echo "Usage: ./scripts/preflight-app-review.sh [--full]"
            echo "  default : static preflight checks only"
            echo "  --full  : include localization/epub checks + xcodebuild test"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: ./scripts/preflight-app-review.sh [--full]"
            exit 1
            ;;
    esac
done

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

pass() {
    echo -e "${GREEN}  PASS${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

warn() {
    echo -e "${YELLOW}  WARN${NC} $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

fail() {
    echo -e "${RED}  FAIL${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

section() {
    echo ""
    echo -e "${BLUE}[$1]${NC}"
}

has_pattern() {
    local pattern="$1"
    shift
    if command -v rg >/dev/null 2>&1; then
        rg -n --hidden --glob '!**/.git/**' "$pattern" "$@" >/dev/null 2>&1
    else
        grep -R -n -E --exclude-dir=.git "$pattern" "$@" >/dev/null 2>&1
    fi
}

count_placeholders() {
    local target="$1"
    if command -v rg >/dev/null 2>&1; then
        rg -n '\$\([A-Za-z0-9_]+\)' "$target" | wc -l | xargs
    else
        grep -n -E '\$\([A-Za-z0-9_]+\)' "$target" | wc -l | xargs
    fi
}

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  App Store Review Preflight${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Project: $PROJECT_DIR"
if [ "$FULL_MODE" = true ]; then
    echo "Mode: full"
else
    echo "Mode: static"
fi

section "1) Core project files"

if [ -f "Isla Reader/Info.plist" ]; then
    pass "Info.plist exists"
else
    fail "Missing Isla Reader/Info.plist"
fi

if [ -f "Isla Reader.xcodeproj/project.pbxproj" ]; then
    pass "Xcode project exists"
else
    fail "Missing Xcode project file"
fi

section "2) Review contact & policy entry points"

if has_pattern "support@isla-reader\.top|mailto:" "Isla Reader/Views/SettingsView.swift"; then
    pass "Support contact entry exists in Settings"
else
    warn "No in-app support contact link found in Settings"
fi

if has_pattern "https://isla-reader\.top/privacy|app\.privacy_policy" "Isla Reader/Views/SettingsView.swift"; then
    pass "Privacy policy entry exists in Settings"
else
    fail "Missing in-app privacy policy entry (high review risk)"
fi

if [ -f "server/app/static/landing/terms.html" ] || [ -f "server/app/routers/pages.py" ]; then
    pass "Terms/privacy hosting artifacts detected"
else
    warn "Cannot verify terms/privacy hosting artifacts in repo"
fi

section "2.1) AI privacy disclosure (5.1.1(i), 5.1.2(i))"

if has_pattern "ai\\.consent\\.launch\\.third_party_provider_format|ai\\.consent\\.launch\\.privacy_policy_link" "Isla Reader/en.lproj/Localizable.strings"; then
    pass "AI consent copy includes provider disclosure + privacy policy entry"
else
    fail "AI consent copy is missing provider disclosure/privacy policy localization keys"
fi

if has_pattern "settings\\.ai_privacy\\.section|settings\\.ai_privacy\\.manage_title" "Isla Reader/en.lproj/Localizable.strings" "Isla Reader/Views/SettingsView.swift"; then
    pass "Settings includes AI privacy management entry"
else
    fail "Missing AI privacy management entry in Settings"
fi

if has_pattern "requiredConsentVersion|aiPrivacyConsentVersion|presentLaunchConsentIfNeeded" "Isla Reader/Utils/AIConfig.swift"; then
    pass "Consent versioning marker detected"
else
    warn "No consent versioning marker detected; re-consent after policy copy changes may be skipped"
fi

section "3) Privacy label + ATT consistency"

has_admob=false
has_att_call=false
has_tracking_desc=false

if has_pattern "GoogleMobileAds|GADMobileAds|GADApplicationIdentifier|AdMob" "Isla Reader"; then
    has_admob=true
fi

if has_pattern "ATTrackingManager|requestTrackingAuthorization" "Isla Reader"; then
    has_att_call=true
fi

if has_pattern "NSUserTrackingUsageDescription" "Isla Reader/Info.plist"; then
    has_tracking_desc=true
fi

if [ "$has_admob" = true ]; then
    pass "Ad SDK detected (AdMob)"
else
    pass "No ad SDK marker detected"
fi

if [ "$has_att_call" = true ] && [ "$has_tracking_desc" = false ]; then
    fail "ATT API detected but NSUserTrackingUsageDescription is missing"
elif [ "$has_att_call" = true ] && [ "$has_tracking_desc" = true ]; then
    pass "ATT API and usage description both present"
elif [ "$has_att_call" = false ] && [ "$has_tracking_desc" = true ]; then
    warn "NSUserTrackingUsageDescription exists but no ATT call found; verify privacy label accuracy"
else
    warn "No ATT API / NSUserTrackingUsageDescription detected; if tracking is used by SDK flow, this will be rejected"
fi

section "4) Payments / IAP"

has_iap=false
has_restore=false

if has_pattern "StoreKit|Product\(|SKPaymentQueue|Transaction\.currentEntitlements|InAppPurchase|SubscriptionStoreView" "Isla Reader"; then
    has_iap=true
fi

if has_pattern "restorePurchases|Restore Purchases|恢复购买|復元|복원" "Isla Reader"; then
    has_restore=true
fi

if [ "$has_iap" = false ]; then
    pass "No IAP implementation markers found"
else
    warn "IAP markers found; verify 3.1.1 and metadata are complete"
    if [ "$has_restore" = true ]; then
        pass "Restore purchases entry marker found"
    else
        fail "IAP markers found but no restore purchase marker found"
    fi
fi

section "5) Login compliance (Sign in with Apple trigger check)"

has_third_party_login=false
has_apple_signin=false

if has_pattern "GoogleSignIn|FBSDK|Login with Google|Login with Facebook|Sign in with Google|Sign in with Facebook" "Isla Reader"; then
    has_third_party_login=true
fi

if has_pattern "ASAuthorizationAppleIDProvider|SignInWithAppleButton|ASAuthorizationAppleIDCredential" "Isla Reader"; then
    has_apple_signin=true
fi

if [ "$has_third_party_login" = true ] && [ "$has_apple_signin" = false ]; then
    fail "Third-party login markers found but Sign in with Apple markers missing"
elif [ "$has_third_party_login" = true ] && [ "$has_apple_signin" = true ]; then
    pass "Third-party login and Sign in with Apple markers both found"
else
    pass "No obvious third-party app-login marker detected"
fi

section "6) Account deletion (conditional)"

has_account_creation=false
has_account_deletion=false

if has_pattern "create account|sign up|signup|register|注册账号|创建账号|アカウント作成|회원가입" "Isla Reader"; then
    has_account_creation=true
fi

if has_pattern "delete account|account deletion|删除账号|注销账号|アカウント削除|계정 삭제" "Isla Reader" "README.md" "README_CN.md"; then
    has_account_deletion=true
fi

if [ "$has_account_creation" = true ] && [ "$has_account_deletion" = false ]; then
    fail "Account creation markers found but no account deletion marker found"
elif [ "$has_account_creation" = true ] && [ "$has_account_deletion" = true ]; then
    pass "Account creation/deletion markers both found"
else
    pass "No obvious in-app account creation marker detected (deletion rule likely N/A)"
fi

section "7) UGC / chat safety (conditional)"

has_ugc=false
has_report_or_block=false

if has_pattern "public post|community feed|comment thread|user generated content|聊天室|社区帖子|评论区|匿名聊天|随机聊天" "Isla Reader"; then
    has_ugc=true
fi

if has_pattern "report user|report content|block user|举报用户|举报内容|拉黑|신고|차단|通報|ブロック" "Isla Reader"; then
    has_report_or_block=true
fi

if [ "$has_ugc" = true ] && [ "$has_report_or_block" = false ]; then
    fail "UGC/chat markers found but no report/block markers found"
elif [ "$has_ugc" = true ] && [ "$has_report_or_block" = true ]; then
    pass "UGC/chat safety markers found"
else
    pass "No obvious UGC/chat marker detected"
fi

section "8) Export compliance / encryption prompts"

if has_pattern "CryptoKit|CommonCrypto|SecKey|SecItem|Keychain" "Isla Reader"; then
    warn "Encryption/security APIs detected; complete App Store Connect export compliance questionnaire"
else
    warn "No explicit encryption API marker detected; App Store Connect export questionnaire is still required"
fi

section "9) Build config placeholder sanity"

placeholder_count=$(count_placeholders "Isla Reader/Info.plist" || true)
if [ "$placeholder_count" -gt 0 ]; then
    warn "Info.plist contains $placeholder_count build-time placeholders; verify Release xcconfig values before archive"
else
    pass "No unresolved placeholders in source Info.plist"
fi

release_app_plist="build/Build/Products/Release-iphonesimulator/LanRead.app/Info.plist"
if [ -f "$release_app_plist" ]; then
    if has_pattern '\$\([A-Za-z0-9_]+\)' "$release_app_plist"; then
        fail "Release app Info.plist still contains unresolved placeholders"
    else
        pass "Release app Info.plist has no unresolved placeholders"
    fi
else
    warn "Release app Info.plist not found (skip built artifact placeholder check)"
fi

if [ "$FULL_MODE" = true ]; then
    section "10) Full mode tests"

    if [ -x "./scripts/test-localization.sh" ]; then
        if ./scripts/test-localization.sh >/tmp/preflight-localization.log 2>&1; then
            pass "test-localization.sh passed"
        else
            fail "test-localization.sh failed (see /tmp/preflight-localization.log)"
        fi
    else
        warn "scripts/test-localization.sh not executable"
    fi

    if [ -x "./scripts/test-epub-parser.sh" ]; then
        if ./scripts/test-epub-parser.sh >/tmp/preflight-epub.log 2>&1; then
            pass "test-epub-parser.sh passed"
        else
            fail "test-epub-parser.sh failed (see /tmp/preflight-epub.log)"
        fi
    else
        warn "scripts/test-epub-parser.sh not executable"
    fi

    if command -v xcodebuild >/dev/null 2>&1; then
        if xcodebuild test -project "Isla Reader.xcodeproj" -scheme "LanRead" -destination 'platform=iOS Simulator,name=iPhone 16' >/tmp/preflight-xcodebuild-test.log 2>&1; then
            pass "xcodebuild test passed"
        else
            fail "xcodebuild test failed (see /tmp/preflight-xcodebuild-test.log)"
        fi
    else
        fail "xcodebuild not found"
    fi
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}PASS: $PASS_COUNT${NC}"
echo -e "${YELLOW}WARN: $WARN_COUNT${NC}"
echo -e "${RED}FAIL: $FAIL_COUNT${NC}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "${RED}Result: NOT READY for submission${NC}"
    exit 1
fi

echo -e "${GREEN}Result: Ready with warnings review${NC}"
exit 0
