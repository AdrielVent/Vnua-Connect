// Serves the project folder statically and tests at phone and desktop widths.
module.exports = {
  testDir: './tests',
  timeout: 90000,
  webServer: { command: 'python3 -m http.server 8000', port: 8000, reuseExistingServer: true },
  use: { baseURL: 'http://localhost:8000' },
  projects: [
    { name: 'desktop', use: { viewport: { width: 1440, height: 900 } } },
  ],
};
