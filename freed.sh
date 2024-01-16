#!/usr/bin/bash -
#
# freed.sh - free domain shell script
# Find lookalike DOMAIN created in the last PERIOD and send result to RECIPIENT.
#
SCRIPT=${0##*/}
STODAY=$(date +%s)

# SMTP configuration
SMTP_USER="your.gmail.account@gmail.com"
SMTP_PASS="your app password from gmail"
SMTP_SERV="smtp.gmail.com:587"

# ACE prefix filter in IDNs
XN="| grep -Ev '^xn--'"

# die gracefully
function die {
    echo "$SCRIPT: $*"
    echo "Try \`$SCRIPT -h' for more information."
    exit 1
} >&2

# depends on `command'
function depends {
    if (( $# == 1 )); then
        echo "$SCRIPT: depends on \`$1'"
        echo "Install \`$1' and try again."
    else
        echo "$SCRIPT depends on the following:"
        for command; do
            echo "  - $command"
        done
        echo "Install them and try again."
    fi
    exit 1
} >&2

# usage statement
function usage {
cat <<-EOF
Usage: $SCRIPT [OPTION]... [DOMAIN]
Find lookalike DOMAIN created in the last PERIOD and send result to RECIPIENT.

positional argument
  DOMAIN        target domain name

options
  -d DEFANG     defang character/string, e.g. '·' (U+00B7), '[.]' (default)
  -e ENGINE     permutation engine, e.g. dnstwist, urlcrazy, urlinsane (default)
  -h            display this help and exit
  -i INCLUDES   include domain(s) separated by comma in the operation
  -k            keep HTML result and do not send email
  -p PERIOD     time period to look back, e.g. 30d, 24h (default)
  -s RECIPIENT  send email to recipient, e.g. <$SMTP_USER> (default)
  -t            display thumbnail in HTML result
  -x            display internationalized domain name (IDN) in HTML result
EOF
exit 0
} >&2

# parse options
while getopts ":d:e:hi:kp:s:tx" opt; do
    case $opt in
    d)
        DEFANG=$OPTARG
        ;;
    e)
        ENGINE=$OPTARG
        ;;
    h)
        usage
        ;;
    i)
        INCLUDES=$OPTARG
        ;;
    k)
        KEEP=1
        ;;
    p)
        PERIOD=$OPTARG
        ;;
    s)
        RECIPIENT=$OPTARG
        ;;
    t)
        THUMBNAIL=1
        NODEJS=$(which node) || depends nodejs puppeteer puppeteer-extra puppeteer-extra-plugin-stealth
        ;;
    x)
        XN=
        IDN=$(which idn) || depends "idn"
        ;;
    :)
        die "option requires an argument -- '$OPTARG'"
        ;;
    \?)
        die "invalid option -- '$OPTARG'"
        ;;
    esac
done
shift $((OPTIND - 1))

# argument check and default values
DEFANG=${DEFANG:=[.]}
DOMAIN=${1:-result}; shift
DOMAIN=${DOMAIN,,}
DOMAIN_REGEX='^(result|[^-][a-z0-9-]{,62}\.[a-z]{2,3}(\.[a-z]{2})?)$'
[[ ! "$DOMAIN" =~ $DOMAIN_REGEX ]] && die "invalid domain name"
ENGINE=${ENGINE:=urlinsane}
if [[ "$INCLUDES" ]]; then
    INCLUDES=${INCLUDES,,}
    readarray -d, -t includes < <(printf "%s" "$INCLUDES")
    for include in "${includes[@]}"; do
        [[ ! "$include" =~ $DOMAIN_REGEX ]] && die "invalid domain name"
        PIPE=${INCLUDE_REGEX:+|}
        INCLUDE_REGEX="${INCLUDE_REGEX}${PIPE}^${include}$"
    done
    INCLUDES=" || [[ \$domain =~ ($INCLUDE_REGEX) ]]"
fi
PERIOD=${PERIOD:=24h}
RECIPIENT=${RECIPIENT:=$SMTP_USER}

# time arithmetic
[[ ! $PERIOD =~ ^[0-9]+[dDhH]$ ]] && die "invalid time period"
TIME=${PERIOD%?}
UNIT=${PERIOD#"$TIME"}
case $UNIT in
    [dD]) SDELTA=$((TIME * 24 * 60 * 60)) ;;
    [hH]) SDELTA=$((TIME * 60 * 60)) ;;
esac
START=$((STODAY - SDELTA))

# iso-8601 date/time format
function timestamp {
    date +%Y-%m-%dT%H:%M:%SZ
}

