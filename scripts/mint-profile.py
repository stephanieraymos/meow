#!/usr/bin/env python3
"""Mint + install the Meowdoku App Store distribution profile via the App Store
Connect API. This account's cloud signing is disabled, so we manage the profile
manually. Idempotent: deletes any existing profile of the same name and recreates
it including every distribution certificate on the account (so it matches
whichever cert is in the local Keychain). Stdlib only — signs the ES256 JWT with
the openssl CLI."""
import json, time, base64, subprocess, urllib.request, urllib.error, os, sys

KEY_ID = "RJ7CKLZFFX"
ISSUER = "4e55d966-9145-4f15-bfc6-c698befe9a66"
BUNDLE = "com.stephanieraymos.meowdoku"
PROFILE_NAME = "Meowdoku App Store CLI"
KEY_PATH = os.path.expanduser(f"~/.private_keys/AuthKey_{KEY_ID}.p8")


def b64url(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def make_jwt():
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    payload = {"iss": ISSUER, "iat": int(time.time()), "exp": int(time.time()) + 1200,
               "aud": "appstoreconnect-v1"}
    signing_input = (b64url(json.dumps(header, separators=(',', ':')).encode()) + "." +
                     b64url(json.dumps(payload, separators=(',', ':')).encode())).encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", KEY_PATH],
                         input=signing_input, capture_output=True).stdout
    i = 2 + (der[1] & 0x7f) if der[1] & 0x80 else 2

    def read_int(idx):
        ln = der[idx + 1]
        return der[idx + 2:idx + 2 + ln].lstrip(b'\x00').rjust(32, b'\x00'), idx + 2 + ln
    r, i = read_int(i)
    s, _ = read_int(i)
    return signing_input.decode() + "." + b64url(r + s)


TOKEN = make_jwt()


def api(method, path, body=None):
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=json.dumps(body).encode() if body else None, method=method,
        headers={"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r) if method != "DELETE" else {}
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} {method} {path}: {e.read().decode()}"); sys.exit(1)


for p in api("GET", "/v1/profiles?limit=200")["data"]:
    if p["attributes"]["name"] == PROFILE_NAME:
        api("DELETE", "/v1/profiles/" + p["id"])

cert_ids = [c["id"] for c in api("GET", "/v1/certificates?limit=200")["data"]
            if c["attributes"]["certificateType"] in ("DISTRIBUTION", "IOS_DISTRIBUTION")]
bundle = api("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE}&limit=200")["data"]
if not bundle:
    print(f"❌ Bundle id {BUNDLE} not registered yet — run an archive once first."); sys.exit(1)

prof = api("POST", "/v1/profiles", {"data": {"type": "profiles",
    "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
    "relationships": {
        "bundleId": {"data": {"type": "bundleIds", "id": bundle[0]["id"]}},
        "certificates": {"data": [{"type": "certificates", "id": c} for c in cert_ids]}}}})
attrs = prof["data"]["attributes"]
dest = os.path.expanduser(f"~/Library/MobileDevice/Provisioning Profiles/{attrs['uuid']}.mobileprovision")
os.makedirs(os.path.dirname(dest), exist_ok=True)
open(dest, "wb").write(base64.b64decode(attrs["profileContent"]))
print(f"✅ Installed '{attrs['name']}' ({attrs['uuid']}) with {len(cert_ids)} cert(s)")
