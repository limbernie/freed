# freed.sh

A proof-of-concept shell script for early detection of lookalike domain used in a third-party compromise or business email compromise.

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
  -i INCLUDES   include domain(s) separated by comma in the operation
  -k            keep HTML result and do not send email
  -p PERIOD     time period to look back, e.g. 30d, 24h (default)
  -s RECIPIENT  send email to recipient, e.g. <your.gmail.account@gmail.com> (default)
  -t            show thumbnail
  -x            show internationalized domain name (IDN)
```

## Premise

To pull off an attack or to achieve action on objectives in a third-party compromise or business email compromise, the threat actor must be tactically placed in the middle of email communications between my organization and the counter party, also known as man-in-the-email attack. A necessary condition for this attack to take place is to register new domains or to update expired ones that look like the domains of my organization and that of the counter party, which to the untrained eye, especially a [homoglyph](https://en.wikipedia.org/wiki/Homoglyph) attack, may be difficult to spot in an email.

My idea is simple.

It makes no sense to detect newly registered domains that looked like the domains of my counter parties since that number could easily fall into hundreds, if not more, an unmanageable situation.

What if we only focus on detecting newly registered domains that looked like ours?

The script can then be put in a `crontab` to run every day, say at 12AM UTC to find lookalike domains in the last 24 hours and send email alert to a recipient if there's a hit. The script takes at most two minutes to run, which is not time-consuming in my opinion because the script uses `parallel` to speed things up.

### Dependencies

The script depends on the following programs:

1. [dig](https://www.isc.org/download/)
2. [dnstwist](https://github.com/elceef/dnstwist)
3. [parallel](https://www.gnu.org/software/parallel/)
4. [sendemail](https://github.com/mogaal/sendemail)
5. [urlcrazy](https://github.com/urbanadventurer/urlcrazy)
6. [urlinsane](https://github.com/ziazon/urlinsane)

You should be able to get these programs from your Linux distribution.

### Permutation

You can choose a permutation engine from three permutation engines: `dnstwist`, `urlcrazy` or `urlinsane` (default).

### Send email from the script

You need to sign up for a SMTP service to send an email alert to a recipient.

Gmail SMTP service is recommended because the `@gmail.com` domain would pass SPF, DKIM and DMARC checks to deliver the email alert to your recipient or yourself. However, the step-by-step instructions to set up Gmail SMTP service is beyond the scope of this README.

## Example

Running `freed.sh` on `facebook.com` to look back 30 days from the time of script run (2023-12-08), with the following options:

* `-d`. Use defang character `․` (one dot leader) instead of the default `[.]` to save space.
* `-i`. Include the original domain for comparison.
* `-k`. Keep HTML result and do not send email.
* `-t`. Show thumbnail.
* `-x`. Show internationalized domain name (to expose homoglyph attacks).

```demo
$ ./freed.sh -d․ -i facebook.com -k -p30d -t -x facebook.com
[2023-12-08T03:50:55Z] freed.sh has started.
[2023-12-08T03:50:55Z] Running `urlinsane' on "facebook.com"...done
[2023-12-08T03:51:09Z] Running `whois' on "facebook.com" (2844 variations)...done
[2023-12-08T03:52:38Z] Sorting result by timestamp...done
[2023-12-08T03:52:38Z] Creating thumbnails...done
[2023-12-08T03:53:28Z] Formatting result to HTML...done
[2023-12-08T03:53:28Z] Result in file "facebook.com.insane.html"
```

The result is sorted in descending order (latest to earliest) by the domain creation date/time. 

RR stands for Registrar, and is shown as the Registrar's URL, if any, from WHOIS.

![facebook.com](facebook.com-demo.png)
