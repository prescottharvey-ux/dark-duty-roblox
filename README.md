# Dark Duty — Roblox + Rojo + Git setup

## 1) Install Aftman (one-time)
Windows (PowerShell): https://github.com/LPGhatguy/aftman#installation
macOS (Homebrew): `brew install aftman`

## 2) Install project tools
PowerShell:
```powershell
./scripts/setup-tools.ps1
```
macOS/Linux:
```bash
chmod +x scripts/setup-tools.sh
./scripts/setup-tools.sh
```

## 3) (Optional) Install Wally packages
```bash
aftman run wally install
```

## 4) Run Rojo
```bash
aftman run rojo serve --port 34872
```
In Roblox Studio → Plugins → Rojo → Connect to `localhost:34872`.

## 5) Git/GitHub
```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin <your-repo-url>
git push -u origin main
```

## 6) ChatGPT & Codex access
- In ChatGPT: Settings → Connectors → GitHub → authorize → select this repo.
- Tell ChatGPT the repo/branch you want it to read.
- (Optional) Use Codex CLI locally to act on this repo.

## Scripts
- `scripts/dev.ps1` — run Rojo server
- `scripts/build.ps1` — build a .rbxlx to `Build/`
- `scripts/format.ps1` — run StyLua
- `scripts/lint.ps1` — run Selene
