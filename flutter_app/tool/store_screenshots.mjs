// Google Play phone screenshots (C-20): 1080x1920 (360x640 at 3x), Chinese and English.
//
// Needs a local backend in development mode with demo data, serving the built web app:
//   cd flutter_app && flutter build web --release
//   cd ../backend && createdb cb_store && export DATABASE_URL=postgresql+psycopg://postgres@localhost:5432/cb_store
//   APP_ENV=development uv run alembic upgrade head && APP_ENV=development uv run python -m app.seed
//   APP_ENV=development WEB_DIR=$PWD/../flutter_app/build/web uv run uvicorn app.main:app --port 8765
// Then, with Playwright installed (npm install playwright):
//   node flutter_app/tool/store_screenshots.mjs docs/store/screenshots
//
// It signs in with the development token dev:mei, starts the ARC procedure and ticks two steps
// so Home shows progress. Re-shoot with real procedure cards before publishing.
import { mkdirSync } from 'node:fs';
import { chromium } from 'playwright';

const out = process.argv[2] ?? 'screenshots';
const base = process.env.BASE_URL ?? 'http://localhost:8765';
const token = 'dev:mei';
const pages = [
  ['01-home', '/'],
  ['02-procedure', '/actions/arc'],
  ['03-progress', '/actions/arc/progress'],
  ['04-explore', '/explore'],
  ['05-experience', '/experiences/class-invitation'],
  ['06-share', '/share'],
];

async function api(method, path, body) {
  const response = await fetch(base + '/api' + path, {
    method,
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: body && JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`${method} ${path}: ${response.status}`);
  return response.json();
}

const execution = await api('POST', '/actions/arc/executions', { identity_type: 'degree_student' });
for (const step of execution.steps.slice(0, 2)) {
  await api('PUT', `/executions/${execution.id}/steps/${step.step_id}`, { state: 'done' });
}

const browser = await chromium.launch();
for (const lang of ['zh', 'en']) {
  mkdirSync(`${out}/${lang}`, { recursive: true });
  const context = await browser.newContext({
    viewport: { width: 360, height: 640 },
    deviceScaleFactor: 3,
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
