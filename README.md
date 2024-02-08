# freed.sh

A proof-of-concept shell script for early detection of lookalike domains utilized in a business email compromise or third-party compromise.

## Premise

To pull off an attack or to take action on objectives in a business email compromise or third-party compromise, an adversary must be placed tactically in the middle of email communications between an organization and its counterparty, also known as a man-in-the-email attack. A necessary condition for this attack to take place, especially a [homoglyph](https://en.wikipedia.org/wiki/Homoglyph) attack, is to register new domains or to update expired ones that look like the domains of the organization and its counterparty, which to the untrained eye, may be difficult to spot in an email.

The idea is simple.

It makes no sense to detect lookalike domains of the counterparties since that number could easily fall into hundreds if not more—an unmanageable situation for a large organization. The focus should be placed on detecting lookalike domains of the organization instead.

The script can then be put in `crontab(5)` to run daily at midnight to find lookalike domains of the organization in the last twenty-four hours and send an email alert to a recipient if there's a hit.

```
0 0 * * * /path/to/freed.sh -s recipient@example.com
```

The script uses `parallel` to speed things up, which shouldn't take more than three minutes in a single vCPU virtual machine running a common Linux distribution such as Ubuntu.

### Similarity Analysis

[Damerau-Levenshtein distance](https://en.wikipedia.org/wiki/Damerau%E2%80%93Levenshtein_distance) between two domains is the minimum number of operations (consisting of insertions, deletions or substitutions of a single character, or transposition of two adjacent characters) required to transform one domain into the other. It's a common practice to normalize the similarity into a floating point number between 0 and 1, where 0 means different while 1 is identical, which can be easily expressed as a percentage to indicate how similar one domain is compared to the other domain

### Phonetic Analysis

[Metaphone](https://en.wikipedia.org/wiki/Metaphone) is a phonetic algorithm for indexing domains by their English pronunciation. It fundamentally improves on the [Soundex](https://en.wikipedia.org/wiki/Soundex) algorithm by using information about variations and inconsistencies in English spelling and pronunciation to produce a more accurate encoding, which does a better job of matching words and names that sound similar. As with Soundex similar-sounding words should share the same keys.

### The difference between a parked domain and a weaponized domain

The main objective of weaponizing a domain is so that the adversary can communicate directly with the organization and the counterparty. For that to happen, the adversary must set up an MX record in the DNS of the domain. 

| Domain     | Created | MX Record                             |
|:-----------|:--------|:--------------------------------------|
| Parked     | Recent  | No                                    |
| Weaponized | Recent  | Yes (usually free email services[^1]) |

[^1]:https://www.trendmicro.com/en_fi/research/21/j/analyzing-email-services-abused-for-business-email-compromise.html

## Usage

```help
$ ./freed.sh -h
Usage: freed.sh [OPTION]... [DOMAIN]
Find lookalike DOMAIN created in the last PERIOD and send result to RECIPIENT.

positional argument
  DOMAIN        target domain name

options
  -d DEFANG     defang character/string, e.g. '·' (U+00B7), '[.]' (default)
  -e ENGINE     permutation engine, e.g. dnstwist, urlcrazy, urlinsane (default)
  -h            display this help and exit
  -i DOMAIN     include domain(s) separated by comma
  -I FILE       include file containing domains separated by newline
  -k            keep HTML result and do not send email
  -p PERIOD     time period to look back, e.g. 30d, 24h (default)
  -s RECIPIENT  send email to recipient, e.g. <your.gmail.account@gmail.com> (default)
  -t            display thumbnail in HTML result
  -x            display internationalized domain name (IDN) in HTML result
```

### Operation Mode

The script operates in two modes: `alert` or `analysis`, depending on the positional argument.

If the `DOMAIN` argument is present, `alert` mode is active. The use case for `alert` mode is to alert lookalike domains when they are created. The permutation engine is used.

If the `DOMAIN` argument is absent, `analysis` mode is active if and only if the `-i` and/or `-I` options are also present and valid. The use case for analysis mode is for standalone analysis of domains without using the permutation engine.

### Dependencies

The script depends on the following programs for a start:

1. [`dig`](https://www.isc.org/download/)
2. [`dnstwist`](https://github.com/elceef/dnstwist)
3. [`parallel`](https://www.gnu.org/software/parallel/)
4. [`sendemail`](https://github.com/mogaal/sendemail)
5. [`urlcrazy`](https://github.com/urbanadventurer/urlcrazy)
6. [`urlinsane`](https://github.com/rangertaha/urlinsane)
7. [`whois`](https://github.com/rfc1036/whois)

These programs and plugins are also needed depending on the options, such as (`-t`) display thumbnails in the HTML result or (`-x`) display internationalized domain names in the HTML result:

1. [`nodejs`](https://github.com/nodejs/node), [`puppeteer`](https://github.com/puppeteer/puppeteer), [`puppeteer-extra`](https://github.com/berstend/puppeteer-extra), and [`puppeteer-extra-plugin-stealth`](https://github.com/berstend/puppeteer-extra)

2. [`idn`](https://www.gnu.org/software/libidn/)

You should be able to get these programs from your preferred Linux distribution.

### Permutation

You can choose one permutation engine out of three permutation engines: `dnstwist`, `urlcrazy` or `urlinsane` (default). URLInsane is chosen as the default because it has all the functionality of URLCrazy and DNSTwist.[^2]

[^2]: https://github.com/rangertaha/urlinsane#features

### Send an email from the script

To send an email alert to a recipient, you need to sign up for a SMTP service.

Gmail SMTP service is recommended because the `gmail.com` domain would pass SPF, DKIM and DMARC checks to deliver the email alert to a recipient (or `your.gmail.account@gmail.com` by default). The step-by-step instructions to set up Gmail SMTP service are beyond the scope of this README.

## Example

Running `freed.sh` in `alert` mode on `facebook.com`, looking back sixty days from the time of the script run, with the following options:

* `-d`. Use defang character `․` (one dot leader) instead of the default `[.]` to save space.
* `-i`. Include the original domain for comparison.
* `-k`. Keep the HTML result and do not send an email.
* `-t`. Display thumbnail in HTML result.
* `-x`. Display internationalized domain names in HTML results to expose homoglyph attacks.

```
$ ./freed.sh -d ․ -i facebook.com -k -p 60d -t -x facebook.com
[2024-01-15T09:52:05Z] freed.sh started in alert mode.
[2024-01-15T09:52:05Z] Running `urlinsane' on "facebook.com"...OK
[2024-01-15T09:52:17Z] Running `whois' on "facebook.com" (2843 variations)...OK
[2024-01-15T09:53:36Z] Sorting result by timestamp...OK
[2024-01-15T09:53:36Z] Creating thumbnails...OK
[2024-01-15T09:56:05Z] Formatting result to HTML...OK
[2024-01-15T09:56:05Z] Result in file "facebook.com.html".
```

The result is sorted in descending order by the domain creation date/time (from youngest domain to oldest domain).

![facebook.com](facebook.com-demo.png)
