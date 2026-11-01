#!/usr/bin/env bash
#
# Regression harness for the route access check (internal/routing/access_policy.cfc) and its
# project setting this.moopa_validated_without_login (application.cfc _validatedWithoutLogin,
# docs/route-access.md). Runs CFML cases on RustCFML with a stub application.lib.auth and a
# session built per case, and checks who may open which open_to level, with the setting off (the
# default) and on. No case reaches the moo_route_permission query, so no database is needed.
#
# Run from Moopa's root, with RustCFML's binary on PATH or named by RUSTCFML:
#   bash scripts/test_access_policy.sh
#   RUSTCFML=~/dev/RustCFML/target/release/rustcfml bash scripts/test_access_policy.sh

set -euo pipefail

rustcfml="${RUSTCFML:-rustcfml}"
if ! command -v "$rustcfml" > /dev/null 2>&1; then
  printf 'RustCFML not found: put rustcfml on PATH or set RUSTCFML to its binary\n' >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Moopa's components by their dotted paths (moopa.application, moopa.internal.routing.access_policy)
ln -s "$PWD" "$tmpdir/moopa"

# application.cfc with its startup check reachable, for the setting's validation
cat > "$tmpdir/probe_app.cfc" <<'CFML'
<cfcomponent extends="moopa.application" output="false">
    <cffunction name="validatedWithoutLogin" access="public" returntype="boolean" output="false">
        <cfreturn _validatedWithoutLogin() />
    </cffunction>
</cfcomponent>
CFML

# application.lib.auth as a project defines it, answering from request.auth_stub
cat > "$tmpdir/auth_stub.cfc" <<'CFML'
<cfcomponent output="false">
    <cffunction name="isLoggedIn" returntype="boolean" output="false"><cfreturn request.auth_stub.logged_in /></cffunction>
    <cffunction name="isValidated" returntype="boolean" output="false"><cfreturn request.auth_stub.validated /></cffunction>
    <cffunction name="isSysAdmin" returntype="boolean" output="false"><cfreturn request.auth_stub.sysadmin /></cffunction>
</cfcomponent>
CFML

cat > "$tmpdir/cases.cfm" <<'CFML'
<cfscript>
    application.app_name = "hub";
    application.lib = { auth: createObject("component", "auth_stub") };
    policy = createObject("component", "moopa.internal.routing.access_policy").init();

    // access(setting, open_to, logged_in, validated, profile_app): what checkAccess answers
    // for a GET on a route open to open_to. profile_app "" is a session with no profile.
    function access(required boolean setting, required string open_to, required boolean logged_in,
                    required boolean validated, required string profile_app) {
        application.moopa_validated_without_login = arguments.setting;
        request.auth_stub = { logged_in: arguments.logged_in, validated: arguments.validated, sysadmin: false };
        structDelete(session, "auth");
        if (len(arguments.profile_app)) {
            session.auth = { profile: { id: "00000000-0000-0000-0000-000000000001", app_name: arguments.profile_app } };
        }
        var route_data = { params: {}, stRoute: {
            id: "00000000-0000-0000-0000-000000000002",
            url: "/probe",
            componentPath: "",
            md: { open_to: arguments.open_to },
            endpoints: { GET: { id: "00000000-0000-0000-0000-000000000003" } }
        } };
        return policy.checkAccess(route_data = route_data, endpoint = "GET");
    }

    function expect(required string label, required boolean expected, required boolean actual) {
        writeOutput((arguments.expected EQ arguments.actual ? "PASS" : "FAIL") & "  " & arguments.label
            & (arguments.expected EQ arguments.actual ? "" : " (expected #arguments.expected#, got #arguments.actual#)") & chr(10));
    }

    // Setting off (the default): exactly the access every project has today
    expect("off: validated, not logged in, can't open validated", false, access(false, "validated", false, true, "hub"));
    expect("off: validated and logged in opens validated", true, access(false, "validated", true, true, "hub"));
    expect("off: validated and logged in with another app's profile can't open validated", false, access(false, "validated", true, true, "www"));
    expect("off: anyone opens public", true, access(false, "public", false, false, ""));
    expect("off: logged in opens logged_in", true, access(false, "logged_in", true, false, "hub"));
    expect("off: logged in with another app's profile can't open logged_in", false, access(false, "logged_in", true, true, "www"));

    // Setting on: a validated session with a profile in this app opens validated routes, and nothing more
    expect("on: validated, not logged in, profile in this app opens validated", true, access(true, "validated", false, true, "hub"));
    expect("on: validated, not logged in, another app's profile can't open validated", false, access(true, "validated", false, true, "www"));
    expect("on: validated, not logged in, no profile can't open validated", false, access(true, "validated", false, true, ""));
    expect("on: not validated, not logged in can't open validated", false, access(true, "validated", false, false, "hub"));
    expect("on: validated, not logged in can't open logged_in", false, access(true, "logged_in", false, true, "hub"));
    expect("on: validated, not logged in can't open security", false, access(true, "security", false, true, "hub"));
    expect("on: validated, not logged in can't open bearer without the token", false, access(true, "bearer", false, true, "hub"));
    expect("on: validated and logged in still opens validated", true, access(true, "validated", true, true, "hub"));
    expect("on: anyone still opens public", true, access(true, "public", false, false, ""));

    // The setting's validation at startup
    function setting(value) {
        var app = createObject("component", "probe_app");
        if (!isNull(arguments.value)) {
            app.moopa_validated_without_login = arguments.value;
        }
        try {
            return app.validatedWithoutLogin() ? "true" : "false";
        } catch (any e) {
            return e.type;
        }
    }
    function expectSetting(required string label, required string expected, required string actual) {
        writeOutput((arguments.expected EQ arguments.actual ? "PASS" : "FAIL") & "  " & arguments.label
            & (arguments.expected EQ arguments.actual ? "" : " (expected #arguments.expected#, got #arguments.actual#)") & chr(10));
    }
    expectSetting("setting: unset is false", "false", setting());
    expectSetting("setting: true is true", "true", setting(true));
    expectSetting("setting: false is false", "false", setting(false));
    expectSetting("setting: ""true"" is true", "true", setting("true"));
    expectSetting("setting: ""yes"" stops the app starting", "moopa.config.invalidValidatedWithoutLogin", setting("yes"));
    expectSetting("setting: 1 stops the app starting", "moopa.config.invalidValidatedWithoutLogin", setting(1));
    expectSetting("setting: """" stops the app starting", "moopa.config.invalidValidatedWithoutLogin", setting(""));
    expectSetting("setting: a struct stops the app starting", "moopa.config.invalidValidatedWithoutLogin", setting({ production: true }));
</cfscript>
CFML

cd "$tmpdir"
"$rustcfml" cases.cfm > "$tmpdir/out" 2>&1 || true
sed -e 's/^[[:space:]]*//' -e '/^$/d' "$tmpdir/out" | tee "$tmpdir/results"

passes="$(grep -c '^PASS' "$tmpdir/results" || true)"
failures="$(grep -c '^FAIL' "$tmpdir/results" || true)"
if [ "$failures" -gt 0 ] || [ "$passes" -eq 0 ] || grep -qv '^\(PASS\|FAIL\)' "$tmpdir/results"; then
  printf '\n%d case(s) failed, or the run stopped early (see above)\n' "$failures"
  exit 1
fi
printf '\nAll %d cases passed\n' "$passes"
