#!/bin/bash
#
# freed.sh - free domain shell script
# Find lookalike DOMAIN created in the last PERIOD and send result to RECIPIENT.
#
SCRIPT=$(basename "$0")
STODAY=$(date +%s)

# SMTP configuration
SERVER="smtp.gmail.com:587"
SMTP_PASS="your app password from gmail"
SMTP_USER="your.gmail.account@gmail.com"

# ACE prefix filter in IDNs
XN="| grep -Ev '^xn--'"

# die gracefully
function die {
    echo "$SCRIPT: $*" >&2
    echo "Try \`$SCRIPT -h' for more information." >&2
    exit 1
}

# depends "command"
function depends {
    echo "$SCRIPT: depends on \`$*'" >&2
    echo "Install \`$*' and try again." >&2
    exit 1
}

# usage statement
function usage {
cat <<-EOF
Usage: $SCRIPT [OPTION]... DOMAIN
Find lookalike DOMAIN created in the last PERIOD and send result to RECIPIENT.

positional argument
  DOMAIN        target domain name

options
  -d CHARACTER  defang character, e.g. "·" (U+00B7), "․" (U+2024), "[.]" (default)
  -e ENGINE     permutation engine, e.g. dnstwist, urlcrazy, urlinsane (default)
  -h            display this help and exit
  -i DOMAIN     include domain(s) separated by comma
  -k            keep HTML result and do not send email
  -p PERIOD     time period to look back, e.g. 30d, 24h (default)
  -s RECIPIENT  send email to recipient, e.g. <$SMTP_USER> (default)
  -t            show domain thumbnail
  -x            show international domain name (xn--)
EOF
}

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
        exit 0
        ;;
    i)
        INCLUDE=$OPTARG
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
        which node &>/dev/null || depends "puppeteer"
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

# argument count
(( $# == 0 )) && die "you must specify a domain name"

# argument check; default value
REGEX='^[^-]{1,63}\.[a-z]{2,3}(\.[a-z]{2})?$'
[[ ! "$1" =~ $REGEX ]] && die "invalid domain name"
DEFANG=${DEFANG:=[.]}
DOMAIN=$1; shift
ENGINE=${ENGINE:=urlinsane}
if [[ "$INCLUDE" ]]; then
    INCLUDE=$(tr ',' '\n' <<<"$INCLUDE" \
            | awk '{ printf "^%s$|", $0 }' \
            | sed 's/|$//')
    INCLUDE=" || [[ \$domain =~ ($INCLUDE) ]]"
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
#!/bin/bash

DOMAIN=\$1

$DNSTWIST --format list \$DOMAIN \\
| sed 1d \\
$XN > \${DOMAIN}.${EXT}
EOF

chmod +x "${DOMAIN}.${ENGINE}".sh
;;

"urlcrazy")
EXT=crazy

# urlcrazy.sh
cat <<-EOF >"${DOMAIN}.${ENGINE}".sh
#!/bin/bash

DOMAIN=\$1

ulimit -n 10000

$URLCRAZY -n -r \${DOMAIN} \\
| grep -Ev '[ST]LD' \\
| sed -e '\$d' -e '11,\$!d' \\
| awk '{ print \$NF }' > \${DOMAIN}.${EXT}
EOF

chmod +x "${DOMAIN}.${ENGINE}".sh
;;

"urlinsane")
EXT=insane

# urlinsane.sh
cat <<-EOF >"${DOMAIN}.${ENGINE}".sh
#!/bin/bash

DOMAIN=\$1

$URLINSANE typo \$DOMAIN -k all -x idna -o csv \\
| grep -Ev '([HPS]I|TLD)' \\
| sed '11,\$!d' \\
| awk -F, '{ print \$NF }' \\
$XN > \${DOMAIN}.${EXT}
EOF

chmod +x "${DOMAIN}.${ENGINE}".sh
;;

*) die "invalid permutation engine" ;;

esac

# $SCRIPT has started.
echo "[$(timestamp)] $SCRIPT has started."

# Running \`$ENGINE' on "${DOMAIN}"...
echo -n "[$(timestamp)] Running \`${ENGINE}' on \"${DOMAIN}\"..."

./"${DOMAIN}.${ENGINE}".sh "${DOMAIN}" && sed -i "1i\\$DOMAIN" "${DOMAIN}.${EXT}"

echo "done"

# whois.sh
cat <<-EOF >"${DOMAIN}".whois.sh
#!/bin/bash

THREADS=\$1
DOMAINS=\$2

function defang {
    sed -r \\
        -e 's/\./$DEFANG/g' \\
        -e 's/http/hxxp/g' <<<"\$1"
}
export -f defang

