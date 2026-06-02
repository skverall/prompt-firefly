#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="com.shokhabbos.PromptFirefly"

/usr/bin/tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "Accessibility permission reset for $BUNDLE_ID"
echo "Restart PromptFirefly, click Request, then enable it in System Settings."
