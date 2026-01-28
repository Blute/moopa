<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        [
            "name": "moo_profile",
            "title": "Profile",
            "title_plural": "Profiles",
            "item_label_template": "`${item.full_name}`",
            "label_generation_expression": "(COALESCE(NULLIF(preferred_name::text,''), full_name::text) || ' - ' || COALESCE(NULLIF(mobile::text,''), email::text))",

            "fields":
            [


                "full_name":
                {
                    "type": "varchar",
                    "searchable": "true"
                },
                "preferred_name":
                {
                    "type": "varchar",
                    "searchable": "true"
                },
                "company_name":
                {
                    "type": "varchar",
                    "searchable": "true"
                },
                "email":
                {
                    "type": "varchar",
                    "searchable": "true",
                    "html": {
                        "type": "email"
                    }
                },
                "mobile":
                {
                    "type": "varchar",
                    "max_length": 20,
                    "searchable": "true",
                    "html": {
                        "type": "tel"
                    }
                },

                "can_login": {
                    "type": "bool",
                    "default": false,
                    "html": {
                        "type": "switch"
                    }
                },
                "dob":
                {
                    "label": "Date Of Birth",
                    "type": "date"
                },
                "address":
                {
                    "type": "jsonb",
                    "html":{
                        "control": "address"
                    }
                },
                "formatted_address":
                {
                    "label": "Formatted Address (Generated)",
                    "type": "text",
                    "generation_expression": "address->>'formatted_address'",
                    "searchable": true,
                    "html": {
                        "hidden": true
                    }
                },
                "bio":
                {
                    "type": "text",
                    "html": {
                        "type": "textarea"
                    }
                },
                "correspondence":
                {
                    "type": "many_to_many",
                    "foreign_key_table": "moo_file",
                    "html": {
                        "type": "file"
                    }
                },
                "profile_picture_id":
                {
                    "type": "uuid",
                    "foreign_key_table": "moo_file",
                    "html": {
                        "type": "file"
                    }
                },
                "profile_avatar_id":
                {
                    "type": "uuid",
                    "foreign_key_table": "moo_file",
                    "html": {
                        "type": "file"
                    }
                },
                "roles":
                {
                    "type": "many_to_many",
                    "foreign_key_table": "moo_role"
                },


            ]
        ]

        />

        <cfreturn this>
    </cffunction>


    <cffunction name="login">
        <cfargument name="profile_id" default="" />
        <cfargument name="full_name" default="" />
        <cfargument name="company_name" default="" />
        <cfargument name="email" default="" />
        <cfargument name="mobile" default="" />
        <cfargument name="auto_login" default=false />
        <cfargument name="stay_logged_in" default=true /> <!--- If true, the user will be logged in for 30 days. Default is true. --->
        <cfargument name="user_directory" default="" />
        <cfargument name="authentication_service_user" default="" />


        <cfif !len(arguments.profile_id) AND !len(arguments.email) AND !len(arguments.mobile)>
            <cfabort showerror="YOU MUST LOGIN WITH AN ID OR EMAIL OR MOBILE" />
        </cfif>


        <cflock name="session_#arguments.profile_id?:''#_#arguments.email?:''#_#arguments.mobile?:''#" timeout="10">

            <cfset session.auth = {} />

            <cfif len(arguments.profile_id)>
                <cfset profile_to_login = application.lib.db.read(
                    table_name = "moo_profile",
                    id = arguments.profile_id,
                    field_list = "id,full_name,full_name,email,mobile,profile_avatar_id,profile_picture_id,can_login,roles",
                    returnAsCFML=true
                ) />

                <cfif !profile_to_login.can_login>
                    <cfabort showerror="YOU DO NOT HAVE ACCESS TO LOGIN" />
                </cfif>

                <cfset session.auth.profile = profile_to_login />
            <cfelse>
                <cfset new_profile = application.lib.db.save(
                    table_name = "moo_profile",
                    data = {
                        full_name = "#arguments.full_name#",
                        company_name = "#arguments.company_name#",
                        email = "#arguments.email?:''#",
                        mobile = "#arguments.mobile?:''#",
                        can_login = true
                    },
                    returnAsCFML=true
                ) />


                <cfset session.auth.profile = application.lib.db.read(
                    table_name = "moo_profile",
                    id = new_profile.id,
                    field_list = "id,full_name,full_name,email,mobile,profile_avatar_id,profile_picture_id,can_login,roles",
                    returnAsCFML=true
                ) />
            </cfif>


            <cfset session.auth.isLoggedIn = true />
            <cfset session.auth.auto_login = false />
            <cfset session.auth.stay_logged_in = false />
            <cfset session.auth.authentication_service_user = arguments.authentication_service_user />
            <cfset session.auth.user = {} /> <!--- Find Profile in DB --->
            <cfset session.auth.is_sysadmin = false />
            <cfset session.auth.role_id_array = [] />
            <cfset session.auth.role_id_list = "" />
            <cfset session.auth.user_directory = arguments.user_directory />
            <cfset session.auth.endpoint_hash_code = createUniqueID() />


            <cfif !arguments.auto_login AND arguments.stay_logged_in>

                <cfset new_device_id = createUUID() />
                <cfset expireTime = dateAdd("d", 30, now())>
                <cfset new_extended_session = application.lib.db.save(
                    table_name = "moo_profile_extended_session",
                    data = {
                        profile_id = "#session.auth.profile.id#",
                        device_id = "#new_device_id#",
                        expiration = "#expireTime#"
                    },
                    returnAsCFML=true
                ) />

                <cfcookie name="deviceid" value="#new_device_id#" expires="#expireTime#" httponly="true" secure="true" samesite="Lax">


                <cfset session.auth.stay_logged_in = true />

            </cfif>


            <cfif (arguments.auto_login)>
                <cfset session.auth.auto_login = true />
                <cfset session.auth.stay_logged_in = true />
            </cfif>


            <cfset session.auth.role_id_array = ArrayMap(session.auth.profile.roles, function(role) {
                return role.id;
            })>

            <!--- Convert the array of role IDs to a comma-separated list --->
            <cfset session.auth.role_id_list = ArrayToList(session.auth.role_id_array)>

            <cfif len(session.auth.profile.email?:'') AND listFindNoCase(server.system.environment.SYSADMIN_email?:'', session.auth.profile.email)>
                <cfset session.auth.is_sysadmin = true />
            </cfif>

            <!--- GENERATE USER PRIMARY NAV BASED ON PERMISSIONS --->
            <cfset generateNavs() />


            <cfset application.lib.db.save(
                table_name = "moo_login_log",
                data = {
                    mobile = "#session.auth.profile.mobile?:''#",
                    email = "#session.auth.profile.email?:''#",
                    status = "Login",
                    auto_login = session.auth.auto_login,
                    authentication_service_user = session.auth.authentication_service_user,
                    stay_logged_in = session.auth.stay_logged_in
                }
            ) />

        </cflock>

    </cffunction>



    <cffunction name="generateNavs">
        <cfif application.lib.auth.isLoggedIn()>

            <cfset session.auth.navs = {}>
            <cfset session.auth.nav_id = application.nav_id?:'' />

            <!--- Loop through all nav structures --->
            <cfloop collection="#application.navs#" item="navKey">
                <!--- Duplicate and filter each nav structure --->
                <cfset session.auth.navs[navKey] = filterNavItems(duplicate(application.navs[navKey]))>
            </cfloop>

            <!---
            <cfset session.auth.primary_nav = filterNavItems(duplicate(application.primary_nav))>
            <cfset session.auth.primary_navid = application.primary_navid?:''> --->
        </cfif>
    </cffunction>



    <cffunction name="filterNavItems" returntype="array" access="private">
        <cfargument name="navItems" type="array" required="yes">

        <cfset var filteredItems = ArrayNew(1)>
        <cfset var moo_route = application.lib.db.getService("moo_route") />

        <!--- Loop over each nav item --->
        <cfloop array="#arguments.navItems#" index="item">

            <cfset item.id = createUUID() />

            <cfif structKeyExists(item, "route")>
                <!--- Check access for the route --->
                <cfset var route_data = moo_route.parseRoute(item.route) />

                <cfif !structIsEmpty(route_data.stRoute)>
                    <cfset var has_access = moo_route.checkAccess(route_data=route_data, endpoint='GET') />

                    <cfif has_access>
                        <!--- If access is granted, add the item to the filtered list --->

                        <cfset arrayAppend(filteredItems, item)>
                    </cfif>
                <cfelse>
                    <!--- -------------------------------------------------- --->
                    <!--- TODO. Submit some sort of notification to sysadmin --->
                    <!--- -------------------------------------------------- --->
                    <!--- Route does not exist so ignore.  --->
                    <!--- <cfabort showerror="NOT A ROUTE: #item.route#" /> --->
                </cfif>
            <cfelseif structKeyExists(item, "items")>
                <!--- Recursively filter the nested items array --->
                <cfset var subItems = filterNavItems(item.items)>

                <!--- Only include the 'items' array if it has accessible sub-items --->
                <cfif arrayLen(subItems)>
                    <cfset var newItem = duplicate(item)>
                    <cfset newItem.items = subItems>
                    <cfset arrayAppend(filteredItems, newItem)>
                <cfelse>
                    <!--- If there are no accessible sub-items, check if the parent item itself is accessible without the 'items' array --->
                    <cfset structDelete(item, "items")>
                </cfif>
            </cfif>
        </cfloop>

        <cfreturn filteredItems>
    </cffunction>


</cfcomponent>
