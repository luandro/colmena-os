# Title
Fix superadmin auth and normalize env-origin parsing

# Message
- retain the superadmin login guard so the platform admin can still access the UI after initial bootstrap
- normalize host/CORS env parsing so docker-compose values stop crashing Django on boot

# Why
We need both changes together to ship the unified Docker image via compose; without the auth fix we lose superadmin access needed for provisioning, and without the parsing fix the backend restarts indefinitely, blocking our deployment work.