# dependency checks
# -----------------
# dig - `sudo apt-get install bind9-dnsutils`
DIG=$(which dig) || depends "dig"

# dnstwist - `sudo apt-get install dnstwist`
DNSTWIST=$(which dnstwist) || depends "dnstwist"

# parallel - `sudo apt-get install parallel`
PARALLEL=$(which parallel) || depends "parallel"

# sendemail - `sudo apt-get install sendemail`
SENDEMAIL=$(which sendemail) || depends "sendemail"

# urlcrazy - `sudo apt-get install urlcrazy`
URLCRAZY=$(which urlcrazy) || depends "urlcrazy"

# urlinsane - `sudo apt-get install urlinsane``
URLINSANE=$(which urlinsane) || depends "urlinsane"

# whois - `sudo apt-get install whois`
WHOIS=$(which whois) || depends "whois"

# select permutation engine
case "$ENGINE" in

"dnstwist")
EXT=twist

# dnstwist.sh
cat <<-EOF >"${DOMAIN}.${ENGINE}".sh
#!/usr/bin/bash -

DOMAIN=\$1

$DNSTWIST --format list \$DOMAIN \\
| sed 1d \\
$XN >\${DOMAIN}.${EXT}
EOF

chmod +x "${DOMAIN}.${ENGINE}".sh
;;

"urlcrazy")
EXT=crazy

# urlcrazy.sh
cat <<-EOF >"${DOMAIN}.${ENGINE}".sh
#!/usr/bin/bash -

DOMAIN=\$1

ulimit -n 10000

$URLCRAZY -n -r \${DOMAIN} \\
| grep -Ev '[ST]LD' \\
| sed -e '\$d' -e '11,\$!d' \\
| awk '{ print \$NF }' >\${DOMAIN}.${EXT}
EOF

chmod +x "${DOMAIN}.${ENGINE}".sh
;;

"urlinsane")
EXT=insane

# urlinsane.sh
cat <<-EOF >"${DOMAIN}.${ENGINE}".sh
#!/usr/bin/bash -

DOMAIN=\$1

$URLINSANE typo \$DOMAIN -k all -x idna -o csv \\
| grep -Ev '([HP]I|TLD)' \\
| sed '11,\$!d' \\
| awk -F, '{ print \$NF }' \\
$XN >\${DOMAIN}.${EXT}
EOF

chmod +x "${DOMAIN}.${ENGINE}".sh
;;

*) die "invalid permutation engine" ;;

esac

if [[ "$DOMAIN" != "result" ]]; then

    # $SCRIPT started in alert mode.
    echo "[$(timestamp)] $SCRIPT started in alert mode."

    # Running \`$ENGINE' on "${DOMAIN}"...
    echo -n "[$(timestamp)] Running \`${ENGINE}' on \"${DOMAIN}\"..."

    # insert original domain after permutation
    ./"${DOMAIN}.${ENGINE}".sh "${DOMAIN}" && sed -i "1i\\$DOMAIN" "${DOMAIN}.${EXT}"

elif [[ "$DOMAIN" == "result" && "$INCLUDES" ]]; then

    # $SCRIPT started in analysis mode.
    echo "[$(timestamp)] $SCRIPT started in analysis mode."

    # Running without permutation...
    echo -n "[$(timestamp)] Running without permutation..." && echo > "${DOMAIN}.${EXT}"

else

    rm "${DOMAIN}.${ENGINE}".sh
    die "invalid operation"

fi

# insert included domain(s)
for include in "${includes[@]}"; do
    sed -i "1i\\$include" "${DOMAIN}.${EXT}"
done

# dedup
sort -u "${DOMAIN}.${EXT}" >"${DOMAIN}".tmp
mv "${DOMAIN}".tmp "${DOMAIN}.${EXT}" && echo "OK" || echo "FAIL"

# similar.py
cat <<-EOF >similar.py
from difflib import SequenceMatcher
import sys

def similar(a, b):
    return SequenceMatcher(None, a, b).ratio()

print(f"{round(similar(sys.argv[1], sys.argv[2]), 4):.2%}")
EOF

# whois.sh
cat <<-EOF >"${DOMAIN}".whois.sh
#!/usr/bin/bash -

JOBS=\$1
DOMAINS=\$2

