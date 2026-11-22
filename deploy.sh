#!/usr/bin/env bash
set -euo pipefail
cd /home/user/Doubao/chats/38452649716263170/news-publish
DEVICE_JSON=device.json
TOKEN=""
for i in $(seq 1 180); do
  RESP=$(python3 - <<'PY'
import json,urllib.parse,urllib.request
d=json.load(open('device.json'))
data=urllib.parse.urlencode({'client_id':'178c6fc778ccc68e1d6a','device_code':d['device_code'],'grant_type':'urn:ietf:params:oauth:grant-type:device_code'}).encode()
req=urllib.request.Request('https://github.com/login/oauth/access_token',data=data,headers={'Accept':'application/json'})
try:
    print(urllib.request.urlopen(req,timeout=15).read().decode())
except Exception as e:
    print('{"error":"network","error_description":"%s"}'%str(e).replace('"',''))
PY
)
  echo "poll $i: $RESP" | sed 's/access_token[^,}]*/access_token=REDACTED/'
  TOKEN=$(python3 -c 'import sys,json; s=sys.stdin.read(); print(json.loads(s).get("access_token",""))' <<<"$RESP" 2>/dev/null || true)
  if [ -n "$TOKEN" ]; then break; fi
  ERR=$(python3 -c 'import sys,json; s=sys.stdin.read(); print(json.loads(s).get("error",""))' <<<"$RESP" 2>/dev/null || true)
  if [ "$ERR" = "authorization_pending" ] || [ "$ERR" = "slow_down" ]; then sleep 5; else sleep 5; fi
done
if [ -z "$TOKEN" ]; then echo "NO_TOKEN"; exit 1; fi

API="https://api.github.com"
AUTH="Authorization: token $TOKEN"
ACCEPT="Accept: application/vnd.github+json"
USER=$(curl -sS -H "$AUTH" -H "$ACCEPT" "$API/user" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("login",""))')
echo "USER=$USER"
REPO="news-stats"
CODE=$(curl -sS -o /tmp/repo_create.json -w '%{http_code}' -X POST -H "$AUTH" -H "$ACCEPT" "$API/user/repos" -d "{\"name\":\"$REPO\",\"description\":\"新闻部工作统计公网只读版\",\"homepage\":\"https://$USER.github.io/$REPO/\",\"private\":false,\"has_issues\":true,\"has_projects\":false,\"has_wiki\":false}")
echo "CREATE_REPO=$CODE"
cat /tmp/repo_create.json | head -c 300; echo

# init and push (fresh history to keep it simple)
rm -rf .git
git init -q
git config user.name "sixqwe"
git config user.email "sixqwe@users.noreply.github.com"
git add index.html
git commit -q -m "news stats public read-only page"
git branch -M master
git remote add origin "https://x-access-token:$TOKEN@github.com/$USER/$REPO.git"
git push -q -u origin master --force
echo "PUSHED"

# enable pages (POST; if exists, PUT)
CODE=$(curl -sS -o /tmp/pages.json -w '%{http_code}' -X POST -H "$AUTH" -H "$ACCEPT" "$API/repos/$USER/$REPO/pages" -d '{"source":{"branch":"master","path":"/"}}')
echo "PAGES_POST=$CODE"
cat /tmp/pages.json | head -c 300; echo
if [ "$CODE" != "201" ] && [ "$CODE" != "200" ]; then
  CODE=$(curl -sS -o /tmp/pages.json -w '%{http_code}' -X PUT -H "$AUTH" -H "$ACCEPT" "$API/repos/$USER/$REPO/pages" -d '{"source":{"branch":"master","path":"/"}}')
  echo "PAGES_PUT=$CODE"; cat /tmp/pages.json | head -c 300; echo
fi

for i in $(seq 1 30); do
  sleep 5
  curl -sS -H "$AUTH" -H "$ACCEPT" "$API/repos/$USER/$REPO/pages" -o /tmp/pages_status.json || true
  URL=$(python3 -c 'import sys,json; d=json.load(open("/tmp/pages_status.json")); print(d.get("html_url",""))' 2>/dev/null || true)
  STATUS=$(python3 -c 'import sys,json; d=json.load(open("/tmp/pages_status.json")); print(d.get("status",""))' 2>/dev/null || true)
  echo "page $i status=$STATUS url=$URL"
  if [ -n "$URL" ]; then echo "PUBLIC_URL=$URL"; break; fi
done
