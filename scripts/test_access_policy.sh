#!/usr/bin/env bash
#
# Regression harness for the route access check (internal/routing/access_policy.cfc), the project
# settings this.moopa_validated_without_login and this.moopa_validated_session_check, and the
# once-a-minute check of a session validated without a login (application.cfc
# _validatedWithoutLogin, _validatedSessionCheck, _checkValidatedSession; docs/route-access.md).
#
# Runs CFML cases on RustCFML with a stub application.lib.auth, a stub project lib for the session
# check, and a session built per case. The stay-signed-in device test (_deviceStillThere) is
# stubbed too, and no case reaches the moo_route_permission query, so no database is needed.
#
# The run passes only when RustCFML exits cleanly, every case passes, and exactly EXPECTED_CASES
# ran to the end marker: a run that stops part way fails.
#
# Run from Moopa's root, with RustCFML's binary on PATH or named by RUSTCFML:
#   bash scripts/test_access_policy.sh
#   RUSTCFML=~/dev/RustCFML/target/release/rustcfml bash scripts/test_access_policy.sh

set -euo pipefail

EXPECTED_CASES=52

rustcfml="${RUSTCFML:-rustcfml}"
if ! command -v "$rustcfml" > /dev/null 2>&1; then
  printf 'RustCFML not found: put rustcfml on PATH or set RUSTCFML to its binary\n' >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Moopa's components by their dotted paths (moopa.application, moopa.internal.routing.access_policy)
ln -s "$PWD" "$tmpdir/moopa"

# application.cfc with its startup checks and the session check reachable, and the device test
# answering from request.device_present instead of the database
cat > "$tmpdir/probe_app.cfc" <<'CFML'
<cfcomponent extends="moopa.application" output="false">
    <cffunction name="validatedWithoutLogin" access="public" returntype="boolean" output="false">
        <cfreturn _validatedWithoutLogin() />
    </cffunction>
    <cffunction name="validatedSessionCheck" access="public" returntype="string" output="false">
        <cfreturn _validatedSessionCheck() />
    </cffunction>
    <cffunction name="checkValidatedSession" access="public" returntype="void" output="false">
        <cfset _checkValidatedSession() />
    </cffunction>
    <cffunction name="_deviceStillThere" access="private" returntype="boolean" output="false">
        <cfargument name="device_id" type="string" required="true" />
        <cfset request.device_checks += 1 />
        <cfreturn request.device_present />
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

# A project lib backing validation with its own records: request.backing_valid says whether the
# record behind the session still stands
cat > "$tmpdir/backing_stub.cfc" <<'CFML'
<cfcomponent output="false">
    <cffunction name="check" access="public" output="false">
        <cfargument name="auth" type="struct" required="true" />
        <cfset request.hook_calls += 1 />
        <cfset request.hook_profile = arguments.auth.profile.id ?: "" />
        <cfreturn request.backing_valid />
    </cffunction>
    <cffunction name="hidden" access="private" returntype="boolean" output="false"><cfreturn true /></cffunction>
</cfcomponent>
CFML

