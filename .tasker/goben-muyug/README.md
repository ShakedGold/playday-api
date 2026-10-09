---
status: open
priority: 60
kind: feature
---

# Remove the chromium dependency

In the GOG library implementation we use the chromium binary
to login the user and get a code.

We should modify it to just open with the default browser,
And set the redirect url to the application.
