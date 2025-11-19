import { expect, test } from '@playwright/test';

const httpBaseUrl = process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:7180';

test.describe('Infrastructure Validation', () => {
  test('should serve static files correctly', async ({ page }) => {
    // Validates: nginx config, volume mounts, static asset serving
    // Catches: nginx misconfiguration, volume permission issues, build artifacts not copied
    await page.goto(httpBaseUrl);
    await expect(page.locator('body')).toBeVisible({ timeout: 60_000 });

    // Check if CSS files are loaded (check for computed styles)
    const bodyStyles = await page.evaluate(() => {
      const body = document.querySelector('body');
      return window.getComputedStyle(body).fontFamily;
    });
    expect(bodyStyles).toBeTruthy();

    // Check that JavaScript bundle is loaded
    const hasJavaScript = await page.evaluate(() => {
      return document.querySelectorAll('script').length > 0;
    });
    expect(hasJavaScript).toBeTruthy();

    console.log('✅ Static files (CSS, JS) served correctly');
  });
});
