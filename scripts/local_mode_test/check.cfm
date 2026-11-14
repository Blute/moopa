<cfsilent>
<!---
    Regression harness for application.cfc's _assertModernLocalMode(): Moopa starts in modern local
    mode and refuses to start in classic. Included by modern/run.cfm and classic/run.cfm, each under
    an Application.cfc that sets that mode, with variables.expected_mode naming it. No database needed.

    Run from Moopa's root:
        bash scripts/test_local_mode.sh
--->
<cfscript>
    probe = createObject("component", "moopa.scripts.local_mode_test.Probe");
    thrown = "";
    try {
        probe.check();
    } catch (any e) {
        thrown = e.type;
    }

    if (variables.expected_mode EQ "modern") {
        ok = (thrown EQ "");
        label = "modern local mode: the check passes";
    } else {
        ok = (thrown EQ "moopa.config.classicLocalMode");
        label = "classic local mode: the check throws moopa.config.classicLocalMode";
    }

    // A second run answers the same: a failed check leaves nothing behind in the component.
    again = "";
    try {
        probe.check();
    } catch (any e) {
        again = e.type;
    }
    repeatable = (again EQ thrown);
</cfscript>
</cfsilent><cfoutput>#(ok ? "PASS" : "FAIL")#  #label##(ok ? "" : " (threw: " & (len(thrown) ? thrown : "nothing") & ")")#
#(repeatable ? "PASS" : "FAIL")#  #variables.expected_mode# local mode: a second check answers the same
</cfoutput><cfif NOT (ok AND repeatable)><cfthrow message="local mode harness failed" /></cfif>
