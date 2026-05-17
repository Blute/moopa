<cfcomponent key="88fcf7cb-d88c-41b0-b1c8-861c1cfe1895">


    <cffunction name="uploadFileToServerWithProgress.profile_picture_id">
        <cfreturn application.lib.db.getService(table_name="moo_file").uploadFileToServerWithProgress(data="#request.data#") />
    </cffunction>


    <cffunction name="read">
        <cfreturn application.lib.db.read(table_name='moo_profile', id=id, field_list="*", returnAsCFML=true) />
    </cffunction>


    <cffunction name="getAppNames">
        <cfquery name="qAppNames">
            SELECT COALESCE(array_to_json(array_agg(app_name ORDER BY app_name))::text, '[]') AS recordset
            FROM (
                SELECT DISTINCT app_name
                FROM moo_profile
                WHERE app_name IS NOT NULL AND app_name <> ''
            ) AS t
        </cfquery>
        <cfreturn qAppNames.recordset />
    </cffunction>


    <cffunction name="getSysadminEmailList" access="private" returntype="string" output="false">
        <cfset var normalizedEmails = [] />
        <cfset var email = "" />

        <cfloop list="#server.system.environment.SYSADMIN_EMAIL ?: ''#" item="email">
            <cfset email = lCase(trim(email)) />
            <cfif len(email)>
                <cfset arrayAppend(normalizedEmails, email) />
            </cfif>
        </cfloop>

        <cfif NOT arrayLen(normalizedEmails)>
            <cfreturn "__moopa_no_configured_sysadmin_email__" />
        </cfif>

        <cfreturn arrayToList(normalizedEmails) />
    </cffunction>


    <cffunction name="isConfiguredHubSysadminEmail" access="private" returntype="boolean" output="false">
        <cfargument name="email" type="string" required="true" />
        <cfargument name="app_name" type="string" required="true" />

        <cfreturn arguments.app_name EQ "hub" AND listFindNoCase(getSysadminEmailList(), lCase(trim(arguments.email))) GT 0 />
    </cffunction>


    <cffunction name="getProfileSysadminIdentity" access="private" returntype="struct" output="false">
        <cfargument name="profile_id" type="string" required="true" />

        <cfquery name="local.qProfile" returntype="array">
            SELECT id::text, email, app_name
            FROM moo_profile
            WHERE id = <cfqueryparam cfsqltype="other" value="#arguments.profile_id#" />
            LIMIT 1
        </cfquery>

        <cfif NOT arrayLen(local.qProfile)>
            <cfreturn {} />
        </cfif>

        <cfreturn local.qProfile[1] />
    </cffunction>


    <cffunction name="isProtectedSysadminProfileById" access="private" returntype="boolean" output="false">
        <cfargument name="profile_id" type="string" required="true" />
        <cfset var profile = {} />

        <cfif NOT len(arguments.profile_id)>
            <cfreturn false />
        </cfif>

        <cfset profile = getProfileSysadminIdentity(arguments.profile_id) />
        <cfreturn structKeyExists(profile, "id") AND isConfiguredHubSysadminEmail(profile.email ?: "", profile.app_name ?: "") />
    </cffunction>


    <cffunction name="search">

        <cfset searchTerm = request.data.filter.term?:'' />
        <cfset appNameFilter = request.data.filter.app_name?:'' />

        <cfquery name="qData">
        SELECT COALESCE(array_to_json(array_agg(row_to_json(data)))::text, '[]') AS recordset
        FROM (
            SELECT #application.lib.db.select(table_name="moo_profile", field_list="id,app_name,full_name,email,mobile,address,roles,is_employee,employee_type,can_login,profile_picture_id,profile_avatar_id,last_login_at")#,
                (
                    moo_profile.app_name = 'hub'
                    AND lower(moo_profile.email) IN (<cfqueryparam cfsqltype="varchar" value="#getSysadminEmailList()#" list="true" />)
                ) AS is_configured_sysadmin,
                COUNT(*) OVER() AS total_count,
                COALESCE((
                    SELECT json_agg(moo_role.name ORDER BY moo_role.name)
                    FROM moo_profile_roles
                    INNER JOIN moo_role ON moo_role.id = moo_profile_roles.foreign_id
                    WHERE moo_profile_roles.primary_id = moo_profile.id
                ), '[]') AS role_labels,
                COALESCE((
                    SELECT json_agg(json_build_object('provider', provider, 'provider_subject', provider_subject) ORDER BY provider, provider_subject)
                    FROM moo_profile_auth
                    WHERE moo_profile_auth.profile_id = moo_profile.id
                ), '[]') AS auth_identities
            FROM moo_profile
            WHERE 1=1
            <cfif len(searchTerm)>
                AND <cfqueryparam cfsqltype="varchar" value="#searchTerm#" /> <% search_text
            </cfif>
            <cfif len(appNameFilter)>
                AND moo_profile.app_name = <cfqueryparam cfsqltype="varchar" value="#appNameFilter#" />
            </cfif>
            <cfif len(searchTerm)>
                ORDER BY word_similarity(<cfqueryparam cfsqltype="varchar" value="#searchTerm#" />, search_text) DESC
            <cfelse>
                ORDER BY moo_profile.full_name
            </cfif>
            LIMIT 100
        ) AS data
        </cfquery>

        <cfreturn qData.recordset />

    </cffunction>





    <cffunction name="new">
        <cfreturn application.lib.db.getNewObject(
            table_name = "moo_profile",
            data = {
                app_name = application.app_name ?: "hub"
            },
            returnAsCFML = true
        ) />
    </cffunction>

    <cffunction name="save">
        <cfset var protectedProfile = {} />

        <cfif NOT isStruct(request.data)>
            <cfthrow type="moopa.security.invalidProfilePayload" message="Profile save payload must be an object." />
        </cfif>

        <cfif NOT len(request.data.app_name ?: "")>
            <cfset request.data["app_name"] = application.app_name ?: "hub" />
        </cfif>

        <cfif len(request.data.id ?: "") AND isProtectedSysadminProfileById(request.data.id)>
            <cfset protectedProfile = getProfileSysadminIdentity(request.data.id) />
            <cfif lCase(trim(request.data.email ?: "")) NEQ lCase(trim(protectedProfile.email ?: ""))>
                <cfthrow type="moopa.security.protectedSysadmin" message="Configured Hub sysadmin profiles cannot have their email changed from the configured SYSADMIN_EMAIL value." />
            </cfif>
            <cfif (request.data.app_name ?: "") NEQ "hub">
                <cfthrow type="moopa.security.protectedSysadmin" message="Configured Hub sysadmin profiles must remain in the hub app." />
            </cfif>
            <cfset request.data.can_login = true />
        <cfelseif isConfiguredHubSysadminEmail(request.data.email ?: "", request.data.app_name ?: "")>
            <cfset request.data.can_login = true />
        </cfif>

        <cfreturn application.lib.db.save(
            table_name = "moo_profile",
            data = request.data
        ) />
    </cffunction>

    <cffunction name="delete">
        <cfif isProtectedSysadminProfileById(url.id ?: "")>
            <cfthrow type="moopa.security.protectedSysadmin" message="Configured Hub sysadmin profiles cannot be deleted." />
        </cfif>
        <cfreturn application.lib.db.delete(table_name="moo_profile", id="#url.id#") />
    </cffunction>


    <cffunction name="search.current_record.roles">
        <cfreturn application.lib.db.search(table_name='moo_role', q="#url.q?:''#") />
    </cffunction>

    <cffunction name="search.roles">
        <cfreturn application.lib.db.search(table_name='moo_role', q="#url.q?:''#", field_list="id,label") />
    </cffunction>


    <cffunction name="get" output="true">
        <cf_layout_default>

            <div x-data="profiles_admin" x-cloak class="flex flex-col gap-4 lg:gap-5">
                <!-- Header -->
                <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                    <div class="min-w-0">
                        <div class="flex items-center gap-3">
                            <div class="flex h-11 w-11 shrink-0 items-center justify-center rounded-box bg-primary/10 text-primary">
                                <i class="hgi-stroke hgi-user text-xl"></i>
                            </div>
                            <div class="min-w-0">
                                <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                                    <h1 class="text-2xl font-semibold tracking-tight">Profiles</h1>
                                    <span class="text-xs font-medium uppercase tracking-[0.14em] text-base-content/45" x-text="resultSummary()"></span>
                                </div>
                                <p class="text-sm text-base-content/60">Manage identities, login access, roles, and authentication links.</p>
                            </div>
                        </div>
                    </div>

                    <button class="btn btn-primary btn-sm gap-2" @click="addNew">
                        <i class="hgi-stroke hgi-plus-sign"></i>
                        New Profile
                    </button>
                </div>

                <!-- Filters -->
                <div class="rounded-box border border-base-300 bg-base-100 shadow-sm">
                    <div class="grid gap-3 p-4 lg:grid-cols-[minmax(18rem,1fr)_16rem_auto] lg:items-end">
                        <fieldset class="fieldset min-w-0 p-0">
                            <legend class="fieldset-legend pb-1">Search</legend>
                            <label class="input input-sm w-full focus-within:outline-primary/55 focus-within:outline-offset-2" @input.debounce.500ms="load()" @change.stop>
                                <i class="hgi-stroke hgi-search-01 text-base-content/40"></i>
                                <input type="search" placeholder="Search name, email, or mobile" x-model="filters.term">
                            </label>
                        </fieldset>

                        <fieldset class="fieldset min-w-0 p-0">
                            <legend class="fieldset-legend pb-1">App</legend>
                            <select class="select select-sm w-full focus:outline-primary/55 focus:outline-offset-2" x-model="filters.app_name" @change="load()">
                                <option value="">All apps</option>
                                <template x-for="app in app_names" :key="app">
                                    <option :value="app" x-text="app"></option>
                                </template>
                            </select>
                        </fieldset>

                        <button type="button" class="btn btn-ghost btn-sm justify-self-start lg:justify-self-end" @click="resetFilters()" :disabled="!hasActiveFilters()">
                            Reset filters
                        </button>
                    </div>
                </div>

                <template x-if="load_error">
                    <div class="alert alert-error text-sm">
                        <i class="hgi-stroke hgi-alert-02"></i>
                        <div>
                            <p class="font-medium">Profiles could not be loaded.</p>
                            <p class="text-error-content/80">Try again, or check the server logs if the problem continues.</p>
                        </div>
                        <button type="button" class="btn btn-sm" @click="load()">Retry</button>
                    </div>
                </template>

                <!-- Results -->
                <div class="overflow-hidden rounded-box border border-base-300 bg-base-100 shadow-sm">
                    <div class="flex items-center justify-between border-b border-base-300 px-4 py-3 text-xs text-base-content/55">
                        <span x-text="resultSummary()"></span>
                        <template x-if="total_count > records.length">
                            <span>Showing first <span x-text="records.length"></span>. Refine filters to narrow results.</span>
                        </template>
                    </div>

                    <div class="divide-y divide-base-300 md:hidden">
                        <template x-for="i in (loading_indicator ? 4 : 0)" :key="i">
                            <div class="p-4">
                                <div class="skeleton h-20 w-full"></div>
                            </div>
                        </template>

                        <template x-for="item in records" :key="item.id">
                            <article class="p-4" @click="select(item)">
                                <div class="flex items-start justify-between gap-3">
                                    <div class="flex min-w-0 items-start gap-3">
                                        <template x-if="item.profile_picture_id?.thumbnail">
                                            <div class="avatar">
                                                <div class="w-10 rounded-full bg-base-200">
                                                    <img :src="item.profile_picture_id.thumbnail" :alt="item.full_name" />
                                                </div>
                                            </div>
                                        </template>
                                        <template x-if="!item.profile_picture_id?.thumbnail">
                                            <div class="avatar avatar-placeholder">
                                                <div class="bg-neutral text-neutral-content w-10 rounded-full flex items-center justify-center">
                                                    <span class="text-xs font-semibold" x-text="getInitials(item.full_name)"></span>
                                                </div>
                                            </div>
                                        </template>
                                        <div class="min-w-0">
                                            <div class="flex flex-wrap items-center gap-2">
                                                <h3 class="font-medium leading-tight" x-text="item.full_name || 'Unnamed profile'"></h3>
                                                <template x-if="isProtectedSysadmin(item)">
                                                    <span class="badge badge-xs badge-soft badge-primary gap-1">
                                                        <i class="hgi-stroke hgi-shield-01"></i>
                                                        Protected
                                                    </span>
                                                </template>
                                            </div>
                                            <p class="truncate text-sm text-base-content/60" x-text="item.email"></p>
                                        </div>
                                    </div>
                                    <div class="flex shrink-0 items-center gap-1">
                                        <button class="btn btn-ghost btn-sm btn-square min-h-10 h-10 w-10" @click.stop="select(item)" title="Edit profile" aria-label="Edit profile">
                                            <i class="hgi-stroke hgi-pencil-edit-02 text-base-content/70"></i>
                                        </button>
                                        <button class="btn btn-ghost btn-sm btn-square min-h-10 h-10 w-10 text-error" @click.stop="openDeleteModal(item)" title="Delete profile" :disabled="isProtectedSysadmin(item)" :aria-label="isProtectedSysadmin(item) ? 'Configured Hub sysadmin profiles cannot be deleted' : 'Delete profile'">
                                            <i class="hgi-stroke hgi-delete-02"></i>
                                        </button>
                                    </div>
                                </div>
                                <dl class="mt-4 grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
                                    <div>
                                        <dt class="text-xs font-medium text-base-content/45">App</dt>
                                        <dd class="mt-0.5 font-mono text-xs text-base-content/70" x-text="item.app_name || '—'"></dd>
                                    </div>
                                    <div>
                                        <dt class="text-xs font-medium text-base-content/45">Login</dt>
                                        <dd class="mt-0.5 inline-flex items-center gap-1.5 text-xs font-medium" :class="item.can_login ? 'text-success' : 'text-base-content/50'">
                                            <i class="hgi-stroke" :class="item.can_login ? 'hgi-login-03' : 'hgi-lock-key'"></i>
                                            <span x-text="isProtectedSysadmin(item) ? 'Protected' : (item.can_login ? 'Can log in' : 'Login disabled')"></span>
                                        </dd>
                                    </div>
                                    <div class="col-span-2">
                                        <dt class="text-xs font-medium text-base-content/45">Auth identity</dt>
                                        <dd class="mt-0.5 truncate font-mono text-xs text-base-content/70" x-text="item.auth_identities?.length ? formatAuthIdentity(item.auth_identities[0]) : '—'"></dd>
                                    </div>
                                    <div class="col-span-2">
                                        <dt class="text-xs font-medium text-base-content/45">Last login</dt>
                                        <dd class="mt-0.5 font-mono text-xs text-base-content/70" x-text="compactDate(item.last_login_at) || '—'"></dd>
                                    </div>
                                </dl>
                            </article>
                        </template>

                        <template x-if="!loading && !load_error && records.length === 0">
                            <div class="px-6 py-12 text-center">
                                <div class="mx-auto flex max-w-md flex-col items-center gap-3 text-base-content/65">
                                    <i class="hgi-stroke hgi-user-group text-3xl text-base-content/35"></i>
                                    <div>
                                        <p class="font-medium text-base-content" x-text="hasActiveFilters() ? 'No profiles match these filters.' : 'No profiles yet.'"></p>
                                        <p class="mt-1 text-sm" x-text="hasActiveFilters() ? 'Clear filters or search for a different name, email, or mobile.' : 'Create the first identity for this app.'"></p>
                                    </div>
                                    <button type="button" class="btn btn-sm" @click="hasActiveFilters() ? resetFilters() : addNew()" x-text="hasActiveFilters() ? 'Clear filters' : 'New Profile'"></button>
                                </div>
                            </div>
                        </template>
                    </div>

                    <div class="hidden overflow-auto md:block">
                        <table class="table table-sm table-fixed w-full">
                            <thead class="bg-base-100">
                                <tr class="border-base-300 text-xs text-base-content/55">
                                    <th class="w-[27%] font-medium">Identity</th>
                                    <th class="w-[7%] font-medium">App</th>
                                    <th class="w-[12%] font-medium">Roles</th>
                                    <th class="w-[13%] font-medium">Login</th>
                                    <th class="w-[24%] font-medium">Auth identity</th>
                                    <th class="w-[10%] font-medium">Last login</th>
                                    <th class="w-[7%] text-end font-medium">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                <template x-for="i in (loading_indicator ? 6 : 0)" :key="i">
                                    <tr>
                                        <td colspan="7" class="py-3">
                                            <div class="skeleton h-8 w-full"></div>
                                        </td>
                                    </tr>
                                </template>

                                <template x-for="item in records" :key="item.id">
                                    <tr class="border-base-200 hover:bg-base-200/35 cursor-pointer" @click="select(item)">
                                        <td>
                                            <div class="flex items-center gap-3">
                                                <template x-if="item.profile_picture_id?.thumbnail">
                                                    <div class="avatar">
                                                        <div class="w-9 rounded-full bg-base-200">
                                                            <img :src="item.profile_picture_id.thumbnail" :alt="item.full_name" />
                                                        </div>
                                                    </div>
                                                </template>
                                                <template x-if="!item.profile_picture_id?.thumbnail">
                                                    <div class="avatar avatar-placeholder">
                                                        <div class="bg-neutral text-neutral-content w-9 rounded-full flex items-center justify-center">
                                                            <span class="text-xs font-semibold" x-text="getInitials(item.full_name)"></span>
                                                        </div>
                                                    </div>
                                                </template>
                                                <div class="min-w-0">
                                                    <div class="flex items-center gap-2">
                                                        <p class="font-medium truncate" x-text="item.full_name || 'Unnamed profile'" :title="item.full_name"></p>
                                                        <template x-if="isProtectedSysadmin(item)">
                                                            <span class="badge badge-xs badge-soft badge-primary gap-1" title="Configured Hub sysadmin">
                                                                <i class="hgi-stroke hgi-shield-01"></i>
                                                                Protected
                                                            </span>
                                                        </template>
                                                    </div>
                                                    <p class="text-xs text-base-content/60 truncate" x-text="item.email" :title="item.email"></p>
                                                </div>
                                            </div>
                                        </td>
                                        <td><span class="text-xs font-mono text-base-content/70" x-text="item.app_name || '—'"></span></td>
                                        <td>
                                            <div class="flex flex-wrap gap-1">
                                                <template x-for="role in item.role_labels" :key="role">
                                                    <span class="badge badge-sm badge-soft badge-neutral" x-text="role"></span>
                                                </template>
                                                <template x-if="!item.role_labels?.length">
                                                    <span class="text-base-content/40 text-sm">—</span>
                                                </template>
                                            </div>
                                        </td>
                                        <td>
                                            <div class="flex flex-col gap-1">
                                                <span class="inline-flex items-center gap-1.5 text-xs font-medium" :class="item.can_login ? 'text-success' : 'text-base-content/50'">
                                                    <i class="hgi-stroke" :class="item.can_login ? 'hgi-login-03' : 'hgi-lock-key'"></i>
                                                    <span x-text="isProtectedSysadmin(item) ? 'Protected' : (item.can_login ? 'Can log in' : 'Login disabled')"></span>
                                                </span>
                                                <template x-if="item.is_employee">
                                                    <span class="badge badge-xs badge-soft badge-info capitalize" x-text="item.employee_type || 'employee'"></span>
                                                </template>
                                            </div>
                                        </td>
                                        <td class="min-w-0">
                                            <template x-if="item.auth_identities?.length">
                                                <span class="block truncate text-xs font-mono text-base-content/70" x-text="formatAuthIdentity(item.auth_identities[0])" :title="authIdentityTitle(item.auth_identities)"></span>
                                            </template>
                                            <template x-if="!item.auth_identities?.length">
                                                <span class="text-xs text-base-content/40">—</span>
                                            </template>
                                        </td>
                                        <td><span class="block truncate text-xs font-mono text-base-content/70" x-text="compactDate(item.last_login_at) || '—'" :title="prettyDateTitle(item.last_login_at) || '—'"></span></td>
                                        <td>
                                            <div class="flex items-center justify-end gap-1">
                                                <button class="btn btn-ghost btn-sm btn-square min-h-9 h-9 w-9" @click.stop="select(item)" title="Edit profile" aria-label="Edit profile">
                                                    <i class="hgi-stroke hgi-pencil-edit-02 text-base-content/70"></i>
                                                </button>
                                                <button class="btn btn-ghost btn-sm btn-square min-h-9 h-9 w-9 text-error" @click.stop="openDeleteModal(item)" title="Delete profile" :disabled="isProtectedSysadmin(item)" :aria-label="isProtectedSysadmin(item) ? 'Configured Hub sysadmin profiles cannot be deleted' : 'Delete profile'">
                                                    <i class="hgi-stroke hgi-delete-02"></i>
                                                </button>
                                            </div>
                                        </td>
                                    </tr>
                                </template>

                                <template x-if="!loading && !load_error && records.length === 0">
                                    <tr>
                                        <td colspan="7" class="px-6 py-12 text-center">
                                            <div class="mx-auto flex max-w-md flex-col items-center gap-3 text-base-content/65">
                                                <i class="hgi-stroke hgi-user-group text-3xl text-base-content/35"></i>
                                                <div>
                                                    <p class="font-medium text-base-content" x-text="hasActiveFilters() ? 'No profiles match these filters.' : 'No profiles yet.'"></p>
                                                    <p class="mt-1 text-sm" x-text="hasActiveFilters() ? 'Clear filters or search for a different name, email, or mobile.' : 'Create the first identity for this app.'"></p>
                                                </div>
                                                <button type="button" class="btn btn-sm" @click="hasActiveFilters() ? resetFilters() : addNew()" x-text="hasActiveFilters() ? 'Clear filters' : 'New Profile'"></button>
                                            </div>
                                        </td>
                                    </tr>
                                </template>
                            </tbody>
                        </table>
                    </div>
                </div>

                <!-- Edit Drawer -->
                <div class="fixed inset-0 z-[1000]" x-show="drawer_open" x-cloak style="display: none;" @keydown.escape.window="closeDrawer()">
                    <button type="button" class="absolute inset-0 bg-base-content/20" aria-label="Close profile editor" @click="closeDrawer()"></button>
                    <aside class="absolute right-0 top-0 flex h-full w-full max-w-2xl flex-col border-l border-base-300 bg-base-100 shadow-2xl" role="dialog" aria-modal="true" aria-labelledby="profile-drawer-title" tabindex="-1" x-ref="drawerPanel" x-trap.noscroll="drawer_open" x-show="drawer_open" x-transition:enter="transition ease-out duration-200" x-transition:enter-start="translate-x-full" x-transition:enter-end="translate-x-0" x-transition:leave="transition ease-in duration-150" x-transition:leave-start="translate-x-0" x-transition:leave-end="translate-x-full">
                        <header class="flex items-start justify-between gap-4 border-b border-base-300 px-6 py-5">
                            <div class="min-w-0">
                                <p class="text-xs font-medium uppercase tracking-[0.14em] text-base-content/45" x-text="current_record.id ? 'Profile details' : 'New profile'"></p>
                                <h2 id="profile-drawer-title" class="mt-1 text-xl font-semibold tracking-tight" x-text="current_record.id ? (current_record.full_name || 'Unnamed profile') : 'Create profile'"></h2>
                                <p class="mt-1 truncate text-sm text-base-content/60" x-text="current_record.email || 'Add identity and access details.'"></p>
                            </div>
                            <button type="button" class="btn btn-ghost btn-sm btn-circle" @click="closeDrawer()" aria-label="Close profile editor">
                                <i class="hgi-stroke hgi-cancel-01"></i>
                            </button>
                        </header>

                        <div class="flex-1 overflow-y-auto px-6 py-5">
                            <div class="space-y-7">
                                <section class="space-y-4">
                                    <div>
                                        <h3 class="text-sm font-semibold">Identity</h3>
                                        <p class="text-sm text-base-content/55">Name, contact details, and the app this profile belongs to.</p>
                                    </div>
                                    <cf_table_controls table_name="moo_profile" fields="full_name" />
                                    <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
                                        <cf_table_controls table_name="moo_profile" fields="email,mobile" />
                                    </div>
                                </section>

                                <section class="space-y-4 border-t border-base-300 pt-6">
                                    <div>
                                        <h3 class="text-sm font-semibold">Profile picture</h3>
                                        <p class="text-sm text-base-content/55">Used in the shell and profile lists where available.</p>
                                    </div>
                                    <cf_table_controls table_name="moo_profile" fields="profile_picture_id" />
                                </section>

                                <section class="space-y-4 border-t border-base-300 pt-6">
                                    <div>
                                        <h3 class="text-sm font-semibold">Permissions</h3>
                                        <p class="text-sm text-base-content/55">Roles and login access for this identity.</p>
                                    </div>
                                    <cf_table_controls table_name="moo_profile" fields="roles" />
                                    <template x-if="isProtectedSysadmin(current_record)">
                                        <div class="alert alert-info text-sm">
                                            <i class="hgi-stroke hgi-shield-01"></i>
                                            <span>Configured Hub sysadmin. Login access is required and this profile cannot be deleted.</span>
                                        </div>
                                    </template>
                                    <div x-show="!isProtectedSysadmin(current_record)">
                                        <cf_table_controls table_name="moo_profile" fields="can_login" />
                                    </div>
                                </section>

                                <section class="space-y-4 border-t border-base-300 pt-6">
                                    <div>
                                        <h3 class="text-sm font-semibold">Authentication links</h3>
                                        <p class="text-sm text-base-content/55">External or local identities connected to this profile.</p>
                                    </div>
                                    <template x-if="current_record.auth_identities?.length">
                                        <div class="divide-y divide-base-300 rounded-box border border-base-300">
                                            <template x-for="identity in current_record.auth_identities" :key="identity.provider + ':' + identity.provider_subject">
                                                <div class="px-3 py-2 text-xs font-mono text-base-content/70 break-all" x-text="formatAuthIdentity(identity)"></div>
                                            </template>
                                        </div>
                                    </template>
                                    <template x-if="!current_record.auth_identities?.length">
                                        <div class="rounded-box border border-dashed border-base-300 px-4 py-3 text-sm text-base-content/55">No auth identities linked.</div>
                                    </template>
                                </section>
                            </div>
                        </div>

                        <footer class="flex flex-col-reverse gap-3 border-t border-base-300 bg-base-100/95 px-6 py-4 shadow-[0_-8px_24px_oklch(19.5%_0.02_41_/_0.06)] sm:flex-row sm:items-center sm:justify-between">
                            <button type="button" class="btn btn-ghost btn-sm text-error" @click="openDeleteModal(current_record)" x-show="current_record.id && !isProtectedSysadmin(current_record)">
                                <i class="hgi-stroke hgi-delete-02"></i>
                                Delete
                            </button>
                            <div class="flex justify-end gap-2 sm:ml-auto">
                                <button type="button" class="btn btn-ghost btn-sm" @click="closeDrawer()">Cancel</button>
                                <button type="button" class="btn btn-primary btn-sm" @click="handleSave" :disabled="saving">
                                    <span class="loading loading-spinner loading-xs" x-show="saving"></span>
                                    <i class="hgi-stroke hgi-tick-02" x-show="!saving"></i>
                                    Save
                                </button>
                            </div>
                        </footer>
                    </aside>
                </div>

                <!-- Discard Changes Modal -->
                <dialog id="discard_modal" class="modal" x-ref="discardModal">
                    <div class="modal-box max-w-sm">
                        <div class="flex items-start gap-3">
                            <div class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-warning/12 text-warning">
                                <i class="hgi-stroke hgi-alert-02 text-xl"></i>
                            </div>
                            <div>
                                <h3 class="text-lg font-semibold">Discard changes?</h3>
                                <p class="mt-2 text-sm text-base-content/65">This profile has unsaved edits. Closing now will lose those changes.</p>
                            </div>
                        </div>
                        <div class="modal-action">
                            <form method="dialog">
                                <button class="btn btn-ghost">Keep editing</button>
                            </form>
                            <button type="button" class="btn btn-warning" @click="discardDrawerChanges()">
                                Discard changes
                            </button>
                        </div>
                    </div>
                    <form method="dialog" class="modal-backdrop">
                        <button>close</button>
                    </form>
                </dialog>

                <!-- Delete Confirmation Modal -->
                <dialog id="delete_modal" class="modal" x-ref="deleteModal">
                    <div class="modal-box max-w-sm text-center">
                        <div class="py-4">
                            <i class="hgi-stroke hgi-alert-02 text-3xl text-error mb-4 block"></i>
                            <h3 class="text-lg font-semibold">Delete Profile</h3>
                            <p class="text-base-content/70 mt-2">
                                Are you sure you want to delete <span class="font-medium" x-text="current_record.full_name"></span>?
                            </p>
                            <p class="text-sm text-error mt-2">This action cannot be undone.</p>
                        </div>
                        <div class="modal-action justify-center">
                            <form method="dialog">
                                <button class="btn btn-ghost">Cancel</button>
                            </form>
                            <button class="btn btn-error" @click="deleteRecord">
                                <i class="hgi-stroke hgi-delete-02"></i>
                                Delete
                            </button>
                        </div>
                    </div>
                    <form method="dialog" class="modal-backdrop">
                        <button>close</button>
                    </form>
                </dialog>

                <script>
                document.addEventListener('alpine:init', () => {
                    const default_filters = { term: '', app_name: '' };

                    Alpine.data('profiles_admin', () => ({
                        loading: false,
                        loading_indicator: false,
                        loading_indicator_timer: null,
                        loading_request_id: 0,
                        saving: false,
                        load_error: false,
                        drawer_open: false,
                        drawer_reset_timer: null,
                        drawer_original_record: '',
                        pending_drawer_close: false,
                        records: [],
                        total_count: 0,
                        current_record: {},
                        filters: { ...default_filters },
                        app_names: [],

                        getInitials(name) {
                            const cleaned = (name || '').trim();
                            if (!cleaned) return '?';
                            const parts = cleaned.split(/\s+/).filter(Boolean);
                            if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
                            return parts.slice(0, 2).map(p => (p[0] || '')).join('').toUpperCase();
                        },

                        async init() {
                            this.filters = await loadFilters(default_filters);
                            this.app_names = await req({ endpoint: 'getAppNames' });
                            await this.load();
                        },

                        async load() {
                            const requestId = ++this.loading_request_id;
                            this.loading = true;
                            this.loading_indicator = false;
                            clearTimeout(this.loading_indicator_timer);
                            this.loading_indicator_timer = setTimeout(() => {
                                if (this.loading_request_id === requestId) {
                                    this.loading_indicator = true;
                                }
                            }, 180);
                            this.load_error = false;
                            try {
                                await saveFilters(this.filters);
                                const records = await req({
                                    endpoint: 'search',
                                    body: { filter: this.filters }
                                });
                                if (this.loading_request_id !== requestId) return;
                                this.records = Array.isArray(records) ? records : [];
                                this.total_count = this.records[0]?.total_count || this.records.length;
                            } catch (error) {
                                if (this.loading_request_id !== requestId) return;
                                this.load_error = true;
                                this.records = [];
                                this.total_count = 0;
                            } finally {
                                if (this.loading_request_id === requestId) {
                                    clearTimeout(this.loading_indicator_timer);
                                    this.loading = false;
                                    this.loading_indicator = false;
                                }
                            }
                        },

                        async resetFilters() {
                            this.filters = { ...default_filters };
                            await clearFilters();
                            await this.load();
                        },

                        async handleSave() {
                            if (this.saving) return;
                            this.saving = true;
                            try {
                                await req({ endpoint: 'save', body: this.current_record });
                                this.drawer_original_record = JSON.stringify(this.current_record || {});
                                this.closeDrawer({ force: true });
                                await this.load();
                                if (window.toast) {
                                    window.toast({ type: 'success', message: 'Profile saved successfully', duration: 2000 });
                                }
                            } finally {
                                this.saving = false;
                            }
                        },

                        async addNew() {
                            clearTimeout(this.drawer_reset_timer);
                            this.current_record = await req({ endpoint: 'new' });
                            this.drawer_original_record = JSON.stringify(this.current_record || {});
                            this.drawer_open = true;
                            this.$nextTick(() => this.$refs.drawerPanel?.focus());
                        },

                        select(item) {
                            clearTimeout(this.drawer_reset_timer);
                            this.current_record = JSON.parse(JSON.stringify(item));
                            this.drawer_original_record = JSON.stringify(this.current_record || {});
                            this.drawer_open = true;
                            this.$nextTick(() => this.$refs.drawerPanel?.focus());
                        },

                        isDrawerDirty() {
                            return this.drawer_open && JSON.stringify(this.current_record || {}) !== this.drawer_original_record;
                        },

                        closeDrawer(options = {}) {
                            if (!options.force && this.isDrawerDirty()) {
                                this.pending_drawer_close = true;
                                this.$refs.discardModal.showModal();
                                return;
                            }
                            this.drawer_open = false;
                            this.pending_drawer_close = false;
                            clearTimeout(this.drawer_reset_timer);
                            this.drawer_reset_timer = setTimeout(() => {
                                if (!this.drawer_open) {
                                    this.current_record = {};
                                    this.drawer_original_record = '';
                                }
                            }, 220);
                        },

                        discardDrawerChanges() {
                            this.$refs.discardModal.close();
                            this.closeDrawer({ force: true });
                        },

                        openDeleteModal(item) {
                            if (this.isProtectedSysadmin(item)) {
                                if (window.toast) {
                                    window.toast({ type: 'error', message: 'Configured Hub sysadmin profiles cannot be deleted.', duration: 3000 });
                                }
                                return;
                            }
                            this.current_record = item;
                            this.$refs.deleteModal.showModal();
                        },

                        async deleteRecord() {
                            if (this.isProtectedSysadmin(this.current_record)) {
                                this.$refs.deleteModal.close();
                                if (window.toast) {
                                    window.toast({ type: 'error', message: 'Configured Hub sysadmin profiles cannot be deleted.', duration: 3000 });
                                }
                                return;
                            }
                            await req({ endpoint: 'delete', id: this.current_record.id });
                            this.$refs.deleteModal.close();
                            this.closeDrawer({ force: true });
                            await this.load();
                            if (window.toast) {
                                window.toast({ type: 'success', message: 'Profile deleted', duration: 2000 });
                            }
                        },

                        isProtectedSysadmin(profile) {
                            return !!profile?.is_configured_sysadmin;
                        },

                        hasActiveFilters() {
                            return Object.values(this.filters || {}).some(value => `${value || ''}`.trim().length);
                        },

                        resultSummary() {
                            const total = this.total_count || this.records.length;
                            if (this.loading && !total) return '';
                            if (!total) return 'No profiles';
                            if (total === 1) return '1 profile';
                            return `${total} profiles`;
                        },

                        compactDate(value) {
                            if (!value) return '';
                            const date = new Date(value);
                            if (Number.isNaN(date.getTime())) return '';

                            const seconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000));
                            if (seconds < 60) return 'now';
                            if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
                            if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
                            if (seconds < 604800) return `${Math.floor(seconds / 86400)}d ago`;
                            return prettyDate(value);
                        },

                        formatAuthIdentity(identity) {
                            if (!identity) return '';
                            return `${identity.provider}: ${identity.provider_subject}`;
                        },

                        authIdentityTitle(identities) {
                            return (identities || []).map(identity => this.formatAuthIdentity(identity)).join('\n');
                        }
                    }));
                });
                </script>
            </div>

        </cf_layout_default>
    </cffunction>


</cfcomponent>
