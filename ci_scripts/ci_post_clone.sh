#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"

resolve_workspace() {
    for candidate in "${CI_WORKSPACE-}" "${CI_PRIMARY_REPOSITORY_PATH-}" "$repo_root" "$PWD"; do
        [ -n "$candidate" ] || continue
        if [ -f "$candidate/Config/Base.xcconfig" ]; then
            printf '%s\n' "$candidate"
            return
        fi
    done

    printf '%s\n' "$repo_root"
}

workspace="$(resolve_workspace)"
config_dir="$workspace/Config"
config_file="$config_dir/AISecrets.xcconfig"

mkdir -p "$config_dir"

printf 'ci_post_clone: PWD=%s\n' "$PWD"
printf 'ci_post_clone: script_dir=%s\n' "$script_dir"
printf 'ci_post_clone: repo_root=%s\n' "$repo_root"
printf 'ci_post_clone: CI_WORKSPACE=%s\n' "${CI_WORKSPACE-<unset>}"
printf 'ci_post_clone: CI_PRIMARY_REPOSITORY_PATH=%s\n' "${CI_PRIMARY_REPOSITORY_PATH-<unset>}"
printf 'ci_post_clone: workspace=%s\n' "$workspace"
printf 'ci_post_clone: config_file=%s\n' "$config_file"
if [ ! -f "$workspace/Config/Base.xcconfig" ]; then
    echo "warning: Base.xcconfig not found at $workspace/Config/Base.xcconfig" >&2
fi

escape_for_xcconfig() {
    # Avoid accidental comment parsing for URLs (//) in xcconfig.
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/\//\\\//g'
}

