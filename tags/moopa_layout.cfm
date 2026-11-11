<!---
    moopa_layout — Moopa's page shell: the System pages render in it, and a project page may opt in.
    Everything it loads is Moopa's own (moopa.css, moopa.js, Alpine, Font Awesome Free), served from
    code/moopa/static (system.staticUrl(): /_moopa/static/, or the project's anonymous static path);
    nothing comes from another origin.

    <cf_moopa_layout title="Orders">…</cf_moopa_layout>

    The System pages call it as <cfmodule template="/moopa/tags/moopa_layout.cfm">, so a project tag
    of the same name can never stand in for it there.

    Attributes
      title     the page's title, after the project's in the browser tab
      current   the route to mark current in the menus (default: this request's route)
      navs      nav files to show in the sidebar, in order (default: all of the app's, by name)
      head      HTML for <head>, after the stylesheets: a page's own extras (a project's theme is loaded for every
                page by system.stylesheets(); see docs/design.md)
      density   "compact" (default, desk density) or "comfortable"
      chrome    false: no sidebar, for a page shown inside a frame or dialog (default true)

    The sidebar shows the app's menus, then, for a sysadmin, a dividing line and Moopa's System pages
    as a group (application.lib.system.menu(), from sysadmin_nav.json; never one of the app's navs).
    A sysadmin's profile menu has Re-initialise.
--->
<cfif thisTag.executionMode NEQ "end">
    <cfparam name="attributes.title" default="" type="string">
    <cfparam name="attributes.current" default="" type="string">
    <cfparam name="attributes.navs" default="" type="string">
    <cfparam name="attributes.head" default="" type="string">
    <cfparam name="attributes.density" default="compact" type="string">
    <cfparam name="attributes.chrome" default="true" type="boolean">
    <cfreturn>
</cfif>

<cfset pageBody = thisTag.generatedContent />
<cfset thisTag.generatedContent = "" />

<cfset system = application.lib.system />
<cfset signedIn = application.lib.auth.isLoggedIn() />
<cfset showShell = signedIn AND attributes.chrome />
<cfset currentProfile = signedIn ? application.lib.auth.getCurrentProfile() : {} />
<cfset isSysAdmin = signedIn AND application.lib.auth.isSysAdmin() />
<cfset appName = application.app_name ?: "hub" />
<cfset projectTitle = application.project_title ?: "Moopa" />
<cfset appTitle = structKeyExists(application, "app_titles") AND structKeyExists(application.app_titles, appName) ? application.app_titles[appName] : projectTitle />
<cfset appHome = structKeyExists(application, "app_homes") AND structKeyExists(application.app_homes, appName) ? application.app_homes[appName] : "/" />
<!--- The project's logo for the dark panel (application.moopa_theme.logo), else its name --->
<cfset brandLogo = structKeyExists(application, "moopa_theme") AND isStruct(application.moopa_theme) AND structKeyExists(application.moopa_theme, "logo") ? application.moopa_theme.logo : "" />

<!--- The route to mark current in the menus --->
<cfset currentRoute = system.currentRoute(attributes.current) />

<cfset builtNavs = signedIn ? application.lib.db.getService("moo_profile").buildNavs() : {} />
<cfset navNames = len(attributes.navs) ? listToArray(attributes.navs) : structKeyArray(builtNavs) />
<cfif NOT len(attributes.navs)><cfset arraySort(navNames, "textnocase") /></cfif>
<cfset systemItems = system.menu() />
<cfset avatarUrl = signedIn ? system.avatarUrl(currentProfile.id ?: "") : "" />
<cfset impersonated = session.auth.profile ?: {} />
<cfset impersonator = session.auth.impersonator ?: {} />

<cfset initials = "" />
<cfloop list="#currentProfile.full_name ?: ''#" item="namePart" delimiters=" ">
    <cfif len(initials) LT 2 AND len(namePart)><cfset initials &= uCase(left(namePart, 1)) /></cfif>
</cfloop>

<cfoutput><!doctype html>
<html lang="en"<cfif attributes.density EQ "compact"> data-density="compact"</cfif>>
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>#encodeForHTML(projectTitle)#<cfif len(attributes.title)> - #encodeForHTML(attributes.title)#</cfif></title>
    <script>try { if (localStorage.getItem('moo-shell-collapsed') === '1' && !matchMedia('(max-width: 767.98px)').matches) document.documentElement.classList.add('moo-shell-collapsed'); } catch (e) {}</script>
    <!--- Icons, moopa.css and the project's theme (system.stylesheets(), shared with project layouts) --->
    #system.stylesheets()#
    <script src="#system.staticUrl('moopa.js')#"></script>
    #attributes.head#
    <script defer src="#system.staticUrl('vendor/alpine-3.17.5/focus.min.js')#"></script>
    <script defer src="#system.staticUrl('vendor/alpine-3.17.5/alpine.min.js')#"></script>
</head>
<body>
<!--- The project's banner, except inside a frame (chrome=false): the page around the frame shows it already --->
<cfif attributes.chrome>#system.banner()#</cfif>
<!--- Not inside a framed page (chrome=false): the page around the frame shows it already --->
<cfif attributes.chrome AND (session.auth.is_impersonating ?: false)>
    <div class="moo-shell-banner" role="status">
        <i class="fa-solid fa-user-secret"></i>
        <span>Impersonating <strong>#encodeForHTML(impersonated.full_name ?: 'Unknown')#</strong>, by #encodeForHTML(impersonator.full_name ?: 'Unknown')#</span>
        <a class="btn btn-xs" href="/logout/"><i class="fa-solid fa-arrow-right-from-bracket"></i> End session</a>
    </div>
</cfif>
<cfif showShell>
    <div class="moo-shell-backdrop" id="moo-shell-backdrop" aria-hidden="true"></div>
    <div class="moo-shell-mobile-bar">
        <button id="moo-shell-mobile-toggle" type="button" class="moo-shell-icon-button" aria-label="Open sidebar" aria-controls="moo-shell-sidebar" aria-expanded="false"><i class="fa-solid fa-bars"></i></button>
        <cfif len(brandLogo)><img src="#encodeForHTMLAttribute(brandLogo)#" alt="#encodeForHTMLAttribute(projectTitle)#" class="moo-shell-logo moo-shell-logo-mobile" /><cfelse><span>#encodeForHTML(appTitle)#</span></cfif>
    </div>
</cfif>
<div class="moo-shell-root">
<cfif showShell>
    <aside id="moo-shell-sidebar" class="moo-shell-sidebar" aria-label="Primary navigation">
        <div class="moo-shell-brand-row">
            <a class="moo-shell-brand-text" href="#encodeForHTMLAttribute(appHome)#"><cfif len(brandLogo)><img src="#encodeForHTMLAttribute(brandLogo)#" alt="#encodeForHTMLAttribute(projectTitle)#" class="moo-shell-logo" /><cfelse>#encodeForHTML(projectTitle)#</cfif></a>
            <div class="moo-shell-nav-row-wrap">
                <button id="moo-shell-sidebar-toggle" type="button" class="moo-shell-icon-button" aria-label="Collapse sidebar" aria-controls="moo-shell-sidebar" aria-expanded="true">
                    <i class="fa-solid fa-angles-left ico-expanded"></i>
                    <i class="fa-solid fa-angles-right ico-collapsed"></i>
                    <i class="fa-solid fa-xmark ico-mobile"></i>
                </button>
                <span class="moo-shell-nav-tooltip">Open sidebar (Ctrl+.)</span>
            </div>
        </div>

        <nav class="moo-shell-nav">
            <cfset shownNavs = 0 />
            <cfloop array="#navNames#" item="navName">
                <cfif structKeyExists(builtNavs, navName) AND arrayLen(builtNavs[navName])>
                    <cfif shownNavs GT 0><div class="moo-shell-menu-divider"></div></cfif>
                    <cfset shownNavs++ />
                    #system.navHtml(builtNavs[navName], currentRoute)#
                </cfif>
            </cfloop>
            <!--- Moopa's System pages, for sysadmins: their own group after the app's menus, below a line --->
            <cfif arrayLen(systemItems)>
                <div class="moo-shell-nav-system">
                    <div class="moo-shell-menu-divider"></div>
                    #system.navHtml([{ icon: "fa-solid fa-gear", title: "System", items: systemItems }], currentRoute)#
                </div>
            </cfif>
        </nav>

        <div class="moo-shell-profile-menu" id="moo-shell-profile-menu">
            <button id="moo-shell-profile-btn" type="button" class="moo-shell-profile-button" aria-haspopup="menu" aria-expanded="false" aria-controls="moo-shell-profile-dropdown">
                <span class="moo-shell-avatar">#encodeForHTML(len(initials) ? initials : '?')#<cfif len(avatarUrl)><img src="#encodeForHTMLAttribute(avatarUrl)#" alt="" onerror="this.remove()" /></cfif></span>
                <span class="moo-shell-label">
                    <span class="moo-shell-profile-name">#encodeForHTML(currentProfile.full_name ?: 'Signed in')#</span>
                    <span class="moo-shell-profile-email">#encodeForHTML(currentProfile.email ?: '')#</span>
                </span>
                <span class="moo-shell-profile-switch-icon"><i class="fa-solid fa-up-down"></i></span>
            </button>
            <span class="moo-shell-nav-tooltip">#encodeForHTML(currentProfile.full_name ?: 'Profile')#</span>

            <div id="moo-shell-profile-dropdown" class="moo-shell-profile-dropdown" role="menu" aria-hidden="true">
                <div class="moo-shell-profile-dropdown-header">
                    <div class="moo-shell-profile-name">#encodeForHTML(currentProfile.full_name ?: 'Signed in')#</div>
                    <div class="moo-shell-profile-email">#encodeForHTML(currentProfile.email ?: '')#</div>
                </div>
                <cfif isSysAdmin>
                    <button type="button" role="menuitem" class="moo-shell-menu-item" onclick="req({ url_params: { init: '1' }, body: {} }).then(() => window.location.reload())">
                        <span class="moo-shell-menu-item-icon"><i class="fa-solid fa-rotate-right"></i></span>
                        <span>Re-initialise</span>
                    </button>
                    <div class="moo-shell-menu-divider"></div>
                </cfif>
                <!--- Moopa's own pages (Sign-in activity among them) are served by Hub only --->
                <cfif application.system_routes ?: false>
                    <a href="/account/profile" role="menuitem" class="moo-shell-menu-item">
                        <span class="moo-shell-menu-item-icon"><i class="fa-solid fa-user-pen"></i></span>
                        <span>Edit profile</span>
                    </a>
                    <a href="/account/signins" role="menuitem" class="moo-shell-menu-item">
                        <span class="moo-shell-menu-item-icon"><i class="fa-solid fa-clock-rotate-left"></i></span>
                        <span>Sign-in activity</span>
                    </a>
                </cfif>
                <a href="/logout/" role="menuitem" class="moo-shell-menu-item moo-shell-menu-item-danger">
                    <span class="moo-shell-menu-item-icon"><i class="fa-solid fa-right-from-bracket"></i></span>
                    <span>Sign out</span>
                </a>
            </div>
        </div>
    </aside>
</cfif>
    <div class="moo-shell-main">
        <main id="layout-content" class="moo-shell-content">#pageBody#</main>
    </div>
</div>
</body>
</html></cfoutput>
