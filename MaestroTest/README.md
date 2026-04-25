# Maestro Bulk Simulator Runner

Drop-in `maestro/` folder that runs Maestro flows against N iOS simulators
sequentially, across an arbitrary number of rounds, with each simulator's
app data preserved between rounds.

Use case: do something on every device, come back later and do something
else, and observe the state the prior round left behind.

## Demo app

This repo also ships a tiny SwiftUI demo (`MaestroTest`) — a counter button
backed by SwiftData. The bundled flows tap the button across rounds and
prove the count survives between runs.

## Prerequisites

- macOS with Xcode installed
- Xcode command-line tools: `xcode-select --install`
- An iOS runtime installed via Xcode → Settings → Platforms
- JDK 11+ (Maestro requirement): `java -version`
- Maestro CLI:
  ```
  curl -fsSL "https://get.maestro.mobile.dev" | bash
  ```
  Then either open a new terminal or `export PATH="$PATH:$HOME/.maestro/bin"`.

Disk: budget ~1 GB per simulator.

## Drop-in usage

Copy the `maestro/` folder next to any iOS project's `.xcodeproj`:

```
your-app/
├── YourApp.xcodeproj
└── maestro/
    ├── run.sh
    └── flows/
        └── your_flow.yaml
```

Open `maestro/run.sh`, edit the CONFIG block at the top:

```bash
DEVICE_COUNT=5
DEVICE_TYPE="iPhone 16"

FLOWS=(
  "flows/flow_a.yaml"
  "flows/flow_a.yaml"
  "flows/flow_b.yaml"
)

PROJECT=""        # auto-detects the .xcodeproj in parent dir
SCHEME=""         # defaults to project name
KEEP_SIMS=0       # 1 = keep sims after run
SKIP_BUILD=0      # 1 = reuse existing build
```

Then run:

```
./maestro/run.sh
```

Each entry in `FLOWS` is one round, executed on every simulator before the
next round starts. App data persists between rounds.

## What it does

1. Builds the app (`xcodebuild -sdk iphonesimulator`).
2. Deletes all existing simulators on the machine and creates `DEVICE_COUNT`
   fresh ones, named `TestDevice-1`...`TestDevice-N`.
3. Pre-installs the built `.app` on each simulator.
4. For each flow in `FLOWS`, on each simulator:
   boot → wait for full boot → `maestro --device <UDID> test <flow>` → shutdown.
5. Tears down the simulators (unless `KEEP_SIMS=1`).

A single device's failure is logged and does not abort the run.

Build output goes to `maestro/.build/`. UDIDs are tracked in
`maestro/.simulator_udids.txt` between rounds. Both stay inside the folder.

## Writing flows

Standard Maestro YAML. Important: a flow that needs to observe state from a
prior round must NOT start with `clearState` or `clearKeychain` — those
wipe the persisted app data.

Example:

```yaml
appId: com.your.bundle.id
---
- launchApp:
    appId: com.your.bundle.id
- tapOn:
    id: "incrementButton"
- assertVisible:
    id: "counterValue"
```

## Caveats

- All flows must target the same `appId` (the app you built).
- `xcrun simctl delete all` runs unconditionally inside `run.sh` — it nukes
  every simulator on the machine, not just ones this script created. If you
  have other simulators you care about, comment that line.
- Auto-detect picks the first `.xcodeproj` in the parent dir; for workspaces
  or multi-project setups, set `PROJECT` and `SCHEME` explicitly.
- Simulators boot headlessly. Run `open -a Simulator` in another terminal
  if you want to watch them.
