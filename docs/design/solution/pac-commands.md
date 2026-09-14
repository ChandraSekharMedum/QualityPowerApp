# ALM — package the app + flows with Power Platform CLI (`pac`)

Optional but recommended: put the canvas app, the flows, and their connection references into a
**Dataverse solution** so you can version them in this repo and move dev → test → prod.

## Install & auth
```powershell
dotnet tool install --global Microsoft.PowerApps.CLI.Tool   # or the MSI
pac --version
pac auth create --url https://YOURORG.crm.dynamics.com
pac auth list
```

## Create the solution (once)
```powershell
pac solution init --publisher-name yourorg --publisher-prefix qms
```

Then in `make.powerapps.com` → **Solutions → New solution "QualityManagement"**, and **Add
existing** → the canvas app, all flows, and their **connection references** (so target
environments rebind connections instead of hard‑coding them).

## Export the canvas app source (unpack `.msapp` → YAML for git)
```powershell
# 1. Power Apps: File → Save as → This computer → QualityManagement.msapp
# 2. Unpack to editable source under canvas-app/src:
pac canvas unpack --msapp ".\QualityManagement.msapp" --sources ".\canvas-app\src"
```
> `canvas-app/src` (unpacked YAML) is the source‑controllable form of the app. The `screens/*.md`
> files in this repo are the human build spec; `src` is the machine round‑trip. Keep both:
> specs explain intent, `src` captures the exact build. `*.msapp` is git‑ignored (build artifact).

## Export / import the solution
```powershell
pac solution export --path .\solution\QualityManagement_unmanaged.zip --name QualityManagement
pac solution export --path .\solution\QualityManagement_managed.zip   --name QualityManagement --managed true

# In a target environment:
pac solution import --path .\solution\QualityManagement_managed.zip
# then rebind connection references to that environment's F&O connection.
```

## What to commit
- ✅ `canvas-app/` specs + `canvas-app/src` (unpacked YAML)
- ✅ `flows/` definitions (this repo's markdown) — and, once packaged, the solution zips if you
  want binary releases tracked (they're currently git‑ignored; remove the `*.zip` ignore to keep
  them).
- ❌ `*.msapp` (rebuildable from `src`).