function lookup {
    local domain=\$1
    local whois="\$($WHOIS -H \$domain)"
    if  grep -Ei -m1 'creat' <<<"\$whois" &>/dev/null; then
        local date=\$(grep -Ei -m1 'creat' <<<"\$whois" \\
                        | cut -d':' -f2- \\
                        | sed -r 's/^ +//')
        local ts=\$(date +%s -d \$date)
        if [[ \$ts -ge $START && \$ts -le $STODAY ]]$INCLUDE; then
            local rr=\$(grep -Ei -m1 'registrar url:' <<<"\$whois" \\
                        | cut -d':' -f2- \\
                        | sed -r 's/^ +(https?:\/\/)+//')
            rr=\${rr,,}
            rr=\${rr:=None}
            rr="\$(defang "\$rr")"
            local dns=8.8.8.8
            local ip=\$($DIG A \$domain +short @\$dns \\
                        | tr '\n' ',' \\
                        | sed -e 's/,$//' -e 's/,/<br \/>/g')
            ip=\${ip:=None}
            ip="\$(defang "\$ip")"
            local mx=\$($DIG MX \$domain +short @\$dns \\
                        | sed -r -e 's/^[0-9]+ //' -e 's/.\$//' \\
                        | tr '\n' ',' \\
                        | sed -e 's/,$//' -e 's/,/<br \/>/g')
            [[ "\$mx" =~ error ]] && mx=Error
            mx=\${mx:=None}
            mx="\$(defang "\$mx")"
            local ns=\$($DIG NS \$domain +short @\$dns \\
                        | sed -e 's/.\$//' \\
                        | tr '\n' ',' \\
                        | sed -e 's/,$//' -e 's/,/<br \/>/g')
            [[ "\$ns" =~ error ]] && ns=Error
            ns=\${ns:=None}
            ns="\$(defang "\$ns")"
            if [[ "\$domain" =~ ^xn-- ]]; then
                local dd="\$domain (\`$IDN --quiet -u "\$domain"\`)"
            else
                local dd="\$domain"
            fi
            dd="\$(defang "\$dd")"
            if [[ "\$ip" != "None" ]]; then
                domain=\$domain
            else
                domain=None
            fi
            printf "%s|%s|%s|%s|%s|%s|%s|%s\n" \\
                "\$ts" \\
                "\$date" \\
                "\$dd" \\
                "\$ip" \\
                "\$mx" \\
                "\$ns" \\
                "\$rr" \\
                "\$domain"
        fi
    fi
}
export -f lookup

$PARALLEL -q -j\$THREADS lookup :::: \$DOMAINS 2>/dev/null
EOF
chmod +x "${DOMAIN}".whois.sh

# Running `whois' on "${DOMAIN}"...
VARIATIONS=$(wc -l "${DOMAIN}.${EXT}" | cut -d' ' -f1)
echo -n "[$(timestamp)] Running \`whois' on \"${DOMAIN}\" ($VARIATIONS variations)..."

./"${DOMAIN}".whois.sh 64 "${DOMAIN}.${EXT}" >"${DOMAIN}".whois

echo "done"

# clean up operations
function clean_result {
    local result=$1
    case $result in
    "$EXT")
        rm -rf "${DOMAIN}.${EXT}"
        ;;
    "whois")
        rm -rf "${DOMAIN}".whois
        ;;
    "sorted")
        rm -rf "${DOMAIN}".sorted
        ;;
    "html")
        rm -rf "${DOMAIN}.${EXT}".html
        ;;
    *)
        rm -rf "${DOMAIN}".{"${EXT}",whois,sorted,"${EXT}".html}
        ;;
    esac
}

function clean_script {
    local script=$1
    case $script in
    "$ENGINE")
        rm -rf "${DOMAIN}.${ENGINE}".sh
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
        rm -rf "${DOMAIN}".{"${ENGINE}",whois,sort,format,sendemail}.sh
        ;;
    esac
}

function clean_all {
    clean_result
    clean_script
}

# check for result, if any, in ${DOMAIN}.whois
if (( $(wc -l "${DOMAIN}".whois | cut -d' ' -f1) == 0 )); then
    echo "[$(timestamp)] No result. Bye!"
    clean_all
    exit 0
fi

# sort.sh
cat <<-EOF >"${DOMAIN}".sort.sh
#!/bin/bash

FILE=\$1

awk -F'|' '{ if (\$2 != "") print \$0 }' \$FILE \
| sort -t'|' -k1,1nr
EOF
chmod +x "${DOMAIN}".sort.sh

# Sorting result by timestamp...
echo -n "[$(timestamp)] Sorting result by timestamp..."

./"${DOMAIN}".sort.sh "${DOMAIN}".whois >"${DOMAIN}".sorted

echo "done"

