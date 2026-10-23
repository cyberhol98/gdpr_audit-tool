#!/usr/bin/env bash

# =========================================================
#  GDPR WEBSITE AUDIT TOOL  (v2.0 - whole-site scanning)
#
#  Crawls a website (up to a page limit you choose), checks
#  each page for common GDPR and privacy basics, and creates
#  an easy-to-read report.
#
#  Works with Bash 3.2+ (macOS default), Linux, WSL, Git Bash.
# =========================================================

VERSION="2.0"
UA="Mozilla/5.0 (compatible; GDPR-Audit-Tool/$VERSION)"
DEFAULT_PAGES=20
MAX_ALLOWED=200
DELAY=0.5          # seconds to wait between pages (be polite to servers)

usage() {
  cat <<EOF
GDPR Website Audit Tool v$VERSION

Usage:
  ./gdpr_audit.sh                            Interactive mode (asks you questions)
  ./gdpr_audit.sh <website> [pages] [format] Quick mode

  website   The site to check, e.g. example.com
  pages     Maximum number of pages to check (default $DEFAULT_PAGES, max $MAX_ALLOWED)
  format    html (default), txt or md

Examples:
  ./gdpr_audit.sh mywebsite.co.uk
  ./gdpr_audit.sh mywebsite.co.uk 50
  ./gdpr_audit.sh mywebsite.co.uk 50 txt

Set IGNORE_ROBOTS=1 to also check pages your robots.txt asks crawlers to skip
(only do this on your own website):
  IGNORE_ROBOTS=1 ./gdpr_audit.sh mywebsite.co.uk
EOF
}

case "$1" in -h|--help) usage; exit 0 ;; esac

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: this tool needs 'curl', which isn't installed."
  exit 1
fi

echo "====================================="
echo "     GDPR Website Audit Tool v$VERSION"
echo "====================================="

# =========================
# INPUT
# =========================
if [ -n "$1" ]; then
  URL="$1"
  MAX_PAGES="${2:-$DEFAULT_PAGES}"
  FORMAT="${3:-html}"
else
  read -p "Enter website URL (e.g. example.com): " URL
  if [ -z "$URL" ]; then
    echo "No URL entered. Exiting."
    exit 1
  fi
  read -p "Maximum number of pages to check [$DEFAULT_PAGES]: " MAX_PAGES
  echo ""
  echo "Choose output format:"
  echo "1) Web page (recommended - opens in your browser)"
  echo "2) txt"
  echo "3) md"
  read -p "Enter choice (1-3) [1]: " FORMAT
fi

case "$MAX_PAGES" in ''|*[!0-9]*) MAX_PAGES=$DEFAULT_PAGES ;; esac
[ "$MAX_PAGES" -lt 1 ] && MAX_PAGES=1
[ "$MAX_PAGES" -gt $MAX_ALLOWED ] && MAX_PAGES=$MAX_ALLOWED

case "$(printf '%s' "$FORMAT" | tr '[:upper:]' '[:lower:]')" in
  2|txt) FORMAT="txt" ;;
  3|md)  FORMAT="md" ;;
  *)     FORMAT="html" ;;
esac

