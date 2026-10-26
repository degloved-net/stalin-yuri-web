#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
project="$root/work/project"
source "$root/scripts/paths.sh"

if [[ ! -f "$project/project.godot" ]]; then
    echo 'missing work/project; run scripts/recover.sh first' >&2
    exit 1
fi

ask_path godot 'godot executable' "$(command -v godot || true)"
if ! command -v "$godot" >/dev/null 2>&1; then
    echo 'godot executable not found' >&2
    exit 1
fi

case "$("$godot" --version)" in
    4.7.1.*)
        export_args=(--headless --rendering-method gl_compatibility --export-release)
        errors='^SCRIPT ERROR:|^ERROR:'
        ;;
    *)
        echo 'use Godot 4.7.1 to match the bundled Web export templates' >&2
        exit 1
        ;;
esac

for template in web_nothreads_release.zip web_release.zip; do
    if [[ ! -s "$project/.web-templates/$template" ]]; then
        echo "missing patched template: .web-templates/$template; apply patches/0005-small-web-engine.patch or run scripts/recover.sh" >&2
        exit 1
    fi
done

for preset in web web-threads; do
    output="$root/build/$preset"
    log="$root/work/$preset.log"
    rm -rf -- "$output"
    mkdir -p "$output"

    "$godot" --path "$project" "${export_args[@]}" "$preset" "$output/index.html" 2>&1 | tee "$log"

    # Godot sometimes reports leaked resources while closing the headless editor.
    if grep -E "$errors" "$log" | grep -vE '^ERROR: ([0-9]+ (resources still in use|RID allocations)|Pages in use exist)'; then
        echo "export failed; see $log" >&2
        exit 1
    fi

    for file in index.html index.pck index.wasm; do
        if [[ ! -s "$output/$file" ]]; then
            echo "missing export: $output/$file" >&2
            exit 1
        fi
    done
    wasm_size="$(stat -c %s "$output/index.wasm")"
    if (( wasm_size >= 20000000 )); then
        echo "wasm meeds to be below 20 MB: $output/index.wasm is $wasm_size bytes" >&2
        exit 1
    fi
    cp -- "$project/.web-templates/GODOT-LICENSE.txt" "$project/.web-templates/GODOT-COPYRIGHT.txt" "$output/"
    echo "exported $output"
done
