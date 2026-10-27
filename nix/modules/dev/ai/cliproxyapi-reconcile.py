"""Clear stale Claude cooldowns only after OAuth usage confirms capacity."""
import json
import math
import pathlib
import sys
import urllib.error
import urllib.request


def healthy_usage(usage):
    def available(value):
        return (type(value) in (int, float) and math.isfinite(value)
                and 0 <= value < 100)

    for name in ("five_hour", "seven_day"):
        window = usage.get(name)
        if not isinstance(window, dict) or not available(window.get("utilization")):
            return False
    for name, window in usage.items():
        if name.startswith("seven_day_") and window is not None:
            if not isinstance(window, dict) or not available(window.get("utilization")):
                return False
    for limit in usage.get("limits", []):
        if not isinstance(limit, dict) or not available(limit.get("percent")):
            return False
    return True


def reconcile(api):
    for credential in api("auth-files")["files"]:
        if (credential.get("provider") != "claude" or credential.get("disabled")
                or not credential.get("next_retry_after")):
            continue
        try:
            response = api("api-call", {
                "auth_index": credential["auth_index"], "method": "GET",
                "url": "https://api.anthropic.com/api/oauth/usage",
                "header": {"Authorization": "Bearer $TOKEN$",
                           "anthropic-beta": "oauth-2025-04-20"},
            })
            if response.get("status_code") != 200:
                continue
            usage = json.loads(response["body"])
            if not isinstance(usage, dict) or not healthy_usage(usage):
                continue
            name = credential["name"]
            # Always attempt re-enabling, even if the disable response is lost.
            try:
                api("auth-files/status", {"name": name, "disabled": True}, "PATCH")
            finally:
                api("auth-files/status", {"name": name, "disabled": False}, "PATCH")
            print(f"Cleared stale cooldown for {name}", flush=True)
        except (OSError, ValueError, KeyError, TypeError):
            # Never log response bodies or authorization headers.
            print("Could not reconcile a Claude credential; will retry next run", file=sys.stderr)


def main():
    state = pathlib.Path(sys.argv[1])
    key = (state / "management-key").read_text().strip()

    def api(endpoint, data=None, method=None):
        request = urllib.request.Request(
            "http://127.0.0.1:8317/v0/management/" + endpoint,
            data=json.dumps(data).encode() if data is not None else None,
            headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
            method=method,
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)

    reconcile(api)


if __name__ == "__main__":
    main()
