<cfsilent>
<!---
    Regression harness for application.cfc's OnRequest: which pages are Moopa's ways in, and which
    route each runs (docs/routing.md). The route is the request's path, never a ?route= the visitor
    chose; a page elsewhere named index.cfm or _moopa.cfm isn't a way in. No database needed.

    Run from Moopa's root:
        bash scripts/test_front_door.sh
--->
<cfscript>
    probe = createObject("component", "moopa.scripts.front_door_test.Probe");

    // Each case: the page the engine resolved, the url.route it arrived with ("" for none), and the
    // route Moopa should run ("" when the page isn't a way in and runs as itself).
    cases = [
        { page: "/index.cfm",       route: "",               expect: "/",              label: "/ runs the home page" },
        { page: "/index.cfm",       route: "/sysadmin/",     expect: "/",              label: "/?route=/sysadmin/ still runs the home page" },
        { page: "\index.cfm",       route: "/sysadmin/",     expect: "/",              label: "a backslashed index.cfm is the home page too" },
        { page: "/_moopa.cfm",      route: "/login/",        expect: "/login/",        label: "the fallback runs the path it put in url.route" },
        { page: "/_moopa.cfm",      route: "",               expect: "/",              label: "_moopa.cfm with no route runs /" },
        { page: "/a/b/index.cfm",   route: "/sysadmin/",     expect: "",               label: "a deeper index.cfm isn't a way in" },
        { page: "/a/_moopa.cfm",    route: "/sysadmin/",     expect: "",               label: "a deeper _moopa.cfm isn't a way in" },
        { page: "/xindex.cfm",      route: "/sysadmin/",     expect: "",               label: "a page merely ending in index.cfm isn't a way in" }
    ];

    lines = [];
    failed = 0;
    for (c in cases) {
        structClear(url);
        if (len(c.route)) {
            url.route = c.route;
        }
        structDelete(request, "front_door_route");
        try {
            probe.OnRequest(c.page);
        } catch (any e) {
            // Not a way in: OnRequest includes the page itself, which doesn't exist here.
        }
        ran = request.front_door_route ?: "";
        ok = (ran EQ c.expect);
        if (NOT ok) {
            failed++;
        }
        arrayAppend(lines, (ok ? "PASS" : "FAIL") & "  " & c.label & (ok ? "" : " (ran: " & (len(ran) ? ran : "nothing") & ")"));
    }

    // OnRequestStart reads url.route for the restart redirect and the running-request record before
    // OnRequest runs, so the home page's route is already / there.
    structClear(url);
    url.route = "/sysadmin/";
    structDelete(request, "front_door_started_route");
    probe.OnRequestStart("/index.cfm");
    started = request.front_door_started_route ?: "";
    ok = (started EQ "/");
    if (NOT ok) {
        failed++;
    }
    arrayAppend(lines, (ok ? "PASS" : "FAIL") & "  /?route=/sysadmin/ is counted, and sent to /restarting/, as /" & (ok ? "" : " (was: " & started & ")"));
</cfscript>
</cfsilent><cfoutput>#arrayToList(lines, chr(10))#
</cfoutput><cfif failed GT 0><cfthrow message="front door harness failed" /></cfif>