URL=$(printf '%s' "$URL" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
if [[ ! $URL =~ ^[Hh][Tt][Tt][Pp][Ss]?:// ]]; then
  URL="https://$URL"
fi

# =========================
# HELPERS
# =========================
lower()   { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
host_of() { printf '%s' "$1" | sed -E 's|^[A-Za-z]+://||; s|[/?#].*$||' | tr '[:upper:]' '[:lower:]'; }
path_of() {
  local p
  p=$(printf '%s' "$1" | sed -E 's|^[A-Za-z]+://[^/?#]*||; s|[?#].*$||')
  [ -z "$p" ] && p="/"
  printf '%s' "$p"
}
scheme_of() { lower "${1%%://*}"; }
same_site() { local h; h=$(host_of "$1"); h=${h#www.}; [ "$h" = "$BASE_DOMAIN" ]; }
in_list()   { printf '%s' "$2" | grep -Fxq -- "$1"; }
count_lines() { if [ -z "$1" ]; then echo 0; else printf '%s' "$1" | grep -c .; fi; }
show_path() {
  local p; p=$(path_of "$1")
  if [ "$p" = "/" ]; then printf '/ (homepage)'; else printf '%s' "$p"; fi
}

HOST=$(host_of "$URL")
BASE_DOMAIN=${HOST#www.}
ORIGIN="$(scheme_of "$URL")://$HOST"

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t gdpr_audit)
trap 'rm -rf "$WORK"' EXIT
: > "$WORK/seen"; : > "$WORK/scanned"
: > "$WORK/q_top"; : > "$WORK/q_pri"; : > "$WORK/q_rest"
: > "$WORK/disallow"

# Fetch a URL into a file. Prints: http_code|content_type|final_url
fetch() {
  curl -sL --max-time 20 --max-redirs 5 -A "$UA" -o "$2" \
       -w '%{http_code}|%{content_type}|%{url_effective}' "$1" 2>/dev/null
}

# Turn links found on a page into clean, de-duplicated same-site URLs
extract_links() {  # $1 = page file, $2 = page's final URL
  tr '\n\r' '  ' < "$1" \
  | grep -oiE "href[[:space:]]*=[[:space:]]*[\"'][^\"']*" \
  | sed -E "s/^[^\"']*[\"']//" \
  | awk -v origin="$ORIGIN" -v base="$2" -v dom="$BASE_DOMAIN" '
    function canon(u,   h, hh, p, n, i, parts, out, m) {
      sub(/#.*/, "", u); sub(/\?.*/, "", u)
      if (!match(u, /^[A-Za-z]+:\/\/[^\/]*/)) return ""
      h = substr(u, RSTART, RLENGTH); p = substr(u, RSTART + RLENGTH)
      hh = tolower(h); sub(/^[a-z]+:\/\//, "", hh); sub(/^www\./, "", hh)
      if (hh != dom) return ""
      n = split(p, parts, "/"); m = 0
      for (i = 2; i <= n; i++) {
        if (parts[i] == "" || parts[i] == ".") continue
        if (parts[i] == "..") { if (m > 0) m--; continue }
        out[++m] = parts[i]
      }
      p = ""
      for (i = 1; i <= m; i++) p = p "/" out[i]
      sub(/\/(index|default)\.(html?|php|aspx?)$/, "", p)
      if (p == "") p = "/"
      return origin p
    }
    BEGIN {
      scheme = origin; sub(/:.*/, "", scheme)
      b = base; sub(/[?#].*/, "", b); sub(/^[A-Za-z]+:\/\/[^\/]*/, "", b)
      if (b == "") b = "/"
      sub(/[^\/]*$/, "", b); bdir = b
    }
    {
      l = $0
      gsub(/^[ \t]+|[ \t]+$/, "", l); gsub(/&amp;/, "\\&", l)
      if (l == "" || l ~ /^[#?]/) next
      if (l ~ /^\/\//) l = scheme ":" l
      else if (l ~ /^[A-Za-z][A-Za-z0-9+.-]*:/) { if (l !~ /^[Hh][Tt][Tt][Pp][Ss]?:/) next }
      else if (l ~ /^\//) l = origin l
      else l = origin bdir l
      c = canon(l)
      if (c == "") next
      if (tolower(c) ~ /\.(pdf|jpe?g|png|gif|svg|webp|avif|bmp|ico|css|js|mjs|json|xml|rss|atom|txt|csv|zip|rar|7z|gz|tar|mp3|mp4|m4a|wav|mov|avi|webm|docx?|xlsx?|pptx?|odt|woff2?|ttf|otf|eot|exe|dmg|apk)$/) next
      if (tolower(c) ~ /\/(wp-admin|wp-login|wp-json|cdn-cgi|feed|xmlrpc)([\/.]|$)|log-?out|sign-?out/) next
      print c
    }' \
  | sort -u
}

# Add new links to the queue. Privacy/contact/sign-up style pages go first.
TOP_RE='privacy|cookie|gdpr|data-?protection'
PRI_RE='contact|terms|legal|sign-?up|register|join|subscribe|newsletter|checkout|account|login|book|enquir|quote|apply|donate'
queue_links() {
  grep -Fvxf "$WORK/seen" > "$WORK/new"
  [ -s "$WORK/new" ] || return
  cat "$WORK/new" >> "$WORK/seen"
  grep -iE "$TOP_RE" "$WORK/new" >> "$WORK/q_top"
  grep -viE "$TOP_RE" "$WORK/new" | grep -iE "$PRI_RE" >> "$WORK/q_pri"
  grep -viE "$TOP_RE|$PRI_RE" "$WORK/new" >> "$WORK/q_rest"
}

dequeue() {
  local q
  for q in q_top q_pri q_rest; do
    if [ -s "$WORK/$q" ]; then
      head -n 1 "$WORK/$q"
      tail -n +2 "$WORK/$q" > "$WORK/q_tmp" && mv "$WORK/q_tmp" "$WORK/$q"
      return 0
    fi
  done
  return 1
}

blocked_by_robots() {
  [ "$IGNORE_ROBOTS" = "1" ] && return 1
  local p rule
  p=$(path_of "$1")
  while IFS= read -r rule; do
    rule="${rule%%\**}"; rule="${rule%\$}"
    [ -z "$rule" ] && continue
    case "$p" in "$rule"*) return 0 ;; esac
  done < "$WORK/disallow"
  return 1
}

# =========================
# CRAWL
# =========================
PAGES=(); PAGE_FILES=()
FAILED=0; SKIPPED_ROBOTS=0

process_page() {  # $1 = URL. Returns 0 if the page was added.
  local url="$1" i=${#PAGES[@]} file res code rest ctype eff key
  file="$WORK/page_$i.html"
  res=$(fetch "$url" "$file")
  code=${res%%|*}; rest=${res#*|}; ctype=${rest%%|*}; eff=${rest#*|}

  if [ "$code" != "200" ]; then FAILED=$((FAILED+1)); rm -f "$file"; return 1; fi
  case "$(lower "$ctype")" in ''|*html*) ;; *) rm -f "$file"; return 1 ;; esac
  if ! same_site "$eff"; then rm -f "$file"; return 1; fi

  key=$(printf '%s\n' "$eff" | awk -v o="$ORIGIN" '{ sub(/[?#].*/, ""); sub(/^[A-Za-z]+:\/\/[^\/]*/, ""); sub(/\/(index|default)\.(html?|php|aspx?)$/, ""); sub(/\/+$/, ""); print o ($0 == "" ? "/" : $0) }')
  if grep -Fxq -- "$key" "$WORK/scanned"; then rm -f "$file"; return 1; fi
  echo "$key" >> "$WORK/scanned"
  echo "$key" >> "$WORK/seen"

  PAGES+=("$key"); PAGE_FILES+=("$file")
  echo "  [${#PAGES[@]}/$MAX_PAGES] $(show_path "$key")"

  extract_links "$file" "$eff" | queue_links
  return 0
}

echo ""
echo "Checking $URL (up to $MAX_PAGES pages)..."

# First page: work out where the site really lives (after redirects)
res=$(fetch "$URL" "$WORK/first.html")
code=${res%%|*}; rest=${res#*|}; eff=${rest#*|}
if [ "$code" != "200" ]; then
  echo ""
  echo "Error: couldn't load $URL (response code: ${code:-none})."
  echo "Check the address is correct and the site is online."
  exit 1
fi
EFF_HOST=$(host_of "$eff")
if [ "${EFF_HOST#www.}" != "$BASE_DOMAIN" ]; then
  echo "Note: $HOST redirects to $EFF_HOST, so we'll check that instead."
  BASE_DOMAIN=${EFF_HOST#www.}
fi
HOST=$EFF_HOST
ORIGIN="$(scheme_of "$eff")://$HOST"
rm -f "$WORK/first.html"

# Respect robots.txt (rules for all crawlers)
rcode=$(curl -s --max-time 10 -A "$UA" -o "$WORK/robots.txt" -w '%{http_code}' "$ORIGIN/robots.txt" 2>/dev/null)
if [ "$rcode" = "200" ]; then
  tr -d '\r' < "$WORK/robots.txt" | awk '
    { line = $0; sub(/#.*/, "", line); low = tolower(line) }
    low ~ /^[[:space:]]*user-agent[[:space:]]*:/ {
      v = line; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
      if (!ingroup) star = 0
      ingroup = 1; if (v == "*") star = 1; next
    }
    low ~ /^[[:space:]]*disallow[[:space:]]*:/ {
      ingroup = 0; v = line; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
      if (star && v != "") print v; next
    }
    low ~ /^[[:space:]]*[a-z-]+[[:space:]]*:/ { ingroup = 0 }
  ' > "$WORK/disallow"
fi

# The page you asked for is always checked, then we follow links
process_page "$eff"

while [ ${#PAGES[@]} -lt "$MAX_PAGES" ]; do
  next=$(dequeue) || break
  if blocked_by_robots "$next"; then SKIPPED_ROBOTS=$((SKIPPED_ROBOTS+1)); continue; fi
  process_page "$next" && sleep "$DELAY"
done

REMAINING=$(cat "$WORK/q_top" "$WORK/q_pri" "$WORK/q_rest" | grep -c .)
PAGE_COUNT=${#PAGES[@]}

echo ""
echo "Checked $PAGE_COUNT page(s). Analysing..."

# =========================
# ANALYSE EACH PAGE
# =========================
PRIV_ANY=0; PRIV_MISSING=""
CMP=""; CMP_PAGE=""; COOKIE_MENTION=0
FORM_PAGES=""; FORM_NOCONSENT=""; PRETICK=""; FORM_INSECURE=""
MIXED=""
RIGHTS_PAGE=""
PRIVACY_PAGE=""; PRIVACY_FILE=""

CMP_RE='cookiebot|onetrust|cookieyes|cookie-script|termly|iubenda|complianz|usercentrics|quantcast|didomi|osano|trustarc|civic ?uk|cookiefirst|klaro|cookie-?law-?info|cookie-?consent|cookie-?banner|cookie-?notice'
RIGHTS_RE='access your (data|information)|delete your (data|information)|data rights|your rights|right to erasure|right of access|right to be forgotten|data subject|subject access'
Q="[\"']?"

T_NAME=("Google Analytics / Tag Manager" "Facebook (Meta) Pixel" "Hotjar" "Microsoft Clarity" "LinkedIn Insight Tag" "TikTok Pixel" "X (Twitter) Pixel" "Pinterest Tag" "Google Ads")
T_RE=('google-analytics\.com|googletagmanager\.com|gtag\(' 'connect\.facebook\.net|fbq\(' 'hotjar' 'clarity\.ms' 'snap\.licdn\.com|_linkedin_partner_id' 'analytics\.tiktok\.com|ttq\.load' 'static\.ads-twitter\.com|twq\(' 'pintrk|s\.pinimg\.com/ct' 'googleadservices\.com|googlesyndication\.com')
T_PAGES=()
TRACKER_PAGES=""

for i in "${!PAGES[@]}"; do
  url=${PAGES[$i]}
  f="$WORK/flat_$i"
  tr '\n\r\t' '   ' < "${PAGE_FILES[$i]}" > "$f"

  # Privacy policy link on every page
  if grep -qi 'privacy' "$f"; then PRIV_ANY=1; else PRIV_MISSING="$PRIV_MISSING$url"$'\n'; fi

  # Is this page the privacy policy itself?
  if [ -z "$PRIVACY_PAGE" ] && printf '%s' "$(path_of "$url")" | grep -qiE 'privacy|data-?protection|gdpr'; then
    PRIVACY_PAGE=$url; PRIVACY_FILE=$f
  fi

  # Cookie consent tool
  if [ -z "$CMP" ]; then
    m=$(grep -oiE "$CMP_RE" "$f" | head -n 1)
    [ -n "$m" ] && { CMP=$m; CMP_PAGE=$url; }
  fi
  grep -qi 'cookie' "$f" && COOKIE_MENTION=1

  # Data rights
  [ -z "$RIGHTS_PAGE" ] && grep -qiE "$RIGHTS_RE" "$f" && RIGHTS_PAGE=$url

  # Trackers
  found_tracker=0
  for k in "${!T_RE[@]}"; do
    if grep -qiE "${T_RE[$k]}" "$f"; then
      T_PAGES[$k]="${T_PAGES[$k]}$url"$'\n'
      found_tracker=1
    fi
  done
  [ $found_tracker -eq 1 ] && TRACKER_PAGES="$TRACKER_PAGES$url"$'\n'

  # Insecure (http://) images/scripts on secure pages
  if [ "$(scheme_of "$url")" = "https" ] && grep -qiE "src[[:space:]]*=[[:space:]]*${Q}http://" "$f"; then
    MIXED="$MIXED$url"$'\n'
  fi

  # Forms that collect personal details
  awk '{ s = tolower($0)
         while ((i = index(s, "<form")) > 0) {
           s = substr(s, i); j = index(s, "</form>")
           if (j == 0) { print s; break }
           print substr(s, 1, j + 6); s = substr(s, j + 7)
         } }' "$f" > "$WORK/forms_$i"

  pf=0; nc=0; pt=0; ins=0
  while IFS= read -r form; do
    printf '%s' "$form" | grep -qE "type=${Q}(email|tel|password)|name=${Q}[a-z0-9_-]*(email|phone|mobile|name|surname|address|postcode|zip|dob|birth)|<textarea" || continue
    pf=1
    printf '%s' "$form" | grep -qE 'privacy|consent|i agree|gdpr|data protection|personal data|how we use' || nc=1
    printf '%s' "$form" | grep -oE '<input[^>]*>' | grep 'checkbox' | grep -qE '[[:space:]]checked([[:space:]=/>]|$)' && pt=1
    printf '%s' "$form" | grep -qE "action=${Q}http://" && ins=1
  done < "$WORK/forms_$i"
  [ $pf -eq 1 ]  && FORM_PAGES="$FORM_PAGES$url"$'\n'
  [ $nc -eq 1 ]  && FORM_NOCONSENT="$FORM_NOCONSENT$url"$'\n'
  [ $pt -eq 1 ]  && PRETICK="$PRETICK$url"$'\n'
  [ $ins -eq 1 ] && FORM_INSECURE="$FORM_INSECURE$url"$'\n'
done

# Site-wide checks (homepage response headers & HTTPS)
curl -sL --max-time 20 -A "$UA" -D "$WORK/headers_all" -o /dev/null "$ORIGIN/" 2>/dev/null
awk '/^HTTP\//{ buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$WORK/headers_all" 2>/dev/null | tr -d '\r' > "$WORK/headers"
has_header() { grep -qiE "^$1:" "$WORK/headers"; }

HTTPS_CODE=$(curl -s --max-time 15 -A "$UA" -o /dev/null -w '%{http_code}' "https://$HOST/" 2>/dev/null)
HTTP_REDIRECT=$(curl -s --max-time 15 -A "$UA" -o /dev/null -w '%{redirect_url}' "http://$HOST/" 2>/dev/null)

# =========================
# RESULTS
# status = pass | warn | fail | info
# =========================
R_SECTION=(); R_STATUS=(); R_TITLE=(); R_DETAIL=(); R_FIX=(); R_PAGES=()
SECTIONS=()
PASS=0; WARN=0; FAIL=0; INFO=0

add_result() {  # section status title detail fix [pages]
  local n=${#SECTIONS[@]}
  if [ "$n" -eq 0 ] || [ "${SECTIONS[$((n-1))]}" != "$1" ]; then SECTIONS+=("$1"); fi
  R_SECTION+=("$1"); R_STATUS+=("$2"); R_TITLE+=("$3")
  R_DETAIL+=("$4");  R_FIX+=("$5");    R_PAGES+=("$6")
  case $2 in
    pass) PASS=$((PASS+1)) ;;
    warn) WARN=$((WARN+1)) ;;
    fail) FAIL=$((FAIL+1)) ;;
    *)    INFO=$((INFO+1)) ;;
  esac
}

plural() { if [ "$1" -eq 1 ]; then echo "1 page"; else echo "$1 pages"; fi; }
# "1 page has" / "3 pages have" etc.
pv() { if [ "$1" -eq 1 ]; then echo "1 page $2"; else echo "$1 pages $3"; fi; }

# --- Secure connection
case "$HTTPS_CODE" in
  ''|000)
    add_result "Secure Connection" fail "Website does not load over HTTPS" \
      "We couldn't reach your site securely. Without HTTPS, anything visitors type (names, emails, passwords) could be intercepted." \
      "Install an SSL certificate (free from Let's Encrypt or most hosts) and redirect all traffic to https://." ;;
  *)
    add_result "Secure Connection" pass "Website uses HTTPS" \
      "Your site loads securely over HTTPS, so information sent between visitors and your site is encrypted." ""
    if [[ $HTTP_REDIRECT =~ ^https:// ]]; then
      add_result "Secure Connection" pass "Insecure visits are redirected" \
        "Anyone who types http:// is automatically sent to the secure version of your site." ""
    else
      add_result "Secure Connection" warn "Insecure visits aren't redirected" \
        "Your site can still be opened over insecure http://. Visitors who land there won't be protected." \
        "Set your host or server to redirect all http:// traffic to https://."
    fi ;;
esac

n=$(count_lines "$MIXED")
if [ "$n" -gt 0 ]; then
  add_result "Secure Connection" warn "Insecure content on secure pages" \
    "$(pv "$n" loads load) images or scripts over insecure http://. This weakens the protection HTTPS gives." \
    "Change those image and script links to start with https://." "$MIXED"
fi

# --- Privacy policy
n=$(count_lines "$PRIV_MISSING")
if [ $PRIV_ANY -eq 0 ]; then
  add_result "Privacy Policy" fail "No privacy policy found" \
    "GDPR requires you to tell people what data you collect, why, and how long you keep it. We couldn't find a privacy policy on any of the $PAGE_COUNT pages we checked." \
    "Publish a privacy policy and link to it in your site footer so it appears on every page."
elif [ "$n" -gt 0 ]; then
  add_result "Privacy Policy" warn "Privacy policy isn't linked on every page" \
    "We found a privacy policy, but $(pv "$n" "doesn't" "don't") link to it. It should be easy to find wherever someone is on your site." \
    "Put the privacy policy link in your site footer so it appears on every page." "$PRIV_MISSING"
else
  add_result "Privacy Policy" pass "Privacy policy linked on every page" \
    "Every page we checked links to or mentions your privacy policy." ""
fi

if [ -n "$PRIVACY_FILE" ]; then
  MISSING_ITEMS=()
  grep -qiE 'mailto:|[a-z0-9._%+-]+@[a-z0-9-]+\.[a-z.]+|contact (us|form|details)|get in touch' "$PRIVACY_FILE" || MISSING_ITEMS+=("who you are and how to contact you")
  grep -qiE 'personal (data|information)|information (we|that we) collect|data we collect|we collect' "$PRIVACY_FILE" || MISSING_ITEMS+=("what personal data you collect")
  grep -qiE 'lawful basis|legal basis|legitimate interest|basis (for|of) processing' "$PRIVACY_FILE" || MISSING_ITEMS+=("your legal reason (lawful basis) for using it")
  grep -qiE 'retain|retention|how long|kept for|keep your (data|information)' "$PRIVACY_FILE" || MISSING_ITEMS+=("how long you keep it")
  grep -qiE 'third part|share your|sharing|disclose' "$PRIVACY_FILE" || MISSING_ITEMS+=("who you share it with")
  grep -qiE 'ico\.org\.uk|information commissioner|supervisory authority|complain' "$PRIVACY_FILE" || MISSING_ITEMS+=("people's right to complain to the ICO")

  nm=${#MISSING_ITEMS[@]}
  list=""
  for item in "${MISSING_ITEMS[@]}"; do list="$list; $item"; done
  list=${list#; }
  if [ "$nm" -eq 0 ]; then
    add_result "Privacy Policy" pass "Privacy policy covers the key topics" \
      "Your privacy policy mentions contact details, what data you collect, your lawful basis, how long you keep data, who you share it with, and the right to complain." "" "$PRIVACY_PAGE"$'\n'
  else
    [ "$nm" -le 2 ] && st=warn || st=fail
    add_result "Privacy Policy" "$st" "Privacy policy may be missing key information" \
      "We read your privacy policy and couldn't find: $list. GDPR says a privacy policy should explain these." \
      "Add a short section to your privacy policy for each missing topic. The ICO website has a free privacy notice template." "$PRIVACY_PAGE"$'\n'
  fi
elif [ $PRIV_ANY -eq 1 ]; then
  add_result "Privacy Policy" info "Privacy policy contents not checked" \
    "We couldn't open your privacy policy page (it may be hosted on another website, or it was beyond the page limit), so we didn't check what it says." ""
fi

# --- Cookie consent
if [ -n "$CMP" ]; then
  add_result "Cookie Consent" pass "Cookie consent tool detected" \
    "A cookie consent banner appears to be in place (we spotted \"$CMP\")." "" "$CMP_PAGE"$'\n'
elif [ $COOKIE_MENTION -eq 1 ]; then
  add_result "Cookie Consent" warn "Cookies mentioned, but no clear consent banner" \
    "Your site talks about cookies, but we couldn't confirm a proper consent banner. Some banners load later via JavaScript and may not show up in this check, so double-check in your browser." \
    "Make sure visitors can accept or reject non-essential cookies before any are set, and that 'Reject' is as easy as 'Accept'."
else
  add_result "Cookie Consent" fail "No cookie consent found" \
    "We found no cookie notice or consent tool on any page. If your site uses any non-essential cookies, you need visitors' permission first." \
    "Add a cookie consent banner (e.g. CookieYes, Cookiebot or Complianz) that blocks non-essential cookies until visitors agree."
fi

# --- Forms
nf=$(count_lines "$FORM_PAGES")
if [ "$nf" -eq 0 ]; then
  add_result "Forms & Consent" info "No forms collecting personal details" \
    "None of the pages we checked have forms asking for things like names, emails or phone numbers." ""
else
  n=$(count_lines "$FORM_NOCONSENT")
  if [ "$n" -eq 0 ]; then
    add_result "Forms & Consent" pass "Forms include privacy information" \
      "All $(plural "$nf") with forms that collect personal details include privacy or consent wording." "" "$FORM_PAGES"
  else
    add_result "Forms & Consent" warn "Forms without a privacy notice" \
      "$(pv "$n" has have) forms that collect personal details but no privacy or consent wording. People should know how their details will be used before they submit them." \
      "Add a short line to each form explaining how the data is used, with a link to your privacy policy." "$FORM_NOCONSENT"
  fi
  n=$(count_lines "$PRETICK")
  if [ "$n" -gt 0 ]; then
    add_result "Forms & Consent" warn "Checkboxes ticked by default" \
      "$(pv "$n" has have) a form with a checkbox that's already ticked. If it's for marketing or consent, GDPR says it must start unticked so people actively choose." \
      "Make sure any consent or marketing checkbox starts unticked." "$PRETICK"
  fi
  n=$(count_lines "$FORM_INSECURE")
  if [ "$n" -gt 0 ]; then
    add_result "Forms & Consent" fail "Forms send data insecurely" \
      "$(pv "$n" has have) forms that send information over insecure http://, so it could be intercepted." \
      "Change the form's action address to use https://." "$FORM_INSECURE"
  fi
fi

# --- Tracking
TRACKER_LIST=""
for k in "${!T_NAME[@]}"; do
  [ -n "${T_PAGES[$k]}" ] && TRACKER_LIST="$TRACKER_LIST, ${T_NAME[$k]} ($(plural "$(count_lines "${T_PAGES[$k]}")"))"
done
TRACKER_LIST=${TRACKER_LIST#, }
nt=$(count_lines "$TRACKER_PAGES")
if [ "$nt" -eq 0 ]; then
  add_result "Tracking" pass "No common tracking tools found" \
    "We didn't spot common tracking tools such as Google Analytics or the Facebook Pixel on any page." ""
elif [ -n "$CMP" ]; then
  add_result "Tracking" pass "Tracking found, with a consent tool" \
    "Tracking tools found: $TRACKER_LIST. A consent tool is also present. Check that tracking only starts after visitors click 'Accept'." "" "$TRACKER_PAGES"
else
  add_result "Tracking" fail "Tracking without consent" \
    "Tracking tools found: $TRACKER_LIST, but no consent tool to ask permission first. Under GDPR, analytics and advertising trackers need consent before they run." \
    "Add a cookie consent banner and set it to block these scripts until visitors accept." "$TRACKER_PAGES"
fi

# --- Security headers
if has_header "Content-Security-Policy"; then
  add_result "Security" pass "Content-Security-Policy is set" \
    "This header helps stop malicious scripts from running on your site and stealing visitor data." ""
else
  add_result "Security" warn "Content-Security-Policy is missing" \
    "This header helps stop malicious scripts from stealing visitor data. It isn't strictly required by GDPR, but GDPR does expect 'appropriate security'." \
    "Ask your developer or host to add a Content-Security-Policy header."
fi
if has_header "Strict-Transport-Security"; then
  add_result "Security" pass "HSTS is enabled" \
    "Browsers are told to always use a secure connection to your site." ""
else
  add_result "Security" warn "HSTS is missing" \
    "Without HSTS, a visitor's first connection could be downgraded to an insecure one." \
    "Add a Strict-Transport-Security header (most hosts and Cloudflare offer this as a one-click setting)."
fi

# --- Data rights
if [ -n "$RIGHTS_PAGE" ]; then
  add_result "Your Visitors' Rights" pass "Data rights are explained" \
    "Your site explains people's rights over their data (such as seeing or deleting it)." "" "$RIGHTS_PAGE"$'\n'
else
  add_result "Your Visitors' Rights" fail "No mention of data rights" \
    "People have the right to see, correct and delete the data you hold on them. We couldn't find this explained on any page we checked." \
    "In your privacy policy, explain how people can access, correct, delete or export their data, and give a contact email for requests."
fi

# =========================
# SCORE
# =========================
TOTAL=$((PASS+WARN+FAIL))
if [ $TOTAL -gt 0 ]; then SCORE=$(( (PASS*100 + WARN*50) / TOTAL )); else SCORE=0; fi

if   [ $SCORE -ge 80 ]; then VERDICT="Looking good";    VERDICT_TEXT="Your site covers most of the basics. Review any remaining items below."; VCLASS="good"
elif [ $SCORE -ge 50 ]; then VERDICT="Needs some work"; VERDICT_TEXT="A few important things are missing. Start with the top priorities below."; VCLASS="ok"
else                         VERDICT="At risk";         VERDICT_TEXT="Several key GDPR basics are missing. Fix the top priorities below first."; VCLASS="bad"
fi

DATE=$(date "+%d %B %Y, %H:%M")
OUTPUT="gdpr_report_${BASE_DOMAIN//[^A-Za-z0-9.-]/_}.${FORMAT}"

NOTES=""
[ "$MAX_PAGES" -eq "$PAGE_COUNT" ] && [ "$REMAINING" -gt 0 ] && NOTES="$NOTES We reached the $MAX_PAGES-page limit; at least $REMAINING more pages weren't checked."
[ "$SKIPPED_ROBOTS" -gt 0 ] && NOTES="$NOTES $SKIPPED_ROBOTS page(s) were skipped because the site's robots.txt asks crawlers not to visit them."
[ "$FAILED" -gt 0 ] && NOTES="$NOTES $FAILED link(s) couldn't be loaded."
NOTES=${NOTES# }

# Issues per page (for the page list)
page_tags() {  # $1 = url. Prints tags separated by "|"
  local t=""
  in_list "$1" "$PRIV_MISSING"   && t="$t|No privacy link"
  in_list "$1" "$FORM_NOCONSENT" && t="$t|Form without privacy notice"
  in_list "$1" "$PRETICK"        && t="$t|Pre-ticked checkbox"
  in_list "$1" "$FORM_INSECURE"  && t="$t|Insecure form"
  in_list "$1" "$MIXED"          && t="$t|Insecure content"
  [ -z "$CMP" ] && in_list "$1" "$TRACKER_PAGES" && t="$t|Tracking without consent"
  printf '%s' "${t#|}"
}

# =========================
# REPORT WRITERS
# =========================
esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

text_pages() {  # $1 = pages list, $2 = prefix
  local p c=0 total
  total=$(count_lines "$1")
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    c=$((c+1))
    if [ $c -gt 10 ]; then echo "$2...and $((total-10)) more"; break; fi
    echo "$2$(show_path "$p")"
  done <<< "$1"
}

write_txt() {
  {
    echo "GDPR AUDIT REPORT"
    echo "Website: $ORIGIN"
    echo "Date: $DATE"
    echo "Pages checked: $PAGE_COUNT"
    echo "Score: $SCORE/100 - $VERDICT"
    for s in "${SECTIONS[@]}"; do
      echo -e "\n==== $s ====\n"
      for i in "${!R_TITLE[@]}"; do
        [ "${R_SECTION[$i]}" != "$s" ] && continue
        case ${R_STATUS[$i]} in pass) m="✔";; fail) m="✘";; warn) m="!";; *) m="i";; esac
        echo "$m ${R_TITLE[$i]}"
        echo "   ${R_DETAIL[$i]}"
        [ -n "${R_FIX[$i]}" ] && echo "   How to fix: ${R_FIX[$i]}"
        if [ -n "${R_PAGES[$i]}" ]; then echo "   Pages:"; text_pages "${R_PAGES[$i]}" "     - "; fi
      done
    done
    echo -e "\n==== Pages Checked ====\n"
    for p in "${PAGES[@]}"; do
      tags=$(page_tags "$p")
      if [ -n "$tags" ]; then echo "! $(show_path "$p")  [${tags//|/, }]"; else echo "✔ $(show_path "$p")"; fi
    done
    echo -e "\n==== Summary ====\n"
    echo "Passed: $PASS   Warnings: $WARN   Failed: $FAIL"
    [ -n "$NOTES" ] && echo -e "\nNote: $NOTES"
    echo -e "\nThis is an automated check and is not legal advice."
  } > "$OUTPUT"
}

write_md() {
  {
    echo "# GDPR Audit Report"
    echo ""
    echo "**Website:** $ORIGIN  "
    echo "**Date:** $DATE  "
    echo "**Pages checked:** $PAGE_COUNT  "
    echo "**Score:** $SCORE/100 ($VERDICT)"
    for s in "${SECTIONS[@]}"; do
      echo -e "\n## $s\n"
      for i in "${!R_TITLE[@]}"; do
        [ "${R_SECTION[$i]}" != "$s" ] && continue
        case ${R_STATUS[$i]} in pass) m="✅";; fail) m="❌";; warn) m="⚠️";; *) m="ℹ️";; esac
        echo "- $m **${R_TITLE[$i]}**: ${R_DETAIL[$i]}"
        [ -n "${R_FIX[$i]}" ] && echo "  - *How to fix:* ${R_FIX[$i]}"
        if [ -n "${R_PAGES[$i]}" ]; then echo "  - *Pages:*"; text_pages "${R_PAGES[$i]}" "    - "; fi
      done
    done
    echo -e "\n## Pages checked\n"
    echo "| Page | Issues |"
    echo "|---|---|"
    for p in "${PAGES[@]}"; do
      tags=$(page_tags "$p")
      if [ -n "$tags" ]; then cell="⚠️ ${tags//|/, }"; else cell="✅ None found"; fi
      echo "| [$(show_path "$p")]($p) | $cell |"
    done
    echo -e "\n## Summary\n"
    echo "Passed: $PASS | Warnings: $WARN | Failed: $FAIL"
    [ -n "$NOTES" ] && echo -e "\n*Note: $NOTES*"
    echo -e "\n*This is an automated check and is not legal advice.*"
  } > "$OUTPUT"
}

html_page_list() {  # $1 = pages list
  local p out="" c
  c=$(count_lines "$1")
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    out="$out<li><a href=\"$(esc "$p")\" target=\"_blank\" rel=\"noopener\">$(esc "$(show_path "$p")")</a></li>"
  done <<< "$1"
  if [ "$c" -eq 1 ]; then
    printf '<details class="pages"><summary>Show page</summary><ul>%s</ul></details>' "$out"
  else
    printf '<details class="pages"><summary>Show %s pages</summary><ul>%s</ul></details>' "$c" "$out"
  fi
}

write_html() {
  local cards="" priorities="" pagerows="" st icon label tags t clean_count=0
  for s in "${SECTIONS[@]}"; do
    cards+="<section class=\"group\"><h2>$(esc "$s")</h2>"
    for i in "${!R_TITLE[@]}"; do
      [ "${R_SECTION[$i]}" != "$s" ] && continue
      st="${R_STATUS[$i]}"
      case $st in
        pass) icon="✓"; label="Passed" ;;
        fail) icon="✕"; label="Action needed" ;;
        warn) icon="!"; label="Worth fixing" ;;
        *)    icon="i"; label="For info" ;;
      esac
      cards+="<article class=\"card st-$st\"><div class=\"icon\">$icon</div><div class=\"body\">"
      cards+="<div class=\"row\"><h3>$(esc "${R_TITLE[$i]}")</h3><span class=\"badge\">$label</span></div>"
      cards+="<p>$(esc "${R_DETAIL[$i]}")</p>"
      [ -n "${R_FIX[$i]}" ] && cards+="<p class=\"fix\"><strong>How to fix:</strong> $(esc "${R_FIX[$i]}")</p>"
      [ -n "${R_PAGES[$i]}" ] && cards+="$(html_page_list "${R_PAGES[$i]}")"
      cards+="</div></article>"
      [ "$st" = "fail" ] && priorities+="<li><strong>$(esc "${R_TITLE[$i]}")</strong> &mdash; $(esc "${R_FIX[$i]}")</li>"
    done
    cards+="</section>"
  done

  for p in "${PAGES[@]}"; do
    tags=$(page_tags "$p")
    pagerows+="<li class=\"${tags:+has-issues}\"><a href=\"$(esc "$p")\" target=\"_blank\" rel=\"noopener\">$(esc "$(show_path "$p")")</a><span class=\"tags\">"
    if [ -z "$tags" ]; then
      pagerows+="<span class=\"tag ok\">No issues found</span>"
      clean_count=$((clean_count+1))
    else
      local IFS='|'
      for t in $tags; do pagerows+="<span class=\"tag\">$(esc "$t")</span>"; done
      unset IFS
    fi
    pagerows+="</span></li>"
  done

  local prio_block=""
  [ -n "$priorities" ] && prio_block="<section class=\"prio\"><h2>Top priorities</h2><ol>$priorities</ol></section>"
  local notes_html=""
  [ -n "$NOTES" ] && notes_html="<p class=\"note\">$(esc "$NOTES")</p>"

  cat > "$OUTPUT" <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GDPR Report &ndash; $(esc "$HOST")</title>
<style>
:root{--bg:#f5f6f8;--card:#fff;--text:#1d2330;--muted:#5b6475;--line:#e3e6ec;--link:#3557c4;
--pass:#1a8f5a;--pass-bg:#e6f5ee;--warn:#b26a00;--warn-bg:#fff3e0;--fail:#c62828;--fail-bg:#fdecea;--info:#3557c4;--info-bg:#e8edfb}
@media (prefers-color-scheme:dark){:root{--bg:#12151b;--card:#1b2029;--text:#e7eaf0;--muted:#9aa3b5;--line:#2b3240;--link:#8aa6ff;
--pass-bg:#173326;--warn-bg:#3a2a10;--fail-bg:#3d1a1a;--info-bg:#1c2647;--pass:#4cc38a;--warn:#f0a43a;--fail:#ff6b6b;--info:#7d9bff}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.55 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
a{color:var(--link)}
.wrap{max-width:860px;margin:0 auto;padding:32px 16px 64px}
header{display:flex;gap:28px;align-items:center;background:var(--card);border:1px solid var(--line);border-radius:16px;padding:28px;flex-wrap:wrap}
.ring{--p:${SCORE};width:132px;height:132px;border-radius:50%;flex:none;display:grid;place-items:center;
background:conic-gradient(var(--c) calc(var(--p)*1%),var(--line) 0)}
.ring.good{--c:var(--pass)}.ring.ok{--c:var(--warn)}.ring.bad{--c:var(--fail)}
.ring div{width:104px;height:104px;border-radius:50%;background:var(--card);display:grid;place-items:center;text-align:center}
.ring b{font-size:34px;line-height:1}.ring small{color:var(--muted);font-size:12px}
.head{flex:1;min-width:240px}
.eyebrow{color:var(--muted);font-size:13px;text-transform:uppercase;letter-spacing:.06em;margin:0}
h1{margin:4px 0 6px;font-size:26px;word-break:break-all}
.verdict{font-weight:600;margin:0}.verdict.good{color:var(--pass)}.verdict.ok{color:var(--warn)}.verdict.bad{color:var(--fail)}
.head p{margin:4px 0;color:var(--muted)}
.chips{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}
.chip{padding:4px 12px;border-radius:999px;font-size:14px;font-weight:600}
.c-pass{background:var(--pass-bg);color:var(--pass)}.c-warn{background:var(--warn-bg);color:var(--warn)}.c-fail{background:var(--fail-bg);color:var(--fail)}.c-info{background:var(--info-bg);color:var(--info)}
.toolbar{display:flex;gap:8px;justify-content:flex-end;margin:20px 0 4px;flex-wrap:wrap}
button{font:inherit;font-size:14px;padding:8px 14px;border-radius:8px;border:1px solid var(--line);background:var(--card);color:var(--text);cursor:pointer}
button:hover{border-color:var(--muted)}
.prio{background:var(--fail-bg);border-radius:16px;padding:18px 24px;margin-top:20px}
.prio h2{margin:0 0 8px;font-size:18px;color:var(--fail)}.prio ol{margin:0;padding-left:20px}.prio li{margin:6px 0}
.group h2,.pagelist h2{font-size:18px;margin:28px 0 10px}
.card{display:flex;gap:16px;background:var(--card);border:1px solid var(--line);border-left:5px solid var(--sc);border-radius:12px;padding:16px 18px;margin-bottom:10px}
.st-pass{--sc:var(--pass);--sb:var(--pass-bg)}.st-warn{--sc:var(--warn);--sb:var(--warn-bg)}
.st-fail{--sc:var(--fail);--sb:var(--fail-bg)}.st-info{--sc:var(--info);--sb:var(--info-bg)}
.icon{flex:none;width:32px;height:32px;border-radius:50%;background:var(--sb);color:var(--sc);display:grid;place-items:center;font-weight:700}
.body{flex:1;min-width:0}.row{display:flex;justify-content:space-between;gap:10px;align-items:baseline;flex-wrap:wrap}
.card h3{margin:0;font-size:16px}.card p{margin:6px 0 0;color:var(--muted)}
.badge{font-size:12px;font-weight:600;padding:2px 10px;border-radius:999px;background:var(--sb);color:var(--sc);white-space:nowrap}
.fix{background:var(--bg);border-radius:8px;padding:8px 12px;color:var(--text)!important}
details.pages{margin-top:8px;font-size:14px}
details.pages summary{cursor:pointer;color:var(--link);font-weight:600}
details.pages ul{margin:6px 0 0;padding-left:20px}
details.pages li{word-break:break-all}
.pagelist ul{list-style:none;margin:0;padding:0;background:var(--card);border:1px solid var(--line);border-radius:12px}
.pagelist li{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:10px 16px;border-top:1px solid var(--line);flex-wrap:wrap}
.pagelist li:first-child{border-top:0}
.pagelist a{word-break:break-all}
.tags{display:flex;gap:6px;flex-wrap:wrap}
.tag{font-size:12px;font-weight:600;padding:2px 10px;border-radius:999px;background:var(--warn-bg);color:var(--warn)}
.tag.ok{background:var(--pass-bg);color:var(--pass)}
.issues-only .st-pass,.issues-only .st-info,.issues-only .pagelist li:not(.has-issues){display:none}
.note{background:var(--info-bg);color:var(--text);border-radius:10px;padding:10px 14px;font-size:14px;margin-top:20px}
footer{margin-top:36px;color:var(--muted);font-size:13px;text-align:center}
@media print{.toolbar{display:none}body{background:#fff}details.pages{display:none}}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="ring $VCLASS"><div><span><b>$SCORE</b><br><small>out of 100</small></span></div></div>
    <div class="head">
      <p class="eyebrow">GDPR website audit</p>
      <h1>$(esc "$HOST")</h1>
      <p class="verdict $VCLASS">$VERDICT</p>
      <p>$VERDICT_TEXT</p>
      <div class="chips">
        <span class="chip c-info">$PAGE_COUNT pages checked</span>
        <span class="chip c-pass">$PASS passed</span>
        <span class="chip c-warn">$WARN worth fixing</span>
        <span class="chip c-fail">$FAIL action needed</span>
      </div>
    </div>
  </header>

  <div class="toolbar">
    <button onclick="document.body.classList.toggle('issues-only');this.textContent=document.body.classList.contains('issues-only')?'Show all checks':'Show issues only'">Show issues only</button>
    <button onclick="window.print()">Print / Save as PDF</button>
  </div>

  $notes_html
  $prio_block
  $cards

  <section class="pagelist">
    <h2>Pages checked ($clean_count of $PAGE_COUNT with no issues found)</h2>
    <ul>$pagerows</ul>
  </section>

  <footer>
    Checked $(esc "$ORIGIN") on $DATE.<br>
    This is an automated check and is not legal advice. Some things (like banners loaded by JavaScript) may not be detected.
  </footer>
</div>
</body>
</html>
EOF
}

open_report() {
  case "$(uname -s)" in
    Darwin) open "$OUTPUT" ;;
    MINGW*|MSYS*|CYGWIN*) start "" "$OUTPUT" 2>/dev/null || cmd.exe //c start "" "$OUTPUT" ;;
    *)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        if command -v wslview >/dev/null 2>&1; then wslview "$OUTPUT"
        else explorer.exe "$(wslpath -w "$OUTPUT")" >/dev/null 2>&1; fi
      elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$OUTPUT" >/dev/null 2>&1 &
      else
        echo "Open $OUTPUT in your browser to view the report."
      fi ;;
  esac
}

case $FORMAT in
  txt)  write_txt ;;
  md)   write_md ;;
  html) write_html ;;
esac

echo ""
echo "Audit complete! Score: $SCORE/100 ($VERDICT)"
echo "Pages checked: $PAGE_COUNT"
echo "Passed: $PASS   Warnings: $WARN   Failed: $FAIL"
[ -n "$NOTES" ] && echo "Note: $NOTES"
echo "Report saved as: $OUTPUT"

if [ "$FORMAT" = "html" ]; then
  echo "Opening report in your browser..."
  open_report
fi
