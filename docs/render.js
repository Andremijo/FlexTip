// Renders docs/illustration.html to docs/rows.png (needs Playwright with Chromium).
// Run from anywhere: node docs/render.js
const path = require('path');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 2 });
  await page.goto('file://' + path.join(__dirname, 'illustration.html'));
  await page.locator('#card').screenshot({ path: path.join(__dirname, 'rows.png'), omitBackground: true });
  await browser.close();
})();
