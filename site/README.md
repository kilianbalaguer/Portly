# Portly website

A small static Next.js landing page for Portly.

```sh
npm install
npm run dev      # http://localhost:3000
npm run build    # static site in out/
```

- **Release details** (version, download link, size) live in `app/site.ts`. Update them with each release.
- **Images** in `public/` come from the app's README asset generator (`docs/images` on `main`).
- **Deploying:** it's a static export, so any static host works. On Vercel, set the project's root directory to `site`. Set `SITE_URL` to the final URL so social previews use absolute image links.