function defang {
    local url=\$1
    url=\${url//http/hxxp}
    url=\${url//./$DEFANG}
    echo \$url
}
export -f defang

function dns {
    $DIG \$1 \$2 +short @8.8.8.8 \\
    | sort -n \\
    | sed -r -e 's/^[0-9]+ //' -e 's/.\$//'
}
export -f dns

function linebreak {
    readarray -t elements <&0
    for element in "\${elements[@]}"; do
        break=\${html:+<br />}
        html="\${html}\${break}\${element}"
    done
    echo \$html
}
export -f linebreak

function similar {
    echo \$(/usr/bin/python3 similar.py \$1 \$2)
}
export -f similar

function enrich {
    local domain=\$1
    local whois="\$($WHOIS -H \$domain)"
    if  grep -Ei -m1 'creat' <<<"\$whois" &>/dev/null; then
        local d8=\$(grep -Ei -m1 'creat' <<<"\$whois" \\
                        | cut -d':' -f2- \\
                        | sed -r 's/^ +//')
        local ts=\$(date +%s -d \$d8)
        if [[ \$ts -ge $START && \$ts -le $STODAY ]]$INCLUDES; then
            if [[ "\$domain" =~ ^xn-- ]]; then
                local dd="\$domain (\`$IDN --quiet -u "\$domain"\`)"
            else
                local dd="\$domain"
            fi
            dd="\$(defang "\$dd")"

            local ip=\$(dns a \$domain | linebreak)
            [[ "\$ip" =~ error ]] && ip=Error
            ip=\${ip:=None}
            ip="\$(defang "\$ip")"

            local mx=\$(dns mx \$domain | linebreak)
            [[ "\$mx" =~ error ]] && mx=Error
            mx=\${mx:=None}
            mx="\$(defang "\$mx")"

            local ns=\$(dns ns \$domain | linebreak)
            [[ "\$ns" =~ error ]] && ns=Error
            ns=\${ns:=None}
            ns="\$(defang "\$ns")"

            local rr=\$(grep -Ei -m1 'registrar url:' <<<"\$whois" | cut -d':' -f2-)
            rr=\${rr##*/}
            rr=\${rr,,}
            rr=\${rr:=None}
            rr="\$(defang "\$rr")"

            ss="\$(similar "\$domain" "${DOMAIN/result/}")"

            if [[ "\$ip" != "None" ]]; then
                domain=\$domain
            else
                domain=None
            fi

            printf "%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \\
                "\$ts" \\
                "\$d8" \\
                "\$dd" \\
                "\$ip" \\
                "\$mx" \\
                "\$ns" \\
                "\$rr" \\
                "\$ss" \\
                "\$domain"
        fi
    fi
}
export -f enrich

$PARALLEL -q -j\$JOBS enrich :::: \$DOMAINS 2>/dev/null
EOF
chmod +x "${DOMAIN}".whois.sh

# Running `whois' on "${DOMAIN}"...
VARIATIONS=$(wc -l "${DOMAIN}.${EXT}" | cut -d' ' -f1)
echo -n "[$(timestamp)] Running \`whois' on \"${DOMAIN}\" ($((--VARIATIONS)) variations)..."

./"${DOMAIN}".whois.sh 0 "${DOMAIN}.${EXT}" >"${DOMAIN}".whois && echo "OK" || echo "FAIL"

# clean up operations
function clean_result {
    local result=$1
    case $result in
    "$EXT")
        rm -rf "${DOMAIN}".${EXT}
        ;;
    "whois")
        rm -rf "${DOMAIN}".whois
        ;;
    "sorted")
        rm -rf "${DOMAIN}".sorted
        ;;
    "html")
        rm -rf "${DOMAIN}".html
        ;;
    *)
        rm -rf "${DOMAIN}".{${EXT},whois,sorted,html}
        ;;
    esac
}

function clean_script {
    local script=$1
    case $script in
    "$ENGINE")
        rm -rf "${DOMAIN}"."${ENGINE}".sh
        ;;
    "whois")
        rm -rf "${DOMAIN}".whois.sh
        ;;
    "sort")
        rm -rf "${DOMAIN}".sort.sh
        ;;
    "format")
        rm -rf "${DOMAIN}".format.sh
        ;;
    "sendemail")
        rm -rf "${DOMAIN}".sendemail.sh
        ;;
    *)
        rm -rf "${DOMAIN}".{"$ENGINE",whois,sort,format,sendemail}.sh
        rm -rf similar.py
        ;;
    esac
}

function clean_all {
    clean_result all
    clean_script all
}

# check for result, if any, in ${DOMAIN}.whois
if (( $(wc -l "${DOMAIN}".whois | cut -d' ' -f1) == 0 )); then
    echo "[$(timestamp)] No result. Bye!"
    clean_all
    exit 0
fi

# sort.sh
cat <<-EOF >"${DOMAIN}".sort.sh
#!/usr/bin/bash -

FILE=\$1

