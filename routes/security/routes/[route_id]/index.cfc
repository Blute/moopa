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


    <cffunction name="search.roles">
        <cfreturn application.lib.db.search(table_name='moo_role', q="#url.q?:''#", exclude_ids="#url.exclude_ids?:''#") />
    </cffunction>
    <cffunction name="search.profiles">
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



        <div x-data="xxx" class="p-6">

            <!--- Route Info Bar --->
            <div class="flex flex-wrap items-center justify-between gap-4 mb-6" x-cloak>
                <div class="flex flex-wrap items-center gap-2">
                    <code class="text-lg font-mono bg-base-200 px-3 py-1 rounded" x-text="current_route.url"></code>
                    <span x-show="route_open_to === 'public'" class="badge badge-success">Open to Public</span>
                    <span x-show="route_open_to === 'bearer'" class="badge badge-success">Open with Bearer Token</span>
                    <span x-show="route_open_to === 'logged_in'" class="badge badge-success">Open when Logged In</span>
                </div>
                <cfif session.auth.is_sysadmin?:false>
                    <button type="button" class="btn btn-sm btn-primary gap-2" @click="edit_route" x-show="!showEditRoute">
                        <i class="fal fa-pencil"></i>
                        Edit Access
                    </button>
                </cfif>
            </div>

            <cfif session.auth.is_sysadmin?:false>
                <div x-cloak x-show="showEditRoute" x-transition class="mb-6">
                    <div class="card card-border bg-base-100 max-w-2xl">
                        <div class="card-body">
                            <h3 class="card-title text-base">Edit Route Access</h3>
                            <div class="flex flex-col gap-4 mt-2">
                                <cf_table_controls table_name="moo_route" fields="roles,profiles" model_record="route_to_edit"></cf_table_controls>
                            </div>
                            <div class="card-actions justify-end mt-4">
                                <button class="btn btn-ghost" @click="showEditRoute=false">Cancel</button>
                                <button class="btn btn-primary" @click="save_route">Save</button>
                            </div>
                        </div>
                    </div>
                </div>
            </cfif>

            <div class="grid grid-cols-1 lg:grid-cols-3 gap-6" x-show="!showEditRoute" x-transition x-cloak>

                <!--- Permissions Matrix Card --->
                <div class="lg:col-span-2">
                    <div class="card card-border bg-base-100">
                        <div class="card-body p-0">
                            <div class="px-5 pt-5 pb-3 border-b border-base-200">
                                <h3 class="font-semibold flex items-center gap-2">
                                    <i class="fal fa-shield-check text-primary"></i>
                                    Endpoint Permissions
                                </h3>
                                <p class="text-sm text-base-content/60 mt-1">Click to toggle access for profiles and roles</p>
                            </div>

                            <template x-if="(current_route.profiles?.length > 0) || (current_route.roles?.length > 0)">
                                <div class="overflow-x-auto">
                                    <table class="table w-auto">
                                        <thead>
                                            <tr>
                                                <th class="text-center bg-base-200/50">&nbsp;</th>
                                                <template x-for="profile in current_route.profiles" :key="profile.id">
                                                    <th class="text-sm bg-base-200/50">
                                                        <div class="rotated-th">
                                                            <span class="rotated-th__label" x-text="profile.full_name"></span>
                                                        </div>
                                                    </th>
                                                </template>
                                                <template x-for="role in current_route.roles" :key="role.id">
                                                    <th class="text-sm bg-base-200/50">
                                                        <div class="rotated-th">
                                                            <span class="rotated-th__label font-semibold text-primary" x-text="role.label"></span>
                                                        </div>
                                                    </th>
                                                </template>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            <tr class="bg-base-100">
                                                <th class="font-semibold text-sm">ALL ACCESS</th>
                                                <template x-for="profile in current_route.profiles" :key="profile.id">
                                                    <td class="border border-base-300 p-3 text-center cursor-pointer hover:bg-base-200 transition-colors" @click="toggleProfileAccess(profile.id)">
                                                        <i class="fas fa-xl" :class="isProfileAccessSet(profile.id) ? 'fa-shield-check text-success' : 'fa-shield-check opacity-20'"></i>
                                                    </td>
                                                </template>
                                                <template x-for="role in current_route.roles" :key="role.id">
                                                    <td class="border border-base-300 p-3 text-center cursor-pointer hover:bg-base-200 transition-colors" @click="toggleRoleAccess(role.id)">
                                                        <i class="fas fa-xl" :class="isRoleAccessSet(role.id) ? 'fa-shield-check text-success' : 'fa-shield-check opacity-20'"></i>
                                                    </td>
                                                </template>
                                            </tr>

                                            <template x-for="endpoint in current_route.endpoints" :key="endpoint.id">
                                                <tr>
                                                    <th x-text="endpoint.name" class="font-medium text-sm text-base-content/80"></th>
                                                    <template x-for="profile in current_route.profiles" :key="profile.id">
                                                        <td class="border border-base-300 p-3 text-center cursor-pointer hover:bg-base-200 transition-colors" @click="toggleProfileAccess(profile.id, endpoint.id)">
                                                            <div x-show="isProfileAccessSet(profile.id)">
                                                                <i class="fat fa-xl fa-shield-check text-success/50"></i>
                                                            </div>
                                                            <div x-show="!isProfileAccessSet(profile.id)">
                                                                <i class="far fa-xl" :class="isProfileAccessSet(profile.id, endpoint.id) ? 'fa-shield-check text-success' : 'fa-shield-check text-error/60'"></i>
                                                            </div>
                                                        </td>
                                                    </template>
                                                    <template x-for="role in current_route.roles" :key="role.id">
                                                        <td class="border border-base-300 p-3 text-center cursor-pointer hover:bg-base-200 transition-colors" @click="toggleRoleAccess(role.id, endpoint.id)">
                                                            <div x-show="isRoleAccessSet(role.id)">
                                                                <i class="fat fa-xl fa-shield-check text-success/50"></i>
                                                            </div>
                                                            <div x-show="!isRoleAccessSet(role.id)">
                                                                <i class="far fa-xl" :class="isRoleAccessSet(role.id, endpoint.id) ? 'fa-shield-check text-success' : 'fa-shield-check text-error/60'"></i>
                                                            </div>
                                                        </td>
                                                    </template>
                                                </tr>
                                            </template>
                                        </tbody>
                                    </table>
                                </div>
                            </template>

                            <template x-if="!current_route.profiles?.length && !current_route.roles?.length">
                                <div class="p-8 text-center text-base-content/50">
                                    <i class="fal fa-user-shield fa-2x mb-3 block"></i>
                                    <p>No profiles or roles assigned to this route</p>
                                    <p class="text-sm mt-1">Click "Edit Roles & Profiles" to add access</p>
                                </div>
                            </template>
                        </div>
                    </div>
                </div>

                <!--- Who Has Access Sidebar --->
                <div class="lg:col-span-1">
                    <div class="card card-border bg-base-100 sticky top-4">
                        <div class="card-body">
                            <h3 class="font-semibold flex items-center gap-2 mb-3">
                                <i class="fal fa-users text-secondary"></i>
                                Who Has Access
                            </h3>

                            <template x-if="who_has_access.length > 0">
                                <div class="space-y-2 max-h-80 overflow-y-auto">
                                    <template x-for="person in who_has_access" :key="person.profile + person.role">
                                        <div class="flex items-center gap-3 p-2 rounded-lg hover:bg-base-200/50 transition-colors">
                                            <div class="avatar avatar-placeholder">
                                                <div class="bg-neutral text-neutral-content w-8 rounded-full flex items-center justify-center">
                                                    <span class="text-xs font-semibold" x-text="person.profile?.split(' ').map(n => n[0]).join('').slice(0,2).toUpperCase()"></span>
                                                </div>
                                            </div>
                                            <div class="min-w-0 flex-1">
                                                <p class="text-sm font-medium truncate" x-text="person.profile"></p>
                                                <p class="text-xs text-base-content/60 truncate">via <span class="font-medium" x-text="person.role"></span></p>
                                            </div>
                                        </div>
                                    </template>
                                </div>
                            </template>

                            <template x-if="who_has_access.length === 0">
                                <div class="text-center py-4 text-base-content/50">
                                    <i class="fal fa-user-slash fa-lg mb-2 block"></i>
                                    <p class="text-sm">No users have access via roles</p>
                                </div>
                            </template>
                        </div>
                    </div>
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