cat > "$tmpdir/cases.cfm" <<'CFML'
<cfscript>
    application.app_name = "hub";
    application.lib = { auth: createObject("component", "auth_stub"), backing: createObject("component", "backing_stub") };
    policy = createObject("component", "moopa.internal.routing.access_policy").init();
    app = createObject("component", "probe_app");
    cases = 0;

    // signIn(logged_in, validated, profile_app): a session as the project leaves it. profile_app ""
    // is a session with no profile.
    function signIn(required boolean logged_in, required boolean validated, required string profile_app) {
        request.auth_stub = { logged_in: arguments.logged_in, validated: arguments.validated, sysadmin: false };
        structDelete(session, "auth");
        if (len(arguments.profile_app)) {
            session.auth = { profile: { id: "00000000-0000-0000-0000-000000000001", app_name: arguments.profile_app } };
        }
    }

    // opens(open_to, endpoint_open_to): what checkAccess answers for this session on a GET of a
    // route open to open_to, whose GET endpoint declares endpoint_open_to ("" for none)
    function opens(required string open_to, string endpoint_open_to = "") {
        var endpoint = { id: "00000000-0000-0000-0000-000000000003" };
        if (len(arguments.endpoint_open_to)) {
            endpoint.open_to = arguments.endpoint_open_to;
        }
        var route_data = { params: {}, stRoute: {
            id: "00000000-0000-0000-0000-000000000002",
            url: "/probe",
            componentPath: "",
            md: { open_to: arguments.open_to },
            endpoints: { GET: endpoint }
        } };
        return policy.checkAccess(route_data = route_data, endpoint = "GET");
    }

    // access(setting, open_to, logged_in, validated, profile_app[, endpoint_open_to])
    function access(required boolean setting, required string open_to, required boolean logged_in,
                    required boolean validated, required string profile_app, string endpoint_open_to = "") {
        application.moopa_validated_without_login = arguments.setting;
        signIn(arguments.logged_in, arguments.validated, arguments.profile_app);
        return opens(arguments.open_to, arguments.endpoint_open_to);
    }

    function expect(required string label, required any expected, required any actual) {
        cases += 1;
        var ok = toString(arguments.expected) EQ toString(arguments.actual);
        writeOutput((ok ? "PASS" : "FAIL") & "  " & arguments.label
            & (ok ? "" : " (expected #arguments.expected#, got #arguments.actual#)") & chr(10));
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

    // An endpoint's open_to wins over its route's, both ways
    expect("endpoint public on a security route opens to anyone", true, access(false, "security", false, false, "", "public"));
    expect("endpoint security on a public route refuses anyone", false, access(false, "public", false, false, "", "security"));
    expect("on: endpoint validated on a security route opens to a validated session", true, access(true, "security", false, true, "hub", "validated"));
    expect("on: endpoint security on a validated route refuses a validated session", false, access(true, "validated", false, true, "hub", "security"));
    expect("on: endpoint logged_in on a validated route refuses a validated session", false, access(true, "validated", false, true, "hub", "logged_in"));
    expect("off: endpoint validated on a security route refuses a validated session", false, access(false, "security", false, true, "hub", "validated"));

    // The once-a-minute check of a validated session without a login
    // check(setting, hook, device_id, checked_ago, backing_valid, device_present): runs the check
    // on a validated session (not logged in, profile in this app) last checked checked_ago seconds
    // ago (-1: never), then leaves request.hook_calls, request.device_checks and the session.
    function check(required boolean setting, required string hook, required string device_id, required numeric checked_ago,
                   any backing_valid = true, boolean device_present = true) {
        application.moopa_validated_without_login = arguments.setting;
        application.moopa_validated_session_check = arguments.hook;
        request.backing_valid = arguments.backing_valid;
        request.device_present = arguments.device_present;
        request.hook_calls = 0;
        request.device_checks = 0;
        if (arguments.checked_ago GTE 0) {
            session.auth.validated_checked_at = dateAdd("s", -arguments.checked_ago, now());
        }
        if (len(arguments.device_id)) {
            session.auth.device_id = arguments.device_id;
        }
        app.checkValidatedSession();
    }

    // A record behind the session is revoked: the session still opens until its next check, and not after it
    signIn(false, true, "hub");
    check(true, "backing.check", "", -1, true);
    expect("hook: a backed session is checked on its first request and kept", "1 true", request.hook_calls & " " & opens("validated"));
    expect("hook: the check passes the session's auth", "00000000-0000-0000-0000-000000000001", request.hook_profile);
    check(true, "backing.check", "", 30, false);
    expect("hook: revoked within the minute, not yet checked, still opens", "0 true", request.hook_calls & " " & opens("validated"));
    check(true, "backing.check", "", 61, false);
    expect("hook: revoked, the next check ends the session's auth", "1 false", request.hook_calls & " " & structKeyExists(session, "auth"));
    expect("hook: revoked, validated routes no longer open", false, opens("validated"));

    signIn(false, true, "hub");
    check(true, "backing.check", "", 61, true);
    expect("hook: a passing check keeps the session", "1 true", request.hook_calls & " " & opens("validated"));
    expect("hook: a passing check restarts the minute", true, dateDiff("s", session.auth.validated_checked_at, now()) LT 5);

    // A session with a stay-signed-in device is checked by its device, not the hook
    signIn(false, true, "hub");
    check(true, "backing.check", "device-1", 61, false, true);
    expect("device: a device still there keeps the session, hook not asked", "1 0 true", request.device_checks & " " & request.hook_calls & " " & opens("validated"));
    check(true, "backing.check", "device-1", 61, true, false);
    expect("device: a device signed out ends the session's auth", "1 0 false", request.device_checks & " " & request.hook_calls & " " & structKeyExists(session, "auth"));

    // Neither a device nor a hook: the project owns the session's lifetime
    signIn(false, true, "hub");
    check(true, "", "", 61);
    expect("neither: kept, nothing asked", "0 0 true", request.device_checks & " " & request.hook_calls & " " & opens("validated"));

    // Sessions the check leaves alone
    signIn(false, true, "hub");
    check(false, "backing.check", "device-1", 61, false, false);
    expect("off: nothing checked, the session is as it was", "0 0 true", request.device_checks & " " & request.hook_calls & " " & structKeyExists(session, "auth"));
    signIn(true, true, "hub");
    check(true, "backing.check", "", 61, false);
    expect("on: a logged-in session is left to the login's own device check", "0 true", request.hook_calls & " " & structKeyExists(session, "auth"));
    signIn(false, false, "hub");
    check(true, "backing.check", "", 61, false);
    expect("on: a session that isn't validated isn't checked", "0 true", request.hook_calls & " " & structKeyExists(session, "auth"));
    signIn(false, true, "www");
    check(true, "backing.check", "", 61, false);
    expect("on: another app's profile isn't checked", "0 true", request.hook_calls & " " & structKeyExists(session, "auth"));

    // A hook that answers something other than true or false fails loudly
    signIn(false, true, "hub");
    try {
        check(true, "backing.check", "", 61, "maybe");
        expect("hook: a non-boolean answer throws", "moopa.config.invalidValidatedSessionCheck", "no error");
    } catch (any e) {
        expect("hook: a non-boolean answer throws", "moopa.config.invalidValidatedSessionCheck", e.type);
    }

    // The settings' validation at startup
    function startup(required string which, any without_login, any session_check, boolean without_login_on = true) {
        var probe = createObject("component", "probe_app");
        application.moopa_validated_without_login = arguments.without_login_on;
        if (!isNull(arguments.without_login)) {
            probe.moopa_validated_without_login = arguments.without_login;
        }
        if (!isNull(arguments.session_check)) {
            probe.moopa_validated_session_check = arguments.session_check;
        }
        try {
            return arguments.which EQ "without_login"
                ? (probe.validatedWithoutLogin() ? "true" : "false")
                : "[" & probe.validatedSessionCheck() & "]";
        } catch (any e) {
            return e.type;
        }
    }
    bad_setting = "moopa.config.invalidValidatedWithoutLogin";
    expect("setting: unset is false", "false", startup("without_login"));
    expect("setting: true is true", "true", startup("without_login", true));
    expect("setting: false is false", "false", startup("without_login", false));
    expect("setting: ""true"" is true", "true", startup("without_login", "true"));
    expect("setting: ""yes"" stops the app starting", bad_setting, startup("without_login", "yes"));
    expect("setting: 1 stops the app starting", bad_setting, startup("without_login", 1));
    expect("setting: """" stops the app starting", bad_setting, startup("without_login", ""));
    expect("setting: a struct stops the app starting", bad_setting, startup("without_login", { production: true }));

    bad_check = "moopa.config.invalidValidatedSessionCheck";
    expect("session check: unset is none", "[]", startup("session_check"));
    expect("session check: a lib's public method is used", "[backing.check]", startup("session_check", nullValue(), "backing.check"));
    expect("session check: set without validated-without-login stops the app starting", bad_check, startup("session_check", nullValue(), "backing.check", false));
    expect("session check: a missing method stops the app starting", bad_check, startup("session_check", nullValue(), "backing.nope"));
    expect("session check: a private method stops the app starting", bad_check, startup("session_check", nullValue(), "backing.hidden"));
    expect("session check: a missing lib stops the app starting", bad_check, startup("session_check", nullValue(), "nolib.check"));
    expect("session check: a name without a method stops the app starting", bad_check, startup("session_check", nullValue(), "backing"));
    expect("session check: a struct stops the app starting", bad_check, startup("session_check", nullValue(), { lib: "backing" }));

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
