New-Item -ItemType Directory -Force -Path Build | Out-Null
aftman run rojo build --output Build/DarkDuty.rbxlx
