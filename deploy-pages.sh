#!/bin/bash
# Rebuild the static export and redeploy to Cloudflare Pages project "orderflow".
# Requires the custom.cloudflare credential surrogate (see CONNECTOR.md).
set -e
cd "$(dirname "$0")"
npm run build
python3 - << 'PY'
import sys, os, urllib.request, json, mimetypes, uuid, hashlib
sys.path.insert(0, "/opt/muse/skills/custom-connector-setup/bin")
from dynamic_credentials import add_surrogate_to_request, read_json_response
ACC="e4908f71d666474dd617861b6e6a42df"
root=os.path.join(os.getcwd(),"out")
boundary = uuid.uuid4().hex
files=[]
for dirpath, _, fns in os.walk(root):
    for fn in fns:
        full=os.path.join(dirpath,fn)
        rel=os.path.relpath(full, root).replace(os.sep,'/')
        with open(full,'rb') as fh: data=fh.read()
        files.append((rel, data, hashlib.sha256(data).hexdigest()))
manifest = json.dumps({rel: h for rel,_,h in files})
parts=[b"--"+boundary.encode()+b"\r\n"+b'Content-Disposition: form-data; name="manifest"\r\n\r\n'+manifest.encode()+b"\r\n"]
for rel, data, _ in files:
    ctype, _ = mimetypes.guess_type(rel)
    parts.append(b"--"+boundary.encode()+b"\r\n"+f'Content-Disposition: form-data; name="{rel}"; filename="{rel}"\r\n'.encode()+f"Content-Type: {ctype or 'application/octet-stream'}\r\n\r\n".encode()+data+b"\r\n")
body = b"".join(parts)+b"--"+boundary.encode()+b"--\r\n"
r = urllib.request.Request(f"https://api.cloudflare.com/client/v4/accounts/{ACC}/pages/projects/orderflow/deployments", method="POST", data=body)
r.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
add_surrogate_to_request(r, "custom.cloudflare", allowed_hosts=["api.cloudflare.com"])
with urllib.request.urlopen(r, timeout=120) as resp:
    res = read_json_response(resp)
print(json.dumps(res["result"], indent=1)[:600])
PY
