# AMPCrypt: Custom Subdomain & DNS Setup Guide

This guide explains how to map your custom subdomain (e.g., `ampcrypt.yourdomain.com`) to your deployed AMPCrypt Web Vault on GitHub Pages.

---

## 1. Configure DNS Records with your Registrar

Go to your DNS provider (e.g., Namecheap, Cloudflare, GoDaddy) and add the following records:

### Option A: Using a CNAME Record (Recommended for Subdomains)
For subdomains (like `ampcrypt.yourdomain.com`), point a `CNAME` record to GitHub's domain system:
- **Type**: `CNAME`
- **Host/Name**: `ampcrypt`
- **Value/Target**: `[your-github-username].github.io`
- **TTL**: Automatic or 1 Hour

### Option B: Using A-Records (For Apex Domains)
If you are mapping the root apex domain (like `yourdomain.com`), configure `A` records pointing to GitHub Pages IP addresses:
- `185.199.108.153`
- `185.199.109.153`
- `185.199.110.153`
- `185.199.111.153`

---

## 2. Add CNAME File in AMPCrypt Repository

To prevent GitHub Pages from losing your custom subdomain settings when a new build is deployed:

1. Create a file named `CNAME` (no file extension) in the root folder of this repository.
2. In that file, write your custom domain or subdomain name on a single line:
   ```text
   ampcrypt.yourdomain.com
   ```
3. Commit and push the CNAME file. The GitHub Actions CI/CD workflow is already configured to automatically copy this file to your built web project directory during deployment.

---

## 3. Verify GitHub Pages Settings

Once your workflow run finishes:
1. Go to your GitHub Repository -> **Settings** -> **Pages**.
2. Under **Custom domain**, ensure your domain name (`ampcrypt.yourdomain.com`) is displayed.
3. Check the box for **Enforce HTTPS** to secure the connection with an automatically generated SSL certificate (takes up to 24 hours to active).
