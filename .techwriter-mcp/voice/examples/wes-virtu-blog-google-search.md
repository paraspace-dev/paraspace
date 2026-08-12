<!-- Copied verbatim from ~/projects/writing-samples/Wes Roberts/virtu-blog-google-search.md (hand-written, per that repo's README). -->

<!-- blog article from the virtu project, hand-written by this repo's author pre-AI; voice reference -->
# Don't Track Me, Google.

**<span class="first-letter">G</span>oogle earns 85% of its revenue through advertising.** Despite providing hundreds of other products and services, its billions stem primarily from its most important product: **you**.

According to [recent research](https://theconversation.com/most-americans-dont-realize-what-companies-can-predict-from-their-data-110760), folks generally know Google collects their information for profit, but they don't typically realize the extent to which the company can deduce intimiate details from _all_ the data they collect, purchase, aggregate, and analyize about them.

Location data alone [reveals](https://www.nytimes.com/interactive/2018/12/10/business/location-data-privacy-apps.html) your home address, your employer, habits, interests, religious affiliations, the age range of your children, etc. Combined with other available data, Google can deduce or attain your approximate height, weight, age, financial situation, family ties, legal cases, voter registration, recent purchases, social network accounts, who you spend time with, multicultural affinity, sexual orientation, political perspective, and more. The list goes on, and they don't keep it secret.

All of that information becomes extremely valuable when a 1% increase in ad success translates to an extra billion dollars in revenue.

### We expect privacy.

Even if your search history doesn't embarrass you, an overwhelming majority of folks [still care](https://repository.upenn.edu/cgi/viewcontent.cgi?article=1414&context=asc_papers) that companies like Google spy on and profit from their every move, or use their data to unethically influence political elections.

Ethics aside, even governments with global warrantless wiretapping and surveillance agree that selling, sharing, or collecting your private or personal information should require an explicit opt-in. You can see this manifest in the latest bills such as GDPR and CCPA, and also the spirit of the old guard such as HIPAA.

For instance, the EU recently fined Google [€44 million](https://www.bbc.com/news/technology-46944696) for tricking users into forfeiting their personal info by making their opt-out process misleading and difficult to find.

### Nowhere to hide.

It goes far beyond Google. Day-to-day, we may fail to remind ourselves that cellphone carriers [sell our location data](https://www.wired.com/story/carriers-sell-location-data-third-parties-privacy/), or that Internet providers can spy on traffic and [sell our browser history](https://www.washingtonpost.com/news/the-switch/wp/2017/03/29/what-to-expect-now-that-internet-providers-can-collect-and-sell-your-web-browser-history/?utm_term=.939135ee1fba). Our personal data eventually trickles back to the warehouses of companies like Amazon, Facebook, and Google through data brokers [you've never heard of](https://motherboard.vice.com/en_us/article/bjpx3w/what-are-data-brokers-and-how-to-stop-my-private-data-collection), neatly packaged for promotional purposes.

As a result, a truly continent privacy guard would require widespanning changes to your technology choices and behavior. In the rest of this article, we will cover ways to dramatically reduce or eliminate your personal data footprint while still enjoying tools like Google Search.

With so many misleading suggestions out there, I feel obliged to warn you that Google might have a stronger grip on your private data than others claim.

For example, don't let [DuckDuckGo](https://ddg.com/) fool you. First off, their search result relevance barely holds a candle to Google's. More importantly, 70% of your search results will [use Google Analytics](https://marketingland.com/as-google-analytics-turns-10-we-ask-how-many-websites-use-it-151892), so Google can still track the bulk of your browser history and your search terms. Even if you block cookies and mask your IP address, your [browser fingerprint](https://panopticlick.eff.org/static/browser-uniqueness.pdf) may still identify you. Using Google Chrome exacerbates the problem.

Also, "Incognito mode" won't help much. It will eventually delete cookies and local browser history, but that wont stop companies like Google from tracking you. Chrome even warns that enabling extensions allows others to track you.

Let's look at some suggestions that might actually help reduce your private data footprint online, especially when using Google Search.

## Protect your privacy.

**We mostly like Google Search**. It rocks. We just want to use it without donating our personal information to companies who want to exploit us.

So how do we do that? To avoid Google's tracking, follow these steps **in order**, and **do not use or access any Google services** througout the process. For example, when signing-up for a VPN, do not give them your Gmail address, or an address that routes to Gmail. Do not Google for the VPN service. Do not use Google Chrome.

**Level 1: Google Search privacy**

1. Don't use Google Chrome.
1. Install a privacy tool like Disconnect.
1. Connect through a VPN or proxy.
1. Randomize your User Agent identifier.
1. Disable JavaScript for Google.com.
1. Disable cookies for Google.com.
1. Disable HTTP referrer headers.
1. Remove href prefixes on Google.com.

**Leve 2: General online privacy**

8. Mask your contact information.
9. Find alternatives to Gmail, G-Suite, etc.
10. De-Google your other devices.

### 1. Don't use Chrome.

According to Google Chrome's [privacy policy](https://www.google.com/intl/en/chrome/privacy/), the browser itself collect a good bit of information about you by default:

- Everything you type in the address bar
- Two or more unique identifiers for promotion, tracking, and testing
- URL-keyed data for "personalization" of other Google features
- Your location, IP address, WiFi routers, and cell tower information

If you enable "Sign-In", "Sync", and other services, Google collects even more about you and your device. Theoretically it also helps them link your Chrome data with data they collected elsewhere, such as from data brokers or Gmail.

- Your email address(es)
- Your payment information
- A detailed fingerprint of your computer or other device
- Almost all browsing data stored locally by Chrome

With a lot of research and effort you can turn off most of these tracking features in Chrome itself, or with extensions. However, you cannot stop them all, and disabling features like sync degrades the overall experience.

For more privacy-conscious alternatives, you can try [Brave](https://brave.com/), [Firefox](https://firefox.com/), [Waterfox](https://www.waterfoxproject.org/), or unGoogled [Chromium](https://github.com/Eloston/ungoogled-chromium). Keep in mind these other tools also have privacy policies and collect some data. No matter which browser you choose, you will want to configure it for better privacy.

<!-- TODO: Link to article on configuring Firefox -->

### 2. Install a privacy tool.

Install a tool like [Disconnect](https://disconnect.me/disconnect) to your browsers. I honestly would **not** recommend [the](https://addons.mozilla.org/en-US/firefox/addon/donottrackplus/) [others](https://www.ghostery.com/) [for](https://www.reddit.com/r/firefox/comments/1qkc2b/disconnect_vs_ghostery/) [various](https://www.reddit.com/r/privacy/comments/xg7bn/ghostery_a_web_tracking_blocker_that_actually/) [reasons](https://www.reddit.com/r/privacy/comments/14t29c/whats_rprivacys_consensus_on_ghostery_we_seem_to/), and hope that more open solutions pop-up soon to balance the market.

By default, Disconnect (free version) will block all major 3rd party trackers from loading on most any website you visit. Especially for mobile, you might consider their premium plan for a VPN in the next step.

I also recommend installing a reputable ad blocker such as [uBlock Origin](https://addons.mozilla.org/en-US/firefox/addon/ublock-origin/). This will block even more unneeded traffic, improving your privacy protection and making your Web experience snappier.

Other notable yet questionable suggestions include [AdNauseam](https://adnauseam.io/) and apps that reduce the fingerprinting capabilities of JavaScript such as

### 3. Connect through a VPN or proxy.

A VPN allows you to connect to websites (remote hosts) with better end-to-end encryption. It prevents your ISP from spying on the traffic, and it masks your IP address. However, [choose your VPN wisely](https://thatoneprivacysite.net/vpn-comparison-chart/), as they can see everything.

What to look for in a good VPN:

- Doesn't store your IPs or access logs
- Based in a country that values privacy
- Secure, fast connectivity around the world
- Solid tech stack, not succeptable to [DNS leaks](https://www.dnsleaktest.com/what-is-a-dns-leak.html)

Important to note, a VPN encrypts your network traffic in public or unencrypted WiFi scenarios, like coffee shops. You should use a VPN at all times to protect your information, including payment info.

If you do not trust VPN companies, you can set-up your own VPN using [Streisand](https://github.com/StreisandEffect/streisand) or [algo](https://github.com/trailofbits/algo). However, I would not recommend using a VPS because you get a dedicated IP address that trackers can use to identify you.

You can try residential proxies like [Hola](http://hola.org/), but I wouldn't trust them. You could also purchase rotating proxy IPs, though I find them more difficult to configure properly, less reliable, and more expensive than VPN. Typically proxies serve a different use case than privacy protection.

### 4. Randomize your User Agent identifier.

The `User-Agent` header

```
User-Agent: blah
```

### 5. Disable JavaScript for Google.com.

Browser extensions like [NoScript](https://noscript.net/) allow you to control script execution per-domain. Ensure that absolutely no JavaScript executes when you visit the Google.com domain. This will mostly protect you from browser fingerprinting and the vast majority of other tracking mechanisms available to Google.

Fortunately Google search still works great without JavaScript. Many sites will break without JavaScript, so you may feel tempted to enable JavaScript by default on most domains. However, consider leaving JavaScript off by default. You will make your browser about a million times more secure in exchange for slight inconvenience.

<!--

# Links

- https://www.unixsheikh.com/articles/choose-your-browser-carefully.html
- https://bithost.io/
- https://privacy.net/analyzer/
- https://www.tonic.ai/post/ccpa-will-hit-your-dev-team-harder-than-gdpr/
- https://browserleaks.com/canvas
- https://theintercept.com/2017/06/05/be-careful-celebrating-googles-new-ad-blocker-heres-whats-really-going-on/
- https://www.statista.com/topics/1001/google/
- https://www.statista.com/statistics/540115/alphabet-quarterly-net-income/
- https://www.statista.com/statistics/266471/distribution-of-googles-revenues-by-source/
- https://www.statista.com/statistics/266249/advertising-revenue-of-google/
- https://www.betterads.org
- https://www.fakespot.com/
- https://www.nytimes.com/2018/11/15/style/this-is-also-amazon.html
- https://motherboard.vice.com/en_us/article/bjpx3w/what-are-data-brokers-and-how-to-stop-my-private-data-collection
- https://www.performics.com/new-facebook-multicultural-affinity-targeting-more-granular-segmenting-options-for-brands/
- https://www.minterest.com/google-products-services-you-probably-dont-know/


# More links

- https://www.nytimes.com/2019/06/11/opinion/privacy-facebook-sexting.html
- https://addons.mozilla.org/en-US/firefox/addon/decentraleyes/
- https://github.com/StevenBlack/hosts
- https://www.eff.org/privacybadger/faq#How-is-Privacy-Badger-different-from-Disconnect,-Adblock-Plus,-Ghostery,-and-other-blocking-extensions
- http://www.privacywall.org/
- https://pi-hole.net/


# "Anonymous" data can still identify you
- https://www.darkreading.com/endpoint/privacy/companies-anonymized-data-may-violate-gdpr-privacy-regs/d/d-id/1335361

# Android ships 100x as much personal data to Google as iOS does to Apple
- https://digitalcontentnext.org/wp-content/uploads/2018/08/DCN-Google-Data-Collection-Paper.pdf

-->
