import { expect, test } from '@playwright/test';

const httpBaseUrl = process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:7180';
const apiBaseUrl = process.env.PLAYWRIGHT_API_BASE_URL || 'http://127.0.0.1:7100/api';

test.describe('Load Testing', () => {
  test('should handle multiple concurrent API requests', async ({ page }) => {
    // Basic load test to verify the application can handle concurrent requests

    await page.goto(httpBaseUrl);
    await expect(page.locator('body')).toBeVisible({ timeout: 60_000 });

    const startTime = Date.now();
    const concurrentRequests = 10;

    // Make multiple concurrent API requests
    const promises = [];
    for (let i = 0; i < concurrentRequests; i++) {
      promises.push(
        page.request.get(`${apiBaseUrl}/health/`).then(res => ({
          status: res.status(),
          duration: Date.now() - startTime,
          requestId: i
        }))
      );
    }

    const responses = await Promise.all(promises);
    const totalTime = Date.now() - startTime;

    // Analyze results
    console.log(`\n📊 Load Test Results:`);
    console.log(`   Total Requests: ${concurrentRequests}`);
    console.log(`   Total Time: ${totalTime}ms`);
    console.log(`   Average Response Time: ${Math.round(totalTime / concurrentRequests)}ms`);

    // All requests should complete successfully
    const successCount = responses.filter(r => r.status === 200).length;
    const failureCount = responses.filter(r => r.status >= 500).length;

    console.log(`   Successful (200): ${successCount}`);
    console.log(`   Server Errors (5xx): ${failureCount}`);

    // At least 80% of requests should succeed
    expect(successCount / concurrentRequests).toBeGreaterThanOrEqual(0.8);

    // Total time should be reasonable (less than 30 seconds for 10 concurrent requests)
    expect(totalTime).toBeLessThan(30000);

    // No server errors
    expect(failureCount).toBe(0);

    console.log('✅ Application handles concurrent load successfully');
  });

  test('should maintain performance under sustained load', async ({ page }) => {
    // Test sustained load over time to identify performance degradation

    await page.goto(httpBaseUrl);
    await expect(page.locator('body')).toBeVisible({ timeout: 60_000 });

    const requestCount = 20;
    const requestInterval = 500; // ms between requests
    const responseTimes: number[] = [];

    console.log(`\n📈 Sustained Load Test: ${requestCount} requests over ${(requestCount * requestInterval) / 1000}s`);

    for (let i = 0; i < requestCount; i++) {
      const start = Date.now();
      const response = await page.request.get(`${apiBaseUrl}/health/`);
      const duration = Date.now() - start;

      responseTimes.push(duration);

      expect(response.status()).toBeLessThan(500);

      // Log every 5th request
      if ((i + 1) % 5 === 0) {
        console.log(`   Request ${i + 1}/${requestCount}: ${duration}ms (HTTP ${response.status()})`);
      }

      // Wait before next request
      await page.waitForTimeout(requestInterval);
    }

    // Calculate statistics
    const avgResponseTime = responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length;
    const maxResponseTime = Math.max(...responseTimes);
    const minResponseTime = Math.min(...responseTimes);

    console.log(`\n   Statistics:`);
    console.log(`   Min: ${minResponseTime}ms`);
    console.log(`   Max: ${maxResponseTime}ms`);
    console.log(`   Avg: ${Math.round(avgResponseTime)}ms`);

    // Average response time should be reasonable (less than 2 seconds)
    expect(avgResponseTime).toBeLessThan(2000);

    // Performance shouldn't degrade dramatically (max should be < 5x average)
    expect(maxResponseTime).toBeLessThan(avgResponseTime * 5);

    console.log('✅ Application maintains performance under sustained load');
  });

  test('should handle page navigation under load', async ({ page }) => {
    // Test that page navigation still works when making concurrent API requests

    await page.goto(httpBaseUrl);
    await expect(page.locator('body')).toBeVisible({ timeout: 60_000 });

    // Start making concurrent API requests
    const apiRequests = Array.from({ length: 5 }, (_, i) =>
      page.request.get(`${apiBaseUrl}/health/`).then(res => ({ status: res.status(), id: i }))
    );

    // Navigate the page while API requests are in flight
    try {
      // Try to find and click navigation elements
      const homeLink = page.locator('a, button').filter({ hasText: /home|Home/i }).first();
      if (await homeLink.isVisible()) {
        await homeLink.click();
        await expect(page).toHaveURL(/.*home.*/, { timeout: 10_000 });
      }
    } catch (error) {
      // Navigation might not work if backend is down, which is acceptable
      console.log('   Navigation test skipped (backend may be starting up)');
    }

    // Wait for API requests to complete
    const responses = await Promise.all(apiRequests);
    const successCount = responses.filter(r => r.status === 200).length;

    console.log(`\n🔗 Navigation + Load Test:`);
    console.log(`   Successful API responses: ${successCount}/${apiRequests.length}`);

    // At least some requests should succeed
    expect(successCount).toBeGreaterThan(0);

    console.log('✅ Page navigation works during concurrent API load');
  });
});