awk -F'|' '{ if (\$2 != "") print \$0 }' \$FILE \
| sort -t'|' -k1,1nr
EOF
chmod +x "${DOMAIN}".sort.sh

# Sorting result by timestamp...
echo -n "[$(timestamp)] Sorting result by timestamp..."

./"${DOMAIN}".sort.sh "${DOMAIN}".whois >"${DOMAIN}".sorted && echo "OK" || echo "FAIL"

# thumbnail.js
cat <<-EOF >thumbnail.js
const puppeteer = require('puppeteer-extra');
const stealth = require('puppeteer-extra-plugin-stealth');
puppeteer.use(stealth());

function timeout(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
};

const empty = "data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACwAAAAAAQABAAACAkQBADs=";

const domain = process.argv[2];
if (domain === "None") {
    console.log(empty);
    process.exit();
}

const minimal_args = [
  '--autoplay-policy=user-gesture-required',
  '--disable-background-networking',
  '--disable-background-timer-throttling',
  '--disable-backgrounding-occluded-windows',
  '--disable-breakpad',
  '--disable-client-side-phishing-detection',
  '--disable-component-update',
  '--disable-default-apps',
  '--disable-dev-shm-usage',
  '--disable-domain-reliability',
  '--disable-extensions',
  '--disable-features=AudioServiceOutOfProcess',
  '--disable-hang-monitor',
  '--disable-ipc-flooding-protection',
  '--disable-notifications',
  '--disable-offer-store-unmasked-wallet-cards',
  '--disable-popup-blocking',
  '--disable-print-preview',
  '--disable-prompt-on-repost',
  '--disable-renderer-backgrounding',
  '--disable-setuid-sandbox',
  '--disable-speech-api',
  '--disable-sync',
  '--hide-scrollbars',
  '--ignore-gpu-blacklist',
  '--metrics-recording-only',
  '--mute-audio',
  '--no-default-browser-check',
  '--no-first-run',
  '--no-pings',
  '--no-sandbox',
  '--no-zygote',
  '--password-store=basic',
  '--use-gl=swiftshader',
  '--use-mock-keychain',
];

(async() => {
    const browser = await puppeteer.launch({headless: 'new', args: minimal_args, ignoreHTTPSErrors: true});
    try {
        const page = await browser.newPage();
        await page.setViewport({width: 800, height: 600});
        await page.goto('http://www.' + domain + '/');
        await timeout(5000);
        const base64 = await page.screenshot({encoding: 'base64', type: 'jpeg'});
        console.log("data:image/jpeg;base64," + base64);
    } catch (error) {
        console.log(empty);
    } finally {
        browser.close();
    }
})();
EOF

# Creating thumbnails...
cut -d'|' -f1-8 <"${DOMAIN}".sorted >"${DOMAIN}".part1
if (( ${THUMBNAIL:-0} == 1 )); then
    echo -n "[$(timestamp)] Creating thumbnails..."
    readarray -t domains < <(cut -d'|' -f9 <"${DOMAIN}".sorted)
    for domain in "${domains[@]}"; do
        NODE_PATH=$(npm root -g) $NODEJS thumbnail.js "$domain" >> "${DOMAIN}".part2 || echo
    done
    paste -d'|' "${DOMAIN}".part1 "${DOMAIN}".part2 >"${DOMAIN}".thumbnail && echo "OK" || echo "FAIL"
else
    cut -d'|' -f1-8 <"${DOMAIN}".sorted >"${DOMAIN}.thumbnail"
fi
rm thumbnail.js
rm "${DOMAIN}".{sorted,part*}
mv "${DOMAIN}".thumbnail "${DOMAIN}".sorted

# format.sh
cat <<-EOF >"${DOMAIN}".format.sh
#!/usr/bin/bash -

FILE=\$1

