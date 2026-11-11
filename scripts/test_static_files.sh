#!/usr/bin/env bash
#
# Regression harness for serving Moopa's static files (internal/static/static_files.cfc) and the
# project setting this.moopa_anonymous_static_path (application.cfc _anonymousStaticPath;
# docs/design.md, Serving the static files).
#
# Runs CFML cases on RustCFML against a fixture static/ folder (a stylesheet linking fonts beside
# it, a script, a vendored folder), then checks that Moopa's own static/ never names Moopa: a
# project serving it anonymously relies on that.
#
# The run passes only when RustCFML exits cleanly, every case passes, and exactly EXPECTED_CASES
# ran to the end marker: a run that stops part way fails.
#
# Run from Moopa's root, with RustCFML's binary on PATH or named by RUSTCFML:
#   bash scripts/test_static_files.sh
#   RUSTCFML=~/dev/RustCFML/target/release/rustcfml bash scripts/test_static_files.sh

set -euo pipefail

EXPECTED_CASES=34

# Moopa's own static files never name it: an anonymous project's pages load them
if grep -rli "moopa" static; then
  printf '\nThe files above, under static/, name Moopa: an anonymous project serves them as they are\n' >&2
  exit 1
fi
printf 'PASS  static/ never names Moopa\n'

rustcfml="${RUSTCFML:-rustcfml}"
if ! command -v "$rustcfml" > /dev/null 2>&1; then
  printf 'RustCFML not found: put rustcfml on PATH or set RUSTCFML to its binary\n' >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Moopa's components by their dotted paths (moopa.application, moopa.internal.static.static_files)
ln -s "$PWD" "$tmpdir/moopa"

# A static/ folder: a stylesheet at the top linking a vendored font, and one in a vendored folder
# linking its fonts relatively, quoted and bare, with a query and a fragment
mkdir -p "$tmpdir/fixture/vendor/icons-1.0/css" "$tmpdir/fixture/vendor/icons-1.0/webfonts" "$tmpdir/broken"
printf 'body { color: red; background: url("data:image/svg+xml;utf8,<svg xmlns=%s/>"); }\n.logo { background: url(/elsewhere/logo.png); }\n@font-face { src: url(vendor/icons-1.0/webfonts/solid.woff2); }\n' "'x'" > "$tmpdir/fixture/moopa.css"
printf 'window.answer = 42;\n' > "$tmpdir/fixture/moopa.js"
printf '@font-face { src: url(../webfonts/solid.woff2) format("woff2"), url("../webfonts/regular.woff2?v=1#iefix"); }\n' > "$tmpdir/fixture/vendor/icons-1.0/css/icons.css"
printf 'solid-font' > "$tmpdir/fixture/vendor/icons-1.0/webfonts/solid.woff2"
printf 'regular-font' > "$tmpdir/fixture/vendor/icons-1.0/webfonts/regular.woff2"
printf 'licence' > "$tmpdir/fixture/vendor/icons-1.0/LICENSE"
# A stylesheet linking a file that isn't there
printf '.x { background: url(missing.png); }\n' > "$tmpdir/broken/broken.css"

# application.cfc with its startup check of the setting reachable
cat > "$tmpdir/probe_app.cfc" <<'CFML'
<cfcomponent extends="moopa.application" output="false">
    <cffunction name="anonymousStaticPath" access="public" returntype="string" output="false">
        <cfreturn _anonymousStaticPath() />
    </cffunction>
</cfcomponent>
CFML

