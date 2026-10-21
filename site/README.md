# RentManager Website

Static website for the RentManager property management application.

## Structure

- `index.html` - Main page with app description, download links, and screenshots
- No build step required - just deploy the `site` folder

## Deploy to Netlify

1. Push this folder to a GitHub repository, or
2. Drag and drop the `site` folder to [Netlify Drop](https://app.netlify.com/drop)

Or use the Netlify CLI:

```bash
netlify init
# Follow prompts, then:
netlify deploy --site
# Or to publish:
netlify deploy --prod --dir=site
```