import { expect, test } from '@playwright/test';

const serverName = process.env.PLAYWRIGHT_SERVER_NAME || 'Local API';
const apiBaseUrl = process.env.PLAYWRIGHT_API_BASE_URL || 'http://127.0.0.1:7100/api';
const superadminEmail = process.env.PLAYWRIGHT_SUPERADMIN_EMAIL || process.env.SUPERADMIN_EMAIL || 'admin@example.com';
const superadminPassword = (() => {
  const value = process.env.PLAYWRIGHT_SUPERADMIN_PASSWORD || process.env.SUPERADMIN_PASSWORD;
  if (!value) {
    throw new Error(
      'PLAYWRIGHT_SUPERADMIN_PASSWORD (or SUPERADMIN_PASSWORD) must be set before running the smoke suite.',
    );
  }
  return value;
})();

const serverAddress = (() => {
  const envAddress = process.env.PLAYWRIGHT_SERVER_ADDRESS;
  if (envAddress) {
    return envAddress;
  }

  try {
    const parsed = new URL(apiBaseUrl);
    if (parsed.pathname === '/api' || parsed.pathname === '/api/') {
      parsed.pathname = '';
    }
    return parsed.toString().replace(/\/$/, '');
  } catch (error) {
    return apiBaseUrl.replace(/\/api\/?$/, '');
  }
})();

async function connectServer(page: import('@playwright/test').Page) {
  await page.addInitScript(() => {
    window.localStorage.clear();
  });

  await page.goto('/auth/servers');
  await page.evaluate(() =>
    new Promise<void>((resolve) => {
      const request = window.indexedDB.deleteDatabase('Server');
      request.onsuccess = () => resolve();
      request.onerror = () => resolve();
      request.onblocked = () => resolve();
    }),
  );

  await page.goto('/auth/servers');

  await page.getByRole('button', { name: /Add server/i }).click();
  await page.fill('#server_name_text_input', serverName);
  await page.fill('#server_address_text_input', serverAddress);
  await page.getByRole('button', { name: /Confirm/i }).click();

  const actionsButton = page.locator('button[aria-label="Actions"]').first();
  await expect(actionsButton).toBeVisible({ timeout: 10_000 });
  await actionsButton.click();
  const connectItem = page.getByRole('menuitem', { name: /Connect to server/i });
  await expect(connectItem).toBeEnabled({ timeout: 60_000 });
  await connectItem.click();
  await page.waitForFunction(() => !!window.localStorage.getItem('serverId'));
  await page.waitForURL('**/auth/login', { timeout: 30_000 });
}

async function login(page: import('@playwright/test').Page) {
  await page.fill('#username_text_input', superadminEmail);
  await page.fill('#password_text_input', superadminPassword);
  await expect(page.locator('#sign_in_up_submit_button')).toBeEnabled({ timeout: 10_000 });
  await page.click('#sign_in_up_submit_button');
  await page.waitForURL(/.*(user\/welcome|teams|home|dashboard).*/, { timeout: 60_000 });
  // Wait for authentication state to be established
  await page.waitForLoadState('networkidle', { timeout: 10_000 });
  await page.waitForFunction(() => !!window.localStorage.getItem('user'));
}

test.describe('ColmenaOS unified stack smoke flow', () => {
  test('connects server, logs in, and reaches core screens', async ({ page }) => {
    await connectServer(page);
    await login(page);

    const menuList = page.locator('#menu-nav-item-list');
    await expect(menuList).toBeVisible({ timeout: 30_000 });

    await page.getByRole('link', { name: 'Home', exact: true }).click();
    await expect(page).toHaveURL(/\/home/);
    await expect(page).not.toHaveURL(/auth\//);

    await page.getByRole('link', { name: 'Teams', exact: true }).click();
    await expect(page).toHaveURL(/\/teams/);
    await expect(page).not.toHaveURL(/auth\//);

    await page.getByRole('link', { name: 'Tools' }).click();
    await expect(page).toHaveURL(/\/tools/);
    await expect(page).not.toHaveURL(/auth\//);
  });
});