cat > "$tmpdir/cases.cfm" <<'CFML'
<cfscript>
    cases = 0;
    root = getDirectoryFromPath(getCurrentTemplatePath()) & "fixture";

    function expect(required string label, required any expected, required any actual) {
        cases += 1;
        var ok = toString(arguments.expected) EQ toString(arguments.actual);
        writeOutput((ok ? "PASS" : "FAIL") & "  " & arguments.label
            & (ok ? "" : " (expected #arguments.expected#, got #arguments.actual#)") & chr(10));
    }

    function files(required string anonymous_path, string folder = root) {
        return createObject("component", "moopa.internal.static.static_files").init(
            root = arguments.folder, anonymous_path = arguments.anonymous_path, development = false);
    }

    // The error type a call throws, or "none"
    function thrown(required any call) {
        try {
            arguments.call();
            return "none";
        } catch (any e) {
            return e.type;
        }
    }

    // Plain: at /_moopa/static/ under the files' own names, as every project has them today
    plain = files("");
    plainCss = plain.urlFor("moopa.css");
    expect("plain: a URL keeps the file's name", true, plainCss.startsWith("/_moopa/static/moopa.css?v="));
    expect("plain: a vendored file keeps its folder", true, plain.urlFor("vendor/icons-1.0/css/icons.css").startsWith("/_moopa/static/vendor/icons-1.0/css/icons.css?v="));
    expect("plain: a missing file throws", "moopa.static.notFound", thrown(() => plain.urlFor("nope.css")));
    expect("plain: a file with no known extension throws", "moopa.static.notFound", thrown(() => plain.urlFor("vendor/icons-1.0/LICENSE")));
    expect("plain: owns /_moopa/static/", true, plain.owns("/_moopa/static/moopa.css"));
    expect("plain: doesn't own a route", false, plain.owns("/orders"));
    found = plain.lookup("/_moopa/static/moopa.css", true);
    expect("plain: a ?v= URL is the file, kept a year", "#root#/moopa.css|true", found.file & "|" & found.immutable);
    expect("plain: without ?v= it is re-checked", false, plain.lookup("/_moopa/static/moopa.css", false).immutable);
    expect("plain: a vendored file is kept a year without ?v=", true, plain.lookup("/_moopa/static/vendor/icons-1.0/css/icons.css", false).immutable);
    expect("plain: a missing file is none", true, structIsEmpty(plain.lookup("/_moopa/static/nope.css", true)));
    expect("plain: a climbing path is none", true, structIsEmpty(plain.lookup("/_moopa/static/../application.cfc", true)));

    // Anonymous: at the project's path under names made from each file's content
    anon = files("/_ui");
    css = anon.urlFor("moopa.css");
    js = anon.urlFor("moopa.js");
    icons = anon.urlFor("vendor/icons-1.0/css/icons.css");
    solid = anon.urlFor("vendor/icons-1.0/webfonts/solid.woff2");
    regular = anon.urlFor("vendor/icons-1.0/webfonts/regular.woff2");
    expect("anonymous: a stylesheet is a hash under the path", true, reFind("^/_ui/[0-9a-f]{16}\.css$", css) GT 0);
    expect("anonymous: a script is a hash under the path", true, reFind("^/_ui/[0-9a-f]{16}\.js$", js) GT 0);
    expect("anonymous: a vendored font is a hash under the path", true, reFind("^/_ui/[0-9a-f]{16}\.woff2$", solid) GT 0);
    expect("anonymous: a missing file throws", "moopa.static.notFound", thrown(() => anon.urlFor("nope.css")));
    expect("anonymous: owns its path", true, anon.owns(js));
    expect("anonymous: doesn't own /_moopa/static/", false, anon.owns("/_moopa/static/moopa.css"));
    expect("anonymous: a file by its own name is none", true, structIsEmpty(anon.lookup("/_ui/moopa.css", false)));
    found = anon.lookup(js, false);
    expect("anonymous: a script is its file, kept a year", "#root#/moopa.js|true|text/javascript; charset=utf-8", found.file & "|" & found.immutable & "|" & found.type);
    found = anon.lookup(solid, false);
    expect("anonymous: a font is its file", "#root#/vendor/icons-1.0/webfonts/solid.woff2|font/woff2", found.file & "|" & found.type);
    found = anon.lookup(icons, false);
    expect("anonymous: a stylesheet's relative url()s point at the fonts' names",
        '@font-face { src: url("#solid#") format("woff2"), url("#regular#?v=1##iefix"); }',
        trim(charsetEncode(found.bytes, "utf-8")));
    expect("anonymous: a stylesheet is kept a year", "true|text/css; charset=utf-8", found.immutable & "|" & found.type);
    content = charsetEncode(anon.lookup(css, false).bytes, "utf-8");
    expect("anonymous: a data: url() stays", true, find("url(""data:image/svg+xml;utf8,<svg xmlns='x'/>"")", content) GT 0);
    expect("anonymous: an absolute url() stays", true, find("url(/elsewhere/logo.png)", content) GT 0);
    expect("anonymous: a url() into a vendored folder points at its name", true, find("url(""#solid#"")", content) GT 0);
    expect("anonymous: the same files get the same names", css & js, files("/_ui").urlFor("moopa.css") & files("/_ui").urlFor("moopa.js"));
    broken = files("/_ui", getDirectoryFromPath(getCurrentTemplatePath()) & "broken");
    expect("anonymous: a url() to a missing file throws", "moopa.static.unresolvedUrl", thrown(() => broken.urlFor("broken.css")));

    // The setting, as onApplicationStart reads it
    function startup(any setting) {
        var probe = createObject("component", "probe_app");
        if (!isNull(arguments.setting)) {
            probe.moopa_anonymous_static_path = arguments.setting;
        }
        try {
            return "[" & probe.anonymousStaticPath() & "]";
        } catch (any e) {
            return e.type;
        }
    }
    bad = "moopa.config.invalidAnonymousStaticPath";
    expect("setting: unset is plain", "[]", startup());
    expect("setting: a path is used", "[/_ui]", startup("/_ui"));
    expect("setting: a deeper path is used", "[/assets/ui]", startup("/assets/ui"));
    expect("setting: a trailing slash stops the app starting", bad, startup("/_ui/"));
    expect("setting: a relative path stops the app starting", bad, startup("_ui"));
    expect("setting: a climbing path stops the app starting", bad, startup("/_ui/../x"));
    expect("setting: a struct stops the app starting", bad, startup({ path: "/_ui" }));

    writeOutput("DONE #cases#" & chr(10));
</cfscript>
CFML

cd "$tmpdir"
status=0
"$rustcfml" cases.cfm > "$tmpdir/out" 2>&1 || status=$?
sed -e 's/^[[:space:]]*//' -e '/^$/d' "$tmpdir/out" | grep -v '^DONE ' | tee "$tmpdir/results" || true

failures="$(grep -c '^FAIL' "$tmpdir/results" || true)"
done_line="$(grep -E '^[[:space:]]*DONE [0-9]+$' "$tmpdir/out" | tr -d '[:space:]' || true)"
if [ "$status" -ne 0 ]; then
  printf '\nRustCFML exited with status %d\n' "$status"
  exit 1
fi
if [ "$done_line" != "DONE$EXPECTED_CASES" ]; then
  printf '\nThe run did not finish its %d cases (end marker: "%s")\n' "$EXPECTED_CASES" "$done_line"
  exit 1
fi
if [ "$failures" -gt 0 ] || grep -qv '^\(PASS\|FAIL\)' "$tmpdir/results"; then
  printf '\n%d case(s) failed, or the run printed something else (see above)\n' "$failures"
  exit 1
fi
printf '\nAll %d cases passed\n' "$EXPECTED_CASES"
