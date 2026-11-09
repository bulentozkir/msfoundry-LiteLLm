import getpass
import json
import os
import sys
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")

APIM_SUBSCRIPTION_KEY = os.environ.get("APIM_SUBSCRIPTION_KEY", "").strip()
if not APIM_SUBSCRIPTION_KEY:
    try:
        APIM_SUBSCRIPTION_KEY = getpass.getpass("APIM subscription key: ").strip()
    except (EOFError, KeyboardInterrupt):
        raise SystemExit(
            "No subscription key supplied. Set APIM_SUBSCRIPTION_KEY or run "
            "the script in a terminal to enter it securely."
        ) from None

if not APIM_SUBSCRIPTION_KEY:
    raise SystemExit("APIM subscription key cannot be empty.")

url = (
    "https://togg-ai-platform-apim.azure-api.net/"
    "TOGG-AI-PLATFORM-FOUNDRY-02/openai/deployments/"
    "DeepSeek-V4.1-Flash-1017/chat/completions?api-version=2024-10-21"
)

payload = {
    "messages": [{"role": "user", "content": "Say hello briefly."}],
    "max_tokens": 128,
}
request = urllib.request.Request(
    url,
    data=json.dumps(payload).encode(),
    headers={
        "Content-Type": "application/json",
        "Ocp-Apim-Subscription-Key": APIM_SUBSCRIPTION_KEY,
    },
)
with urllib.request.urlopen(request, timeout=150) as response:
    result = json.load(response)

print(result["choices"][0]["message"]["content"])
print(result["usage"])