awk -F'|' -v thumbnail=$THUMBNAIL '
BEGIN {
    print  "<!DOCTYPE html>";
    print  "<html lang=\"en\">";
    print  "<head>";
    print  "<meta charset=\"utf-8\" />";
    print  "<meta name=\"viewport\" content=\"width=device-width\">";
    print  "<style type=\"text/css\">";
    print  "body { font-family: monospace, sans-serif; }";
    print  "th { font-weight: bold; text-align: left; }";
    print  "th, td { background: #eee; padding: 8px; }";
    print  "@media screen and (max-width: 600px) {";
    print  "  table { width: 100%; }";
    print  "  table thead { display: none; }";
    print  "  table tr, table td { border-bottom: 1px solid #ddd; }";
    print  "  table tr { margin-bottom: 8px; }";
    print  "  table td { display: flex; }";
    print  "  table td::before {";
    print  "    content: attr(label);";
    print  "    float: left;";
    print  "    font-weight: bold;";
    print  "    width: 120px;";
    print  "    min-width: 120px;";
    print  "  }";
    print  "}";
    print  "img { border: 1px solid #ddd; border-radius: 4px; padding: 5px; width: 160px; height: 120px; }";
    print  "</style>";
    print  "</head>";
    print  "<body>"
    print  "  <table>";
    print  "    <thead>";
    print  "      <tr>";
    print  "        <th>Created</th>";
    print  "        <th>Domain</th>";
    print  "        <th>IP</th>";
    print  "        <th>MX</th>";
    print  "        <th>NS</th>";
    print  "        <th>Registrar</th>";
    if (\$8 != "")
        print  "        <th>Similarity</th>";
    if (thumbnail == 1)
        print  "        <th>Thumbnail</th>";
    print  "      </tr>";
    print  "    </thead>";
    print  "    <tbody>";
}
{
    print  "      <tr>";
    printf "        <td label=\"Created\">%s</td>\n", \$2;
    if (\$3 == "${DOMAIN//./$DEFANG}") {
        printf "        <td label=\"Domain\">%s (original)</td>\n", \$3;
    } else {
        printf "        <td label=\"Domain\">%s</td>\n", \$3;
    }
    printf "        <td label=\"IP\">%s</td>\n", \$4;
    printf "        <td label=\"MX\">%s</td>\n", \$5;
    printf "        <td label=\"NS\">%s</td>\n", \$6;
    printf "        <td label=\"Registrar\">%s</td>\n", \$7;
    if (\$8 != "")
        printf "        <td label=\"Similarity\">%s</td>\n", \$8;
    if (\$9 != "") {
        print  "        <td label=\"Thumbnail\">";
        printf "          <a target=\"_blank\" href=\"%s\">\n", \$9;
        printf "            <img alt=\"%s\" title=\"%s\" src=\"%s\" width=\"160\" height=\"120\">\n", \$3, \$3, \$9;
        print  "          </a>";
        print  "        </td>";
    }
    print  "      </tr>";
}
END {
    print  "    </tbody>";
    print  "  </table>";
    print  "</body>"
    print  "</html>";
}
' \$FILE
EOF
chmod +x "${DOMAIN}".format.sh

# Formatting result to HTML...
echo -n "[$(timestamp)] Formatting result to HTML..."

./"${DOMAIN}".format.sh "${DOMAIN}".sorted >"${DOMAIN}".html && echo "OK" || echo "FAIL"

# Keep result and do not send email...
if (( ${KEEP:-0} == 1 )); then
    echo "[$(timestamp)] Result in file \"${DOMAIN}.html\"."
    clean_result $EXT
    clean_result whois
    clean_result sorted
    clean_script all
    exit 0
fi

# sendemail.sh
cat <<-EOF >"${DOMAIN}".sendemail.sh
DOMAIN=\$1
RECIPIENT=\$2
SMTP_USER="$SMTP_USER"
SMTP_PASS="$SMTP_PASS"
SMTP_SERV="$SMTP_SERV"
SUBJECT="LOOKALIKE DOMAIN ALERT - \$DOMAIN"

RECIPIENT=\${RECIPIENT:=\$SMTP_USER}

$SENDEMAIL \\
    -f  "ALERT <\$SMTP_USER>" \\
    -t  "\$RECIPIENT" \\
    -o  tls=auto \\
    -o  message-charset=UTF-8 \\
    -o  message-content-type=html \\
    -o  message-file=${DOMAIN}.html \\
    -u  "\$SUBJECT" \\
    -s  "\$SMTP_SERV" \\
    -xu "\$SMTP_USER" \\
    -xp "\$SMTP_PASS"
EOF
chmod +x "${DOMAIN}".sendemail.sh

# Sending email to <$RECIPIENT>...
echo -n "[$(timestamp)] Sending email to <$RECIPIENT>..."

# Make a list of domains; transform them to upper case and separated by comma
while read -r domain; do
    COMMA=${DOMAINS:+, }
    DOMAINS="${DOMAINS}${COMMA}${domain^^}"
done < <(awk -F'|' '{ print $3 }' "${DOMAIN}".sorted)

./"${DOMAIN}".sendemail.sh "$DOMAINS" "$RECIPIENT" &>/dev/null && echo "OK" || echo "FAIL"

# clean up
clean_all

# $SCRIPT has ended.
echo "[$(timestamp)] $SCRIPT has ended."

exit 0
