# freed.sh

A proof-of-concept shell script for early detection of lookalike domain used in a third-party compromise or business email compromise.

```help
$ ./freed -h
Usage: freed.sh [OPTION]... DOMAIN
Find lookalike DOMAIN created in the last PERIOD and send result to RECIPIENT.

positional argument
  DOMAIN        target domain name

options
  -d CHARACTER  defang character, e.g. "·" (U+00B7), "․" (U+2024), "[.]" (default)
  -e ENGINE     permutation engine, e.g. dnstwist, urlcrazy, urlinsane (default)
  -h            display this help and exit
  -i DOMAIN     include domain(s) separated by comma
  -k            keep HTML result and do not send email
  -p PERIOD     period of time to look back, e.g. 30d, 24h (default)
  -s RECIPIENT  send email to recipient, e.g. <freed.domain.alert@gmail.com> (default)
  -x            show international domain name (xn--)
```

## Premise

To pull off an attack or to achieve action on objectives in a third-party compromise or business email compromise, the adversary must be tactically placed in the middle of email communications between your organization and the counter party, also known as man-in-the-email attack. A necessary condition for this attack is to register new domains or update expired ones that look like the domains of your organization and that of the counter party, which to the untrained eye, especially a [homoglyph](https://en.wikipedia.org/wiki/Homoglyph) attack, may be difficult to spot in an email.

The idea is simple.

It makes no sense to detect newly registered domains that looked like the domains of your counter parties since that number could easily fall into hundreds, if not more, an unmanageable situation.

What if we only focus on detecting newly registered domains that looked like yours?

The script can then be put in a `crontab` to run every day, say at 12AM UTC. The script takes at most 2 mins to run, which is not time-consuming in my opinion because the script is running in multiple parallel processes.

### Dependencies

The script depends on the following programs:

1. [dig](https://www.isc.org/download/)
2. [dnstwist](https://github.com/elceef/dnstwist)
3. [parallel](https://www.gnu.org/software/parallel/)
4. [sendemail](https://github.com/mogaal/sendemail)
5. [urlcrazy](https://github.com/urbanadventurer/urlcrazy)
6. [urlinsane](https://github.com/ziazon/urlinsane)

### Permutation

You can choose from three permutation engines: `dnstwist`, `urlcrazy` and `urlinsane` (default).

### Send email from the script

You need to sign up for a SMTP service to send an email alert to a recipient.

Gmail SMTP service is recommended. However, the step-by-step instructions to set up Gmail SMTP service is beyond the scope of this README.

## Example

Running `freed.sh` on `facebook.com` to look back 100 days from the time of script run (2023-11-28), with the following options:

* `-d`. Use defang character `·` (middle dot) instead of the default `[.]`.
* `-i`. Include the original domain for comparison.
* `-k`. Keep HTML result and do not send email.
* `-x`. Show international domain name (to expose homoglyph attacks).

```demo
./freed.sh -d'·' -i facebook.com -k -p 100d -x facebook.com
[2023-11-28T07:12:43Z] freed.sh has started.
[2023-11-28T07:12:43Z] Running `urlinsane' on "facebook.com"...done
[2023-11-28T07:12:55Z] Running `whois' on "facebook.com" (2844 variations)...done
[2023-11-28T07:14:12Z] Sorting result by timestamp...done
[2023-11-28T07:14:12Z] Formatting result to HTML...done
[2023-11-28T07:14:12Z] Result in file facebook.com.insane.html
```

The result is sorted in descending order (from latest to earliest) by the date/time of domain creation. 

RR stands for Registrar, and is shown as the Registrar's URL.

![facebook.com](facebook.com-demo.png)