append_if_set() {
    var_name="$1"
    key_name="$2"
    eval "raw_value=\${$var_name-}"
    trimmed_value="$(printf '%s' "${raw_value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [ -n "${trimmed_value}" ]; then
        escaped_value="$(escape_for_xcconfig "$trimmed_value")"
        printf '%s = %s\n' "$key_name" "$escaped_value" >> "$config_file"
    fi
}

normalize_admob_value() {
    value="$(printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    value="$(printf '%s' "$value" | sed -e ':double' -e 's/^"\\(.*\\)"$/\\1/' -e 't double' -e ":single" -e "s/^'\\(.*\\)'$/\\1/" -e 't single')"
    printf '%s' "$value" | sed -e 's#\\/#/#g'
}

is_valid_admob_unit_id() {
    printf '%s' "$1" | grep -Eq '^ca-app-pub-[0-9]{16}/[0-9]{10}$'
}

is_admob_app_id() {
    printf '%s' "$1" | grep -Eq '^ca-app-pub-[0-9]{16}~[0-9]+$'
}

masked_admob_value() {
    value="$1"
    if printf '%s' "$value" | grep -Eq '^ca-app-pub-[0-9]{16}/[0-9]{10}$'; then
        publisher_prefix="$(printf '%s' "$value" | sed -E 's#^(.*/).{4}$#\1****#')"
        suffix="$(printf '%s' "$value" | sed -nE 's#^.*/([0-9]{4})$#\1#p')"
        printf '%s%s' "$publisher_prefix" "$suffix"
        return
    fi

    printf 'len=%s' "${#value}"
}

handle_invalid_admob_value() {
    var_name="$1"
    normalized_value="$2"

    if is_admob_app_id "$normalized_value"; then
        message="$var_name looks like a GADApplicationIdentifier/App ID (~) instead of an ad unit ID (/)."
    else
        message="$var_name must match ca-app-pub-<publisher>/<unit> after trimming quotes and whitespace."
    fi

    if [ "${CI_XCODEBUILD_ACTION-}" = "archive" ]; then
        echo "error: $message" >&2
        exit 1
    fi

    echo "warning: $message" >&2
}

append_admob_if_set() {
    var_name="$1"
    key_name="$2"
    eval "raw_value=\${$var_name-}"
    trimmed_value="$(printf '%s' "${raw_value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    normalized_value="$(normalize_admob_value "$trimmed_value")"

    if [ -n "${normalized_value}" ]; then
        if ! is_valid_admob_unit_id "$normalized_value"; then
            handle_invalid_admob_value "$var_name" "$normalized_value"
            return
        fi

        escaped_value="$(escape_for_xcconfig "$normalized_value")"
        printf '%s = %s\n' "$key_name" "$escaped_value" >> "$config_file"
    fi
}

report_var_state() {
    var_name="$1"
    eval "raw_value=\${$var_name-}"
    trimmed_value="$(printf '%s' "${raw_value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ -n "${trimmed_value}" ]; then
        if [ "${trimmed_value}" != "${raw_value}" ]; then
            printf 'ci_post_clone: %s=SET(trimmed,len=%s)\n' "$var_name" "${#trimmed_value}"
        else
            printf 'ci_post_clone: %s=SET(len=%s)\n' "$var_name" "${#trimmed_value}"
        fi
    else
        printf 'ci_post_clone: %s=EMPTY\n' "$var_name"
    fi
}

report_admob_var_state() {
    var_name="$1"
    eval "raw_value=\${$var_name-}"
    trimmed_value="$(printf '%s' "${raw_value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    normalized_value="$(normalize_admob_value "$trimmed_value")"

    if [ -z "${normalized_value}" ]; then
        printf 'ci_post_clone: %s=EMPTY\n' "$var_name"
        return
    fi

    masked_value="$(masked_admob_value "$normalized_value")"
    if is_valid_admob_unit_id "$normalized_value"; then
        printf 'ci_post_clone: %s=SET(valid,%s)\n' "$var_name" "$masked_value"
        return
    fi

    if is_admob_app_id "$normalized_value"; then
        printf 'ci_post_clone: %s=SET(invalid_app_id,%s)\n' "$var_name" "$masked_value"
        return
    fi

    printf 'ci_post_clone: %s=SET(invalid,%s)\n' "$var_name" "$masked_value"
}

is_non_empty_var() {
    var_name="$1"
    eval "raw_value=\${$var_name-}"
    trimmed_value="$(printf '%s' "${raw_value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "${trimmed_value}" ]
}

cat > "$config_file" <<EOC
// Generated by ci_scripts/ci_post_clone.sh in Xcode Cloud.
// Do not commit this file.
// Only non-empty environment variables are written so Base.xcconfig defaults are preserved.
EOC

append_if_set AI_API_ENDPOINT AI_API_ENDPOINT
append_if_set AI_API_KEY AI_API_KEY
append_if_set AI_MODEL AI_MODEL

append_if_set NOTION_CLIENT_ID NOTION_CLIENT_ID
append_if_set NOTION_REDIRECT_URI NOTION_REDIRECT_URI

append_if_set SECURE_SERVER_BASE_URL SECURE_SERVER_BASE_URL
append_if_set SECURE_SERVER_CLIENT_ID SECURE_SERVER_CLIENT_ID
append_if_set SECURE_SERVER_CLIENT_SECRET SECURE_SERVER_CLIENT_SECRET
append_if_set SECURE_SERVER_REQUIRE_TLS SECURE_SERVER_REQUIRE_TLS
append_if_set SECURE_SERVER_METRICS_TOKEN SECURE_SERVER_METRICS_TOKEN

append_admob_if_set ADMOB_BANNER_AD_UNIT_ID ADMOB_BANNER_AD_UNIT_ID
append_admob_if_set ADMOB_REWARDED_INTERSTITIAL_AD_UNIT_ID ADMOB_REWARDED_INTERSTITIAL_AD_UNIT_ID
append_admob_if_set ADMOB_INTERSTITIAL_AD_UNIT_ID ADMOB_INTERSTITIAL_AD_UNIT_ID
append_if_set ADMOB_ENABLE_REWARDED_INTERSTITIAL_FALLBACK ADMOB_ENABLE_REWARDED_INTERSTITIAL_FALLBACK

append_if_set ADS_SWIFT_FLAGS ADS_SWIFT_FLAGS

report_var_state AI_API_ENDPOINT
report_var_state AI_API_KEY
report_var_state AI_MODEL
report_var_state SECURE_SERVER_BASE_URL
report_var_state SECURE_SERVER_CLIENT_ID
report_var_state SECURE_SERVER_CLIENT_SECRET
report_admob_var_state ADMOB_BANNER_AD_UNIT_ID
report_admob_var_state ADMOB_REWARDED_INTERSTITIAL_AD_UNIT_ID
report_admob_var_state ADMOB_INTERSTITIAL_AD_UNIT_ID
report_var_state ADMOB_ENABLE_REWARDED_INTERSTITIAL_FALLBACK

secure_config_ready=0
if is_non_empty_var SECURE_SERVER_CLIENT_ID && is_non_empty_var SECURE_SERVER_CLIENT_SECRET; then
    secure_config_ready=1
fi

local_ai_config_ready=0
if is_non_empty_var AI_API_ENDPOINT && is_non_empty_var AI_API_KEY && is_non_empty_var AI_MODEL; then
    local_ai_config_ready=1
fi

if [ "$secure_config_ready" -eq 0 ] && [ "$local_ai_config_ready" -eq 0 ]; then
    echo "warning: Missing AI runtime config. Need SECURE_SERVER_CLIENT_ID+SECURE_SERVER_CLIENT_SECRET or full local AI_API_* values." >&2
    if [ "${CI_XCODEBUILD_ACTION-}" = "archive" ]; then
        echo "error: Aborting archive because runtime AI configuration is incomplete." >&2
        exit 1
    fi
fi

printf 'Generated %s\n' "$config_file"
