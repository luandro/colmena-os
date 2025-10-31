# Title
Handle missing OpenAPI status method in frontend

# Message
- guard the generated API client call so we use `client.status_retrieve()` when available and fall back to `client.get('/api/status/')`
- keep the same success path/return signature so the rest of the UI polling logic stays untouched

# Why
Playwright uncovered that recent schema changes omit the `status_retrieve` method at runtime, leaving the server connect button disabled because the call throws; this fallback ensures the frontend always reaches `/api/status/` and unblocks users from connecting to the backend.
