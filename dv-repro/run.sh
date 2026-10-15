#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
OUT="$ROOT/output"
TMPBASE="${RUNNER_TEMP:-/tmp}/dv-repro-${GITHUB_RUN_ID:-local}-${GITHUB_JOB:-job}"
mkdir -p "$OUT" "$TMPBASE" "$ROOT/gradle"
unset GRADLE_RO_DEP_CACHE
unset GRADLE_USER_HOME

echo "=== Gradle ==="
gradle --version
echo "=== Java ==="
java -version
echo "=== Root ==="
echo "$ROOT"

MODE=default
run_gradle() {
    local home="$1"
    shift
    local opts=(--no-daemon --console plain --project-dir "$ROOT" --gradle-user-home "$home")
    if [[ "$MODE" == "pomOnly" ]]; then opts+=(-PpomOnly); fi
    gradle "${opts[@]}" "$@"
}

for MODE in default pomOnly; do
    mkdir -p "$OUT/$MODE"
    echo "=== MODE: $MODE ==="
    for ARM in cold warm refresh; do
        LOGDIR="$OUT/$MODE/$ARM"
        HOME_PATH="$TMPBASE/$MODE/$ARM/home"
        mkdir -p "$LOGDIR" "$HOME_PATH"
        rm -f "$ROOT/gradle/verification-metadata.xml"
        if [[ "$ARM" != cold ]]; then
            echo "Pre-warm: $MODE $ARM"
            if run_gradle "$HOME_PATH" resolveDependencies > "$LOGDIR/prewarm.log" 2>&1; then
                echo "0" > "$LOGDIR/prewarm_exit.txt"
            else
                echo "$?" > "$LOGDIR/prewarm_exit.txt"
                echo "PREWARM FAILED: $MODE $ARM"
                tail -50 "$LOGDIR/prewarm.log"
                exit 2
            fi
        fi
        EXTRA_ARGS=()
        if [[ "$ARM" == "refresh" ]]; then EXTRA_ARGS+=(--refresh-dependencies); fi
        echo "Generate: $MODE $ARM"
        if run_gradle "$HOME_PATH" --write-verification-metadata sha256 "${EXTRA_ARGS[@]}" resolveDependencies > "$LOGDIR/generate.log" 2>&1; then
            echo "0" > "$LOGDIR/generate_exit.txt"
        else
            echo "$?" > "$LOGDIR/generate_exit.txt"
            echo "GENERATION FAILED: $MODE $ARM"
            tail -75 "$LOGDIR/generate.log"
            exit 3
        fi
        if [[ ! -s "$ROOT/gradle/verification-metadata.xml" ]]; then
            echo "MISSING VERIFICATION XML after $MODE $ARM"
            exit 4
        fi
        cp "$ROOT/gradle/verification-metadata.xml" "$LOGDIR/verification-metadata.xml"
    done

    for ARM in cold warm refresh; do
        LOGDIR="$OUT/$MODE/$ARM"
        cp "$LOGDIR/verification-metadata.xml" "$ROOT/gradle/verification-metadata.xml"
        for CHECK in same_home independent_resolve independent_build; do
            if [[ "$CHECK" == same_home ]]; then
                VERIFY_HOME="$TMPBASE/$MODE/$ARM/home"
                TEST_ARGS=(resolveDependencies)
            elif [[ "$CHECK" == independent_resolve ]]; then
                VERIFY_HOME="$TMPBASE/$MODE/$ARM/independent_resolve"
                TEST_ARGS=(resolveDependencies)
            else
                VERIFY_HOME="$TMPBASE/$MODE/$ARM/independent_build"
                TEST_ARGS=(--no-build-cache --no-configuration-cache --rerun-tasks build)
            fi
            mkdir -p "$VERIFY_HOME"
            echo "STRICT: $MODE $ARM $CHECK"
            if run_gradle "$VERIFY_HOME" --dependency-verification strict "${TEST_ARGS[@]}" > "$LOGDIR/$CHECK.log" 2>&1; then
                printf '0\n' > "$LOGDIR/${CHECK}_exit.txt"
            else
                printf '%s\n' "$?" > "$LOGDIR/${CHECK}_exit.txt"
            fi
            cat "$LOGDIR/${CHECK}_exit.txt"
            tail -10 "$LOGDIR/$CHECK.log"
        done
    done
done

python3 - "$OUT" <<'PY'
import sys,os,json,xml.etree.ElementTree as ET
base=sys.argv[1]
for mode in ('default','pomOnly'):
    report={'mode':mode,'arms':{},'comparisons':{}}
    for arm in ('cold','warm','refresh'):
        p=os.path.join(base,mode,arm)
        xml=os.path.join(p,'verification-metadata.xml')
        root=ET.parse(xml).getroot()
        entries=set()
        for comp in root.iter():
            if not comp.tag.endswith('}component'): continue
            gav=':'.join([comp.get('group'),comp.get('name'),comp.get('version')])
            for artifact in comp:
                if not artifact.tag.endswith('}artifact'): continue
                cs=next((v.get('value') for v in artifact if v.tag.endswith('}sha256')),None)
                entries.add((gav,artifact.get('name'),cs))
        report['arms'][arm]={'entries':len(entries),'junit_bom':[list(x) for x in sorted(entries) if 'org.junit:junit-bom:' in x[0]],'parent_poms':[list(x) for x in sorted(entries) if any(y in x[0] for y in ('commons-parent:', 'org.apache:apache:','mojo-parent:'))],'strict_exit_codes':{name:open(os.path.join(p,name+'_exit.txt')).read().strip() for name in ('same_home','independent_resolve','independent_build')}}
        report['arms'][arm]['_entries']=entries
    cold=report['arms']['cold']['_entries']
    for arm in ('warm','refresh'):
        current=report['arms'][arm]['_entries']
        report['comparisons'][f'cold_minus_{arm}']=[list(x) for x in sorted(cold-current)]
        report['comparisons'][f'{arm}_minus_cold']=[list(x) for x in sorted(current-cold)]
    for d in report['arms'].values():d.pop('_entries')
    with open(os.path.join(base,mode,'summary.json'),'w') as f:json.dump(report,f,indent=2,ensure_ascii=False)
    print('=== COMPARISON '+mode+' ===')
    print(json.dumps(report,indent=2,ensure_ascii=False)[:22000])
PY
echo "=== END reproducible experiment ==="
