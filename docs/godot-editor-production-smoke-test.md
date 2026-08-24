# Godot Editor Production Smoke-Test Mode

Godot DEBUG builds use the local development backend by default:

`http://localhost:5000`

To explicitly use the deployed backend for an Editor smoke test, start Godot
from the same PowerShell session after setting this local process environment
variable:

```powershell
$env:THERESIANS_PRODUCTION_SMOKE_TEST = "1"
& "C:\Path\To\Godot_v4.6.1-stable_win64.exe" --editor --path "C:\Path\To\capstone-theresians-quest"
```

With this exact opt-in, a DEBUG build uses:

`https://theresiansquest.com`

Godot prints the following non-secret Editor-output indicator when the mode is
enabled:

```text
PRODUCTION SMOKE TEST MODE — active backend: https://theresiansquest.com
```

To disable the override and return the current PowerShell session to normal
local-development behavior:

```powershell
Remove-Item Env:THERESIANS_PRODUCTION_SMOKE_TEST -ErrorAction SilentlyContinue
```

The flag selects only the configured production URL. It does not accept a URL,
perform a request, create data, or bypass backend authorization. A release build
always uses the configured production URL and never falls back to the local
development URL.