# thumbnail.js
cat <<-EOF >thumbnail.js
const puppeteer = require('puppeteer-extra');
const stealth = require('puppeteer-extra-plugin-stealth');
puppeteer.use(stealth());

function timeout(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
};

const empty = "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAIAQMAAAD+wSzIAAAABlBMVEX///+/v7+jQ3Y5AAAADklEQVQI12P4AIX8EAgALgAD/aNpbtEAAAAASUVORK5CYII";

(async() => {
    try {
        const domain = process.argv[2];
        if (domain === "None") {
            console.log(empty);
            process.exit();
        }
        const browser = await puppeteer.launch({headless: 'new'});
        const page = await browser.newPage();
        await page.setViewport({width: 800, height: 600});
        await page.goto('http://www.' + domain + '/');
        await timeout(1000);
        const base64 = await page.screenshot({encoding: 'base64'});
        browser.close();
        console.log(base64);
    } catch (error) {
        console.log(empty);
    }
})();
EOF

# Creating thumbnails...
cut -d'|' -f1-7 < "${DOMAIN}".sorted > "${DOMAIN}".tbm1
if (( ${THUMBNAIL:-0} == 1 )); then
    echo -n "[$(timestamp)] Creating thumbnails..."
    readarray -t domains < <(cut -d'|' -f8 <"${DOMAIN}".sorted)
    for domain in "${domains[@]}"; do
        node thumbnail.js "$domain" >> "${DOMAIN}".tbm2
    done
    paste -d'|' "${DOMAIN}".tbm1 "${DOMAIN}".tbm2 > "${DOMAIN}".thumbnail
    echo "done"
else
    cut -d'|' -f1-7 < "${DOMAIN}".sorted > "${DOMAIN}.thumbnail"
fi
rm thumbnail.js
rm "${DOMAIN}".{sorted,tbm*}
mv "${DOMAIN}".thumbnail "${DOMAIN}".sorted

# format.sh
cat <<-EOF >"${DOMAIN}".format.sh
#!/bin/bash

FILE=\$1

awk -F'|' -v thumbnail=$THUMBNAIL '
BEGIN {
    print  "<!DOCTYPE html>";
    print  "<html lang=\"en\">";
    print  "<head>";
    print  "<meta charset=\"utf-8\" />";
    print  "<style>";
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
    print  "        <th>RR</th>";
    if (thumbnail == 1) {
        print "        <th>Thumbnail</th>";
    }
    print  "      </tr>";
    print  "    </thead>";
    print  "    <tbody>";
}
{
    print  "      <tr>";
    printf "        <td label=\"Created\">%s</td>\n", \$2;
    printf "        <td label=\"Domain\">%s</td>\n", \$3;
    printf "        <td label=\"IP\">%s</td>\n", \$4;
    printf "        <td label=\"MX\">%s</td>\n", \$5;
    printf "        <td label=\"NS\">%s</td>\n", \$6;
    printf "        <td label=\"RR\">%s</td>\n", \$7;
    if (\$8 != "") {
        print  "        <td label=\"Thumbnail\">";
        printf "          <a target=\"_blank\" href=\"data:image/png;base64,%s\">", \$8;
        printf "            <img src=\"data:image/png;base64,%s\" alt=\"%s\">", \$8, \$3;
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

./"${DOMAIN}".format.sh "${DOMAIN}".sorted >"${DOMAIN}.${EXT}".html

echo "done"

# Keep result and do not send email...
if (( ${KEEP:-0} == 1 )); then
    echo "[$(timestamp)] Result in file \"${DOMAIN}.${EXT}.html\""
    clean_result $EXT
    clean_result whois
    clean_result sorted
    clean_script "$@"
    exit 0
fi

# sendemail.sh
cat <<-EOF >"${DOMAIN}".sendemail.sh
DOMAIN=\$1
RECIPIENT=\$2
SERVER="$SERVER"
SMTP_USER="$SMTP_USER"
SMTP_PASS="$SMTP_PASS"
SUBJECT="LOOKALIKE DOMAIN ALERT - \$DOMAIN"

RECIPIENT=\${RECIPIENT:=\$SMTP_USER}

$SENDEMAIL \\
    -f "ALERT <\$SMTP_USER>" \\
    -t "\$RECIPIENT" \\
    -o tls=auto \\
    -o message-charset=UTF-8 \\
    -o message-content-type=html \\
    -o message-file=${DOMAIN}.${EXT}.html \\
    -u "\$SUBJECT" \\
    -s "\$SERVER" \\
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

./"${DOMAIN}".sendemail.sh "$DOMAINS" "$RECIPIENT" &>/dev/null && echo "done" || echo "failed"

# clean up
clean_all

# $SCRIPT has ended.
echo "[$(timestamp)] $SCRIPT has ended."

exit 0
