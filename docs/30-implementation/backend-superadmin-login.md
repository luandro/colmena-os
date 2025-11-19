## Why the backend submodule change is required

Context: our unified Docker image provisions a single superadmin account (`admin@example.com`) during startup. The Playwright smoke flow logs in with that account to validate that the stack actually works end to end.

Before the change, `colmena/serializers/serializers.py` refused to authenticate superadmin users because `ColmenaLoginSerializer.is_valid_user()` only allowed OrgOwner, Admin, or User group members. Superadmins belong exclusively to the "Superadmin" group, so login requests returned `{"error_code":"ERRORS_USERNAME_NOT_FOUND"}` and the container remained on the server connection screen. This blocked the smoke script and the Playwright suite from connecting, even though the credentials were correct.

Reverting the serializer patch would take us back to that behaviour and immediately break `scripts/compose-smoke.sh` and `tests/playwright` (they would fail at the login step).

Allowing the Superadmin group in the serializer is therefore the minimal change needed to keep automated stack validation working while still enforcing group-based access control for regular roles.
