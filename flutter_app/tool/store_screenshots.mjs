// Google Play screenshots (C-20), Chinese and English, all 9:16:
//   phone (default) 1080x1920 (360x640 at 3x)
//   tablet7         1152x2048 (576x1024 at 2x)
//   tablet10        1620x2880 (810x1440 at 2x)
// Pick one with DEVICE=tablet7 or DEVICE=tablet10.
//
// Needs a local backend in development mode with demo data, serving the built web app:
//   cd flutter_app && flutter build web --release
//   cd ../backend && createdb cb_store && export DATABASE_URL=postgresql+psycopg://postgres@localhost:5432/cb_store
//   APP_ENV=development uv run alembic upgrade head && APP_ENV=development uv run python -m app.seed
//   APP_ENV=development WEB_DIR=$PWD/../flutter_app/build/web uv run uvicorn app.main:app --port 8765
// Then, with Playwright installed (npm install playwright):
//   node flutter_app/tool/store_screenshots.mjs docs/store/screenshots
//
// It signs in with the development token dev:mei. The official Q&A pages come from the NISA
// file the seed imports; posts are the demo ones.
import { mkdirSync } from 'node:fs';
import { chromium } from 'playwright';

const out = process.argv[2] ?? 'screenshots';
const base = process.env.BASE_URL ?? 'http://localhost:8765';
const token = 'dev:mei';
const devices = {
  phone: { viewport: { width: 360, height: 640 }, deviceScaleFactor: 3 },
  tablet7: { viewport: { width: 576, height: 1024 }, deviceScaleFactor: 2 },
  tablet10: { viewport: { width: 810, height: 1440 }, deviceScaleFactor: 2 },
};
const device = devices[process.env.DEVICE ?? 'phone'];
const pages = [
  ['01-home', '/'],
  // Procedure cards on top, official Q&A below. No procedure detail page: the demo procedures
  // name one school, and the store listing must not suggest a school partnership.
  ['02-faqs', '/faqs'],
  ['03-faq', '/faqs/nisa-934'],
  ['04-explore', '/explore'],
  ['05-experience', '/experiences/class-invitation'],
  ['06-share', '/share'],
];

const browser = await chromium.launch();
for (const lang of ['zh', 'en']) {
  mkdirSync(`${out}/${lang}`, { recursive: true });
  const context = await browser.newContext({
    ...device,
    locale: lang === 'en' ? 'en-US' : 'zh-TW',
  });
  await context.addInitScript(
    ([tokenValue, english]) => {
      localStorage.setItem('flutter.dev-token', JSON.stringify(tokenValue));
      localStorage.setItem('flutter.english', String(english));
    },
    [token, lang === 'en'],
  );
  const page = await context.newPage();
  for (const [name, path] of pages) {
    await page.goto(base + path);
    await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 30000 });
    await page.waitForTimeout(4000); // fonts and API data
    await page.screenshot({ path: `${out}/${lang}/${name}.jpg`, type: 'jpeg', quality: 90 });
    console.log(`${lang}/${name}`);
  }
  await context.close();
}
await browser.close();
