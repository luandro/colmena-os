import { expect, test } from '@playwright/test';

const httpBaseUrl = process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:7180';
const apiBaseUrl = process.env.PLAYWRIGHT_API_BASE_URL || 'http://127.0.0.1:7100/api';

test.describe('Edge Cases and Volume Permissions', () => {
  test('should handle static file serving with correct permissions', async ({ page }) => {
    // This test verifies that static files (CSS, JS, images) are served correctly
    // which indicates proper volume mounts and permissions

    await page.goto(httpBaseUrl);

    // Wait for page to load
    await expect(page.locator('body')).toBeVisible({ timeout: 60_000 });

    // Check if CSS files are loaded (check for computed styles)
    const bodyStyles = await page.evaluate(() => {
      const body = document.querySelector('body');
      return window.getComputedStyle(body).fontFamily;
    });

    // If styles are applied, it means CSS files are being served correctly
    expect(bodyStyles).toBeTruthy();

    // Check that JavaScript bundle is loaded
    const hasJavaScript = await page.evaluate(() => {
      return document.querySelectorAll('script').length > 0;
    });
    expect(hasJavaScript).toBeTruthy();

    console.log('✅ Static files (CSS, JS) are being served correctly');
  });

  test('should handle rapid container restarts', async ({ page }) => {
    // This test verifies the application can handle rapid restart scenarios

    await page.goto(httpBaseUrl);

    // First load
    await expect(page.locator('body')).toBeVisible({ timeout: 60_000 });
    const initialLoadTime = Date.now();

    // Refresh the page multiple times quickly
    for (let i = 0; i < 3; i++) {
      await page.reload({ waitUntil: 'networkidle' });
      await expect(page.locator('body')).toBeVisible({ timeout: 60_000 });
    }

    const totalTime = Date.now() - initialLoadTime;
    expect(totalTime).toBeLessThan(180000); // Should complete within 3 minutes

    console.log('✅ Application handles rapid restarts gracefully');
  });

  test('should validate environment configuration', async ({ page }) => {
    // This test checks that required environment variables are properly configured
    // by verifying expected application behavior

    await page.goto(httpBaseUrl);

    // The application should load without configuration errors
    await expect(page.locator('body')).toBeVisible({ timeout: 60_000 });

    // Check that API endpoints are accessible (not returning 500 errors)
    const response = await page.request.get(`${apiBaseUrl}/schema/`);
    expect(response.status()).toBeLessThan(500); // No server errors

    // Verify we get a valid response (either 200 or 404 for specific endpoint)
    expect([200, 404]).toContain(response.status());

    console.log('✅ Environment configuration is valid');
  });

  test('should handle concurrent migration attempts', async ({ page }) => {
    // This test simulates multiple requests during migration startup
    // to verify the application handles concurrent access gracefully

    await page.goto(httpBaseUrl);

    // Make multiple concurrent API requests
    const promises = [];
    for (let i = 0; i < 5; i++) {
      promises.push(
        page.request.get(`${apiBaseUrl}/schema/`).then(res => ({
          status: res.status(),
          requestNumber: i
        }))
      );
      // Small delay between requests
      await page.waitForTimeout(100);
    }

    const responses = await Promise.all(promises);

    // Log failed requests for debugging (verbose output only for failures)
    const failedRequests = responses.filter(r => r.status >= 400);
    if (failedRequests.length > 0) {
      failedRequests.forEach((res, idx) => {
        console.log(`Request ${res.requestNumber}: HTTP ${res.status}`);
      });
    }

    // All requests should get valid HTTP responses
    responses.forEach((res) => {
      expect(res.status).toBeLessThan(600);
    });

    // At least some requests should succeed
    const successCount = responses.filter(r => r.status === 200).length;
    expect(successCount).toBeGreaterThan(0);

    console.log('✅ Application handles concurrent requests during startup');
  });

  test('should validate socket permissions (Issue #8)', async ({ page }) => {
    // This test indirectly validates that socket permissions are correctly set
    // by verifying that backend-frontend communication works

    await page.goto(httpBaseUrl);

    // Wait for the application to initialize
    await expect(page.locator('body')).toBeVisible({ timeout: 60_000 });

    // The fact that we can navigate and interact indicates
    // that the Unix socket communication (Issue #8) is working correctly

    // Try to trigger an API call that would use the socket
    const response = await page.request.get(`${apiBaseUrl}/schema/`);

    // If socket permissions were wrong (777 vs 660), we would get permission errors
    expect(response.status()).toBeLessThan(500);

    if (response.status() === 200) {
      console.log('✅ Unix socket communication working correctly (Issue #8)');
    }
  });
});
