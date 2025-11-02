\
    #!/usr/bin/env bash
    set -euo pipefail
    aftman init || true
    aftman add rojo-rbx/rojo
    aftman add UpliftGames/wally
    aftman add Kampfkarren/selene
    aftman add JohnnyMorganz/StyLua
    aftman install
