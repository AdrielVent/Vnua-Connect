// Playwright wrapper around the in-page self-test (not yet executed in this environment).
// Setup: npm i -D @playwright/test && npx playwright install chromium
// Run:   npx playwright test
const { test, expect } = require('@playwright/test');

test('in-page regression suite passes', async ({ page }) => {
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto('/Vnua-connect.dc.html');
  await page.waitForFunction(() => typeof window.vnuaSelfTest === 'function' && !!window.VnuaMockApi);
  await page.waitForTimeout(1500);
  const results = await page.evaluate(() => window.vnuaSelfTest());
  const failed = results.filter((r) => !r.startsWith('PASS'));
  expect(failed, failed.join('\n')).toEqual([]);
  expect(errors).toEqual([]);
});

test('visitor can browse without an account', async ({ page }) => {
  await page.goto('/Vnua-connect.dc.html');
  await page.getByRole('button', { name: 'Member app' }).click();
  await page.getByRole('button', { name: 'Browse clubs and events' }).click();
  await expect(page.getByText('Lowlight Drama Collective').first()).toBeVisible();
});
