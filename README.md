# GDPR Website Audit Tool

A simple command-line tool that scans a **whole website** for common GDPR and privacy basics. It produces an easy-to-read report that opens in your browser.

It's designed for small business owners, freelancers and anyone who wants a quick health check of their website, so no technical knowledge is needed to understand the results.

> **Note:** This tool gives a quick automated check. It is **not legal advice** and doesn't guarantee GDPR compliance.

---

## How it works

1. You enter your website address.
2. The tool starts on that page and follows the links to other pages on the same site, up to a page limit you choose (20 by default).
3. It checks every page it finds, putting important pages first (privacy policy, cookie policy, contact, sign-up and checkout pages).
4. You get a single report with an overall score, what to fix first, and exactly **which pages** each problem was found on.

---

## What it checks

| Area | What it looks for |
|---|---|
| **Secure connection** | Whether the site uses HTTPS, whether `http://` visits are redirected to the secure version, and whether secure pages load anything over insecure `http://` |
| **Privacy policy** | Whether a privacy policy exists, whether it's linked on **every page**, and whether it covers key topics: contact details, what data you collect, your lawful basis, how long you keep data, who you share it with, and the right to complain to the ICO |
| **Cookie consent** | A cookie consent tool (e.g. Cookiebot, OneTrust, CookieYes, Complianz) |
| **Forms** | Forms that collect personal details (names, emails, phone numbers) but have no privacy wording, checkboxes that are **ticked by default**, and forms that send data insecurely |
| **Tracking** | Trackers such as Google Analytics, the Meta Pixel, Hotjar, Microsoft Clarity, LinkedIn and TikTok, and whether there's a consent tool to ask permission first |
| **Security headers** | Content-Security-Policy and HSTS |
| **Data rights** | Whether your site explains people's rights over their data (access, deletion and so on) |

Each result is marked as **Passed**, **Worth fixing**, **Action needed** or **For info**, with a plain-English explanation and a suggested fix.

---

## The report

The web page report includes:

- An overall **score out of 100** with a clear verdict (*Looking good*, *Needs some work* or *At risk*)
- A **Top priorities** list showing what to fix first
- A card for each check explaining the result and **how to fix it**, with a list of the pages affected
- A **Pages checked** list showing every page scanned and any issues found on it
- A **Show issues only** button to hide passed checks
- A **Print / Save as PDF** button
- Dark mode and a mobile-friendly layout

You can also choose a plain text (`.txt`) or Markdown (`.md`) report instead.

<img width="1677" height="938" alt="image" src="https://github.com/user-attachments/assets/05165d71-d57f-436a-b1c8-2b18af655511" />

---

## Requirements

- **Bash**: built into macOS and Linux. On Windows, use [Git Bash](https://git-scm.com/downloads) or [WSL](https://learn.microsoft.com/en-us/windows/wsl/install).
- **curl**: already installed on most systems.
- An internet connection.

---

## Installation

1. Download `gdpr_audit.sh` from this repository.

2. Open a terminal in the folder where you saved it, and make the script executable:

   ```bash
   chmod +x gdpr_audit.sh
   ```

---

## How to use

1. Run the script:

   ```bash
   ./gdpr_audit.sh
   ```

2. Answer the questions. Press **Enter** to accept a default:

   ```
   Enter website URL (e.g. example.com): mywebsite.co.uk
   Maximum number of pages to check [20]: 30

   Choose output format:
   1) Web page (recommended - opens in your browser)
   2) txt
   3) md
   Enter choice (1-3) [1]:
   ```

3. The tool shows each page as it checks it, then opens the report:

   ```
   Checking https://mywebsite.co.uk (up to 30 pages)...
     [1/30] / (homepage)
     [2/30] /privacy-policy
     [3/30] /contact
     ...

   Audit complete! Score: 71/100 (Needs some work)
   Pages checked: 18
   Passed: 6   Warnings: 3   Failed: 1
   Report saved as: gdpr_report_mywebsite.co.uk.html
   Opening report in your browser...
   ```

If the report doesn't open automatically, double-click the `.html` file it saved in the same folder as the script.

---

## Choosing how many pages to check

- The default is **20 pages**, which is enough for most small websites.
- The maximum is **200 pages**.
- The tool waits half a second between pages so it doesn't overload your server, so bigger scans take longer. 50 pages takes roughly a minute.
- If the limit is reached before every page has been checked, the report tells you, so you can run it again with a higher number.

---

## Tips

- **Double-check cookie banners in your browser.** Some banners load with JavaScript after the page has loaded, so the tool may not always detect them.
- **Re-run after making fixes** to see your score improve.
- **Start from a specific section** by entering its address, e.g. `mywebsite.co.uk/shop`.

---

## Limitations

- Only follows links on the same website. Subdomains (e.g. `shop.mywebsite.co.uk`) and privacy policies hosted on other sites aren't checked.
- Can't see content or links that only appear after JavaScript runs.
- Can't check pages that require logging in.
- Looks for common tools and wording, but can't judge whether your privacy policy is legally complete.
- Doesn't check how data is stored or handled behind the scenes.

---

## Responsible use

Only scan websites you own or have permission to check.

---

## Contributing

Suggestions and improvements are welcome! If you spot a problem or have an idea, open an issue on this repository.

## Disclaimer

This tool is provided for informational purposes only and does not constitute legal advice. For more information on GDPR, see the [ICO's guidance](https://ico.org.uk/for-organisations/).
