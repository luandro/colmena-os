/**
 * Playwright Configuration for ColmenaOS Integration Tests
 */

const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  // Test directory
  testDir: './tests/playwright',
  
  // Global test timeout
  timeout: 30000,
  
  // Test configuration
  expect: {
    timeout: 5000
  },
  
  // Fail the build on CI if you accidentally left test.only in the source code
  forbidOnly: !!process.env.CI,
  
  // Retry on CI
  retries: process.env.CI ? 2 : 0,
  
  // Parallel tests on CI
  workers: process.env.CI ? 1 : undefined,
  
  // Reporter
  reporter: 'html',
  
  use: {
    // Base URL for tests
    baseURL: 'http://localhost:7180',
    
    // Global test settings
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  // Configure projects for different browsers
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
  ],

  // Run local dev server before starting tests
  webServer: {
    command: 'docker-compose -f docker-compose.local.yml up -d',
    port: 7180,
    timeout: 120 * 1000,
    reuseExistingServer: !process.env.CI,
  },
});