#!/usr/bin/env bash
# Exports the Web build to build/web and lets it run over plain http on the
# local network (Godot refuses non-HTTPS origins other than localhost, but
# this no-threads build doesn't actually need a secure context).
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-D:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe}"
mkdir -p build/web
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
python - <<'EOF'
p = "build/web/index.html"
s = open(p, encoding="utf-8").read()
anchor = "const missing = Engine.getMissingFeatures({"
patch = "\n\tfor (let i = missing.length - 1; i >= 0; i--) { if (missing[i].startsWith('Secure Context')) missing.splice(i, 1); }"
i = s.index(anchor)
j = s.index("});", i) + 3
if patch not in s:
    s = s[:j] + patch + s[j:]
    open(p, "w", encoding="utf-8").write(s)
print("patched index.html for LAN play")
EOF
