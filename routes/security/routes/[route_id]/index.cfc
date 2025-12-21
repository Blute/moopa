<cfcomponent key="2befa9ac-1cc6-483f-bde1-1cca8cc1a818">


    <cffunction name="load">
        <cfset stResult = {} />
        <cfset stResult.current_route = application.lib.db.read(table_name='moo_route', id="#arguments.route_id#", field_list="*", returnAsCFML=true) />
        <cfset stResult.route_open_to = application.stAllRoutes[arguments.route_id].open_to />
        <cfset stResult.endpoint_access = {} />


        <!--- Initialize endpoint access --->
        <cfloop array="#stResult.current_route.profiles#" item="profile">
            <cfif !structKeyExists(stResult.endpoint_access, profile.id)>
                <cfset stResult.endpoint_access[profile.id] = {'_full_route_access_':false, endpoints:{}} />
            </cfif>
        </cfloop>

        <cfloop array="#stResult.current_route.roles#" item="role">
            <cfif !structKeyExists(stResult.endpoint_access, role.id)>
                <cfset stResult.endpoint_access[role.id] = {'_full_route_access_':false, endpoints:{}} />
            </cfif>
        </cfloop>


        <cfquery name="qRoutePermissions">
            SELECT
            moo_route.id AS route_id,
            moo_route.url AS route_url,
            moo_route_permission.profile_id AS profile_id,
            moo_route_permission.role_id as role_id,
            moo_route_permission.is_granted as is_granted
            FROM moo_route
            LEFT JOIN moo_route_endpoint ON moo_route.id = moo_route_endpoint.route_id
            LEFT JOIN moo_route_permission ON moo_route_permission.route_id = moo_route.id AND moo_route_permission.endpoint_id is null
            WHERE moo_route.id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
        </cfquery>

        <cfquery name="qEndpointPermissions">
            SELECT
            moo_route.id AS route_id,
            moo_route.url AS route_url,
            moo_route_endpoint.id AS endpoint_id,
            moo_route_endpoint.name AS endpoint_name,
            moo_route_permission.profile_id AS profile_id,
            moo_route_permission.role_id as role_id,
            moo_route_permission.is_granted as is_granted
            FROM moo_route
            LEFT JOIN moo_route_endpoint ON moo_route.id = moo_route_endpoint.route_id
            LEFT JOIN moo_route_permission ON moo_route_permission.route_id = moo_route.id AND moo_route_permission.endpoint_id = moo_route_endpoint.id
            WHERE moo_route.id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
        </cfquery>



        <cfloop query="qRoutePermissions">
            <cfif len(qRoutePermissions.profile_id)>
                <cfset stResult.endpoint_access[qRoutePermissions.profile_id]['_full_route_access_'] = qRoutePermissions.is_granted?true:false />
            <cfelseif len(qRoutePermissions.role_id)>
                <cfset stResult.endpoint_access[qRoutePermissions.role_id]['_full_route_access_'] = qRoutePermissions.is_granted?true:false />
            </cfif>
        </cfloop>

        <cfloop query="qEndpointPermissions">
            <cfif len(qEndpointPermissions.profile_id)>
                <cfset stResult.endpoint_access[qEndpointPermissions.profile_id]['endpoints'][qEndpointPermissions.endpoint_id] = qEndpointPermissions.is_granted?true:false />
            <cfelseif len(qEndpointPermissions.role_id)>
                <cfset stResult.endpoint_access[qEndpointPermissions.role_id]['endpoints'][qEndpointPermissions.endpoint_id] = qEndpointPermissions.is_granted?true:false />
            </cfif>
        </cfloop>


        <cfquery name="who_has_access">
        SELECT COALESCE(jsonb_agg(data)::text, '[]') as data
        FROM (
            SELECT moo_role.name as role, moo_profile.full_name as profile
            FROM moo_route_permission
            LEFT JOIN moo_role ON moo_role.id = moo_route_permission.role_id
            LEFT JOIN moo_profile_roles on moo_profile_roles.foreign_id = moo_role.id
            LEFT JOIN moo_profile on moo_profile.id = moo_profile_roles.primary_id
            WHERE moo_route_permission.route_id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
            AND moo_route_permission.is_granted

            AND (
                moo_route_permission.role_id IN (
                    SELECT foreign_id
                    FROM moo_route_roles
                    WHERE primary_id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
                )
                OR moo_route_permission.profile_id IN (
                    SELECT foreign_id
                    FROM moo_route_profiles
                    WHERE primary_id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
                )
            )

            AND moo_profile.id is not null
            ORDER BY moo_profile.full_name
        ) as data
        </cfquery>

        <cfset stResult.who_has_access = deserializeJSON(who_has_access.data) />


        <cfreturn stResult />

    </cffunction>

    <cffunction name="toggleProfileAccess">

        <cfquery name="qCheckExists">
        SELECT *
        FROM moo_route_permission
        WHERE route_id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
        AND profile_id = <cfqueryparam cfsqltype="other" value="#request.data.profileId#" />
        <cfif len(request.data.endpointId?:'')>
            AND endpoint_id = <cfqueryparam cfsqltype="other" value="#request.data.endpointId#" />
        <cfelse>
            AND endpoint_id is null
        </cfif>
        </cfquery>

        <cfif qCheckExists.recordcount EQ 1>
            <cfreturn application.lib.db.delete(
                table_name = "moo_route_permission",
                id="#qCheckExists.id#"
            ) />
        <cfelse>
            <cfreturn application.lib.db.save(
                table_name = "moo_route_permission",
                data = {
                    route_id="#arguments.route_id#",
                    profile_id="#request.data.profileId#",
                    endpoint_id="#request.data.endpointId?:''#",
                    is_granted=true,

                }
            ) />
        </cfif>
    </cffunction>

    <cffunction name="toggleRoleAccess">

        <cfquery name="qCheckExists">
        SELECT *
        FROM moo_route_permission
        WHERE route_id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
        AND role_id = <cfqueryparam cfsqltype="other" value="#request.data.roleId#" />
        <cfif len(request.data.endpointId?:'')>
            AND endpoint_id = <cfqueryparam cfsqltype="other" value="#request.data.endpointId#" />
        <cfelse>
            AND endpoint_id is null
        </cfif>
        </cfquery>

        <cfif qCheckExists.recordcount EQ 1>
            <cfreturn application.lib.db.delete(
                table_name = "moo_route_permission",
                id="#qCheckExists.id#"
            ) />
        <cfelse>
            <cfreturn application.lib.db.save(
                table_name = "moo_route_permission",
                data = {
                    route_id="#arguments.route_id#",
                    role_id="#request.data.roleId#",
                    endpoint_id="#request.data.endpointId?:''#",
                    is_granted=true,

                }
            ) />
        </cfif>
    </cffunction>


    <cffunction name="search.route_to_edit.roles">
        <cfreturn application.lib.db.search(table_name='moo_role', q="#url.q?:''#", exclude_ids="#url.exclude_ids?:''#") />
    </cffunction>
    <cffunction name="search.route_to_edit.profiles">
        <cfreturn application.lib.db.search(table_name='moo_profile', q="#url.q?:''#", exclude_ids="#url.exclude_ids?:''#") />
    </cffunction>



    <cffunction name="save_route">
        <cfreturn application.lib.db.save(
            table_name = "moo_route",
            data = request.data
        ) />
    </cffunction>




    <cffunction name="get" output="true">
        <cfargument name="route_id" />

        <cf_layout_blank>

        <style>
            .rotated-th {
                /**
                * Since the rotated text is taken out of the DOM flow (position: absolute), we
                * need to artificially consume vertical space so that the rotated headers
                * don't overlap with the content above the table.
                */
                height: 110px ;
                position: relative ;
            }
            /**
            * When an element is transform rotated, it still takes up the amount of space that
            * it would have if not rotated. As such, I'm making the label "position: absolute"
            * so that it doesn't take up any space ("absolute" takes it out of the DOM flow).
            * Instead, I'm deferring the space allocation to the parent DIV.
            */
            .rotated-th__label {
                bottom: 5px ;
                left: 50% ;
                position: absolute ;
                transform: rotate( -45deg ) ;
                transform-origin: center left ;
                white-space: nowrap ;
            }
        </style>



        <div x-data="xxx">

            <h1 class="text-2xl font-bold flex flex-wrap items-center gap-2" x-cloak>
                Route Security
                <span x-text="current_route.url" class="italic opacity-60"></span>
                <span x-show="route_open_to === 'public'" class="badge badge-success">Open to Public</span>
                <span x-show="route_open_to === 'bearer'" class="badge badge-success">Open with Bearer Token</span>
                <span x-show="route_open_to === 'logged_in'" class="badge badge-success">Open when Logged In</span>
            </h1>

            <cfif session.auth.is_sysadmin?:false>
                <button type="button" class="btn btn-outline btn-primary mt-4" @click="edit_route">Edit Roles & Profiles</button>

                <div x-cloak x-show="showEditRoute" x-transition class="mt-4 flex gap-2">

                    <!--- <cf_fields table_name="moo_route" fields="roles,profiles" model_record="route_to_edit" /> --->


                    <!--- <cf_input_many_to_many field="moo_route.roles" model_record="route_to_edit" />
                    <cf_input_many_to_many field="moo_route.profiles" model_record="route_to_edit" /> --->



                    <button class="btn btn-primary" @click="save_route">Save</button>
                    <button class="btn btn-ghost" @click="showEditRoute=false">Cancel</button>
                </div>
            </cfif>


            <div class="flex gap-8 mt-6" x-show="!showEditRoute" x-transition>



                    <div x-cloak>




                        <div class="overflow-x-auto">
                        <table class="table w-auto" x-show="(current_route.profiles?.length > 0) || (current_route.roles?.length > 0)">
                        <thead>
                          <tr>
                            <th class="text-center">&nbsp;</th>
                            <template x-for="profile in current_route.profiles" :key="profile.id">
                                <th class="text-sm">
                                    <div class="rotated-th">
                                        <span class="rotated-th__label" x-text="profile.full_name"></span>
                                    </div>
                                </th>
                            </template>
                            <template x-for="role in current_route.roles" :key="role.id">
                                <th class="text-sm">
                                    <div class="rotated-th">
                                        <span class="rotated-th__label" x-text="role.label"></span>
                                    </div>
                                </th>
                            </template>
                          </tr>
                        </thead>
                        <tbody>

                            <tr>
                              <th class="font-semibold">ALL ACCESS</th>
                                <template x-for="profile in current_route.profiles" :key="profile.id">
                                  <td class="border border-base-300 p-3 text-center cursor-pointer hover:bg-base-200" @click="toggleProfileAccess(profile.id)">
                                    <i class="fas fa-xl" :class="isProfileAccessSet(profile.id) ? 'fa-shield-check text-success' : 'fa-shield-check opacity-30'"></i>
                                  </td>
                                </template>


                                <template x-for="role in current_route.roles" :key="role.id">
                                  <td class="border border-base-300 p-3 text-center cursor-pointer hover:bg-base-200" @click="toggleRoleAccess(role.id)">
                                    <i class="fas fa-xl" :class="isRoleAccessSet(role.id) ? 'fa-shield-check text-success' : 'fa-shield-check opacity-30'"></i>
                                  </td>
                                </template>
                            </tr>


                          <template x-for="endpoint in current_route.endpoints" :key="endpoint.id">
                            <tr>
                              <th x-text="endpoint.name" class="font-medium"></th>
                                <template x-for="profile in current_route.profiles" :key="profile.id">
                                  <td class="border border-base-300 p-3 text-center cursor-pointer hover:bg-base-200" @click="toggleProfileAccess(profile.id, endpoint.id)">
                                    <div x-show="isProfileAccessSet(profile.id)">
                                        <i class="fat fa-xl fa-shield-check text-success"></i>
                                    </div>
                                    <div x-show="!isProfileAccessSet(profile.id)">
                                        <i class="far fa-xl" :class="isProfileAccessSet(profile.id, endpoint.id) ? 'fa-shield-check text-success' : 'fa-shield-check text-error'"></i>
                                    </div>

                                  </td>
                                </template>


                                <template x-for="role in current_route.roles" :key="role.id">
                                  <td class="border border-base-300 p-3 text-center cursor-pointer hover:bg-base-200" @click="toggleRoleAccess(role.id, endpoint.id)">
                                    <div x-show="isRoleAccessSet(role.id)">
                                        <i class="fat fa-xl fa-shield-check text-success"></i>
                                    </div>
                                    <div x-show="!isRoleAccessSet(role.id)">
                                        <i class="far fa-xl" :class="isRoleAccessSet(role.id, endpoint.id) ? 'fa-shield-check text-success' : 'fa-shield-check text-error'"></i>
                                    </div>
                                  </td>
                                </template>
                            </tr>
                          </template>
                        </tbody>
                      </table>
                      </div>
                    </div>


                <div>

                    <h6 class="text-sm font-semibold" style="margin-top:110px;">Who Has Access Via Roles?</h6>

                    <template x-for="person in who_has_access">

                        <div class="py-1">
                            <span x-text="person.profile"></span>
                            <span class="text-xs opacity-60">(<span x-text="person.role"></span>)</span>
                        </div>
                    </template>
                </div>

            </div>






        </div>

        <script>
            document.addEventListener("alpine:init", () => {
                Alpine.data("xxx", () => ({
                    loadingState: 'idle',
                    showEditRoute: false,
                    current_route: {},
                    route_to_edit: {},
                    endpoint_access: {},
                    who_has_access:[],
                    route_open_to: 'security',

                    edit_route() {
                        this.route_to_edit = JSON.parse(JSON.stringify(this.current_route))
                        this.showEditRoute = true;
                    },

                    save_route() {
                        this.loadingState = 'loading';

                        fetchData({
                            method: 'POST',
                            endpoint: 'save_route',
                            body: this.route_to_edit,
                            callback: (data) => {
                                this.load();
                                this.loadingState = 'idle';
                                this.showEditRoute = false;
                            }
                        });
                    },

                    // Function to check if a profile has access to an endpoint
                    isProfileAccessSet(profileId, endpointId) {
                        // Safely check if the profileId exists in the endpoint_access object
                        const profileAccess = this.endpoint_access[profileId];
                        if (profileAccess) {
                            // If endpointId is not passed, only check for full route access
                            if (typeof endpointId === 'undefined' || endpointId === null) {

                                return profileAccess._full_route_access_ === true;
                            }

                            // If endpointId is passed, check for specific endpoint access
                            const hasEndpointAccess = profileAccess.endpoints && profileAccess.endpoints[endpointId] === true;
                            return hasEndpointAccess;
                        }

                        // Return false if profileId doesn't exist or doesn't have the required access
                        return false;
                    },

                    // Function to check if a profile has access to an endpoint
                    isRoleAccessSet(roleId, endpointId) {
                        // Safely check if the profileId exists in the endpoint_access object
                        const roleAccess = this.endpoint_access[roleId];
                        if (roleAccess) {
                             // If endpointId is not passed, only check for full route access
                            if (typeof endpointId === 'undefined' || endpointId === null) {

                                return roleAccess._full_route_access_ === true;
                            }

                            // If endpointId is passed, check for specific endpoint access
                            const hasEndpointAccess = roleAccess.endpoints && roleAccess.endpoints[endpointId] === true;
                            return hasEndpointAccess;
                        }

                        // Return false if profileId doesn't exist or doesn't have access to the endpointId
                        return false;

                    },

                    toggleProfileAccess(profileId, endpointId) {
                        // Handle the checkbox click event to set access
                        <cfif session.auth.is_sysadmin?:false>
                            fetchData({
                                method: 'POST',
                                endpoint: 'toggleProfileAccess',
                                body: {
                                    profileId:profileId,
                                    endpointId:endpointId
                                },
                                callback: (data) => {
                                    this.loadingState = 'idle';

                                    this.load()

                                }
                            });
                        </cfif>

                    },

                    toggleRoleAccess(roleId, endpointId) {
                        // Handle the checkbox click event to set access

                        <cfif session.auth.is_sysadmin?:false>
                            fetchData({
                                method: 'POST',
                                endpoint: 'toggleRoleAccess',
                                body: {
                                    roleId:roleId,
                                    endpointId:endpointId
                                },
                                callback: (data) => {
                                    this.loadingState = 'idle';

                                    this.load()

                                }
                            });
                        </cfif>
                    },

                    async load() {
                        await fetchData({
                            endpoint: 'load',
                            callback: (data) => {
                                this.route_to_edit = {}
                                this.current_route = data.current_route
                                this.endpoint_access = data.endpoint_access
                                this.route_open_to = data.route_open_to
                                this.who_has_access = data.who_has_access
                            }
                        });
                    },

                    init() {
                        this.load()
                    }
                }))
            })
        </script>


        </cf_layout_blank>
    </cffunction>


</cfcomponent>
