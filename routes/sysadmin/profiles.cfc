<cfcomponent key="88fcf7cb-d88c-41b0-b1c8-861c1cfe1895" open_to="security">


    <cffunction name="uploadFileToServerWithProgress.profile_picture_id">
        <cfreturn application.lib.db.getService(table_name="moo_file").uploadFileToServerWithProgress(data="#request.data#") />
    </cffunction>


    <cffunction name="read">
        <cfreturn application.lib.db.read(table_name='moo_profile', id=id, field_list="*", returnFormat="cfml") />
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
        <cfif NOT (structKeyExists(profile, "id") AND isConfiguredHubSysadminEmail(profile.email ?: "", profile.app_name ?: ""))>
            <cfreturn false />
        </cfif>

        <!--- Duplicate rows for the same sysadmin email (e.g. stale pre-migration profiles)
              stay editable/deletable: only the sole remaining row is protected. --->
        <cfquery name="local.qDuplicates" returntype="array">
            SELECT count(*)::int AS profile_count
            FROM moo_profile
            WHERE app_name = 'hub'
              AND lower(email) = lower(<cfqueryparam cfsqltype="varchar" value="#profile.email#" />)
        </cfquery>

        <cfreturn local.qDuplicates[1].profile_count LTE 1 />
    </cffunction>


    <cffunction name="search">

        <cfset searchTerm = request.data.filter.term?:'' />
        <cfset appNameFilter = request.data.filter.app_name?:'' />
        <!--- One profile by id, for links that open it straight in the drawer (?profile_id=). --->
        <cfset profileIdFilter = request.data.profile_id?:'' />
        <cfset limit = val(request.data.limit ?: 20) />
        <cfset offset = val(request.data.offset ?: 0) />
        <cfif NOT listFind("20,50,100", limit)>
            <cfthrow type="moopa.security.invalidProfileLimit" message="Profile search limit must be one of 20, 50, or 100." />
        </cfif>
        <cfif offset LT 0>
            <cfthrow type="moopa.security.invalidProfileOffset" message="Profile search offset cannot be negative." />
        </cfif>

        <cfquery name="qData">
        SELECT COALESCE(array_to_json(array_agg(row_to_json(data)))::text, '[]') AS recordset
        FROM (
            SELECT #application.lib.db.select(table_name="moo_profile", field_list="id,app_name,full_name,email,mobile,address,roles,is_employee,employee_type,can_login,profile_picture_id,profile_avatar_id,last_login_at")#,
                (
                    moo_profile.app_name = 'hub'
                    AND lower(moo_profile.email) IN (<cfqueryparam cfsqltype="varchar" value="#getSysadminEmailList()#" list="true" />)
                    <!--- Duplicate rows for the same sysadmin email (e.g. stale pre-migration
                          profiles) stay deletable: only the sole remaining row is protected. --->
                    AND (
                        SELECT count(*)
                        FROM moo_profile dup
                        WHERE dup.app_name = 'hub'
                          AND lower(dup.email) = lower(moo_profile.email)
                    ) = 1
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
            <cfif len(profileIdFilter)>
                AND moo_profile.id = <cfqueryparam cfsqltype="other" value="#profileIdFilter#" />
            </cfif>
            <cfif len(searchTerm)>
                ORDER BY word_similarity(<cfqueryparam cfsqltype="varchar" value="#searchTerm#" />, search_text) DESC
            <cfelse>
                ORDER BY moo_profile.full_name
            </cfif>
            LIMIT <cfqueryparam cfsqltype="integer" value="#limit#" />
            OFFSET <cfqueryparam cfsqltype="integer" value="#offset#" />
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
            returnFormat = "cfml"
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

    <cffunction name="resetPassword">
        <cfif NOT structKeyExists(application.lib, "auth_local_password")>
            <cfthrow type="moopa.auth.providerMissing" message="The local password auth provider is not available in this app." />
        </cfif>
        <cfreturn serializeJSON(application.lib.auth_local_password.provisionTempPassword(profile_id=url.id ?: "")) />
    </cffunction>


    <cffunction name="search.current_record.roles">
        <cfreturn application.lib.db.search(table_name='moo_role', q="#url.q?:''#") />
    </cffunction>

    <cffunction name="search.roles">
        <cfreturn application.lib.db.search(table_name='moo_role', q="#url.q?:''#", field_list="id,label") />
    </cffunction>


    <cffunction name="get" output="true">
        <cfmodule template="/moopa/tags/moopa_layout.cfm" title="Profiles">

            <div x-data="profiles_admin" x-cloak class="page">
                <div class="page-header">
                    <div>
                        <div class="eyebrow" x-text="resultSummary()"></div>
                        <h1>Profiles</h1>
                        <p class="page-lede">People: who they are, whether they can sign in, their roles and how they sign in.</p>
                    </div>
                    <div class="page-actions">
                        <button type="button" class="btn btn-primary btn-sm" @click="addNew"><i class="fa-solid fa-plus"></i> New profile</button>
                    </div>
                </div>

                <template x-if="load_error">
                    <div class="alert alert-danger">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        <div class="grow"><div class="strong">Profiles could not be loaded.</div><div>Try again, or check the error log if it keeps happening.</div></div>
                        <button type="button" class="btn btn-sm" @click="load()">Retry</button>
                    </div>
                </template>

                <div class="card" x-show="has_loaded || load_error">
                    <div class="card-header">
                        <div class="cluster">
                            <div class="input-icon" style="width: 18rem; max-width: 100%" @input.debounce.500ms="load({ resetOffset: true })" @change.stop>
                                <i class="fa-solid fa-magnifying-glass"></i>
                                <input class="input input-sm" type="search" aria-label="Search profiles" placeholder="Search name, email or mobile" x-model="filters.term">
                            </div>
                            <select class="select select-sm" style="width: 10rem" aria-label="Filter profiles by app" x-model="filters.app_name" @change="load({ resetOffset: true })">
                                <option value="">All apps</option>
                                <template x-for="app in app_names" :key="app">
                                    <option :value="app" x-text="app"></option>
                                </template>
                            </select>
                            <button type="button" class="btn btn-ghost btn-sm" @click="resetFilters()" :disabled="!hasActiveFilters()">Reset</button>
                        </div>
                    </div>

                    <div class="table-wrap">
                        <table class="table table-sm table-hover table-clickable">
                            <thead>
                                <tr><th>Person</th><th>App</th><th>Roles</th><th>Sign-in</th><th>Signs in with</th><th>Last sign-in</th><th class="actions">Actions</th></tr>
                            </thead>
                            <tbody>
                                <template x-for="item in records" :key="item.id">
                                    <tr tabindex="0" @click="select(item)" @keydown.enter.prevent="select(item)" :aria-label="`Edit profile ${item.full_name || item.email || 'profile'}`">
                                        <td>
                                            <div class="row" style="gap: var(--sp-3)">
                                                <span class="avatar">
                                                    <template x-if="item.profile_picture_id?.thumbnail"><img :src="item.profile_picture_id.thumbnail" :alt="item.full_name" /></template>
                                                    <template x-if="!item.profile_picture_id?.thumbnail"><span x-text="getInitials(item.full_name)"></span></template>
                                                </span>
                                                <div class="min0">
                                                    <div class="row">
                                                        <span class="cell-main truncate" x-text="item.full_name || 'Unnamed profile'" :title="item.full_name"></span>
                                                        <template x-if="isProtectedSysadmin(item)">
                                                            <span class="badge badge-signal" title="Configured Hub sysadmin"><i class="fa-solid fa-shield-halved"></i> Protected</span>
                                                        </template>
                                                    </div>
                                                    <div class="cell-sub truncate" x-text="item.email" :title="item.email"></div>
                                                </div>
                                            </div>
                                        </td>
                                        <td><span class="mono muted" x-text="item.app_name || '—'"></span></td>
                                        <td>
                                            <div class="cluster" style="--cluster-gap: var(--sp-1)">
                                                <template x-for="role in item.role_labels" :key="role"><span class="badge" x-text="role"></span></template>
                                                <span class="muted" x-show="!item.role_labels?.length">—</span>
                                            </div>
                                        </td>
                                        <td>
                                            <div class="stack stack-xs">
                                                <span class="row small" :class="item.can_login ? 'text-success' : 'muted'">
                                                    <i class="fa-solid" :class="item.can_login ? 'fa-right-to-bracket' : 'fa-lock'"></i>
                                                    <span x-text="isProtectedSysadmin(item) ? 'Protected' : (item.can_login ? 'Can sign in' : 'Sign-in off')"></span>
                                                </span>
                                                <template x-if="item.is_employee"><span class="badge badge-info" x-text="item.employee_type || 'employee'"></span></template>
                                            </div>
                                        </td>
                                        <td style="max-width: 16rem">
                                            <span class="mono muted truncate" style="display: block" x-show="item.auth_identities?.length" x-text="item.auth_identities?.length ? formatAuthIdentity(item.auth_identities[0]) : ''" :title="authIdentityTitle(item.auth_identities || [])"></span>
                                            <span class="muted" x-show="!item.auth_identities?.length">—</span>
                                        </td>
                                        <td><span class="mono muted nowrap" x-text="compactDate(item.last_login_at) || '—'" :title="prettyDateTitle(item.last_login_at) || '—'"></span></td>
                                        <td class="actions">
                                            <button type="button" class="btn btn-ghost btn-icon btn-sm" @click.stop="select(item)" title="Edit profile" aria-label="Edit profile"><i class="fa-solid fa-pen-to-square"></i></button>
                                            <!--- Not :disabled: keep it clickable so openDeleteModal can explain why a protected profile can't go --->
                                            <button type="button" class="btn btn-ghost btn-icon btn-sm text-danger" :style="isProtectedSysadmin(item) ? 'opacity: 0.4; cursor: not-allowed' : ''" @click.stop="openDeleteModal(item)" title="Delete profile" :aria-disabled="isProtectedSysadmin(item)" :aria-label="isProtectedSysadmin(item) ? 'Configured Hub sysadmin profiles cannot be deleted' : 'Delete profile'"><i class="fa-solid fa-trash"></i></button>
                                        </td>
                                    </tr>
                                </template>
                            </tbody>
                        </table>
                    </div>

                    <div class="empty" x-show="!loading && !load_error && records.length === 0">
                        <i class="fa-solid fa-users"></i>
                        <p class="strong secondary" x-text="hasActiveFilters() ? 'No profiles match these filters.' : 'No profiles yet.'"></p>
                        <p class="small" x-text="hasActiveFilters() ? 'Clear the filters, or search for a different name, email or mobile.' : 'Create the first one for this app.'"></p>
                        <button type="button" class="btn btn-sm mt-2" @click="hasActiveFilters() ? resetFilters() : addNew()" x-text="hasActiveFilters() ? 'Clear filters' : 'New profile'"></button>
                    </div>

                    <div class="card-footer cluster cluster-end small muted" x-show="!loading && !load_error && total_count > 0">
                        <label class="row">
                            <span class="eyebrow">Rows</span>
                            <select class="select select-sm" style="width: 4.5rem" x-model.number="limit" @change="load({ resetOffset: true })" aria-label="Profiles per page">
                                <option :value="20">20</option>
                                <option :value="50">50</option>
                                <option :value="100">100</option>
                            </select>
                        </label>
                        <span><strong class="secondary" x-text="rangeStart()"></strong>–<strong class="secondary" x-text="records.length"></strong> of <strong class="secondary" x-text="total_count"></strong></span>
                        <button type="button" class="btn btn-ghost btn-xs" x-show="canShowMore()" @click="showMore()">More</button>
                    </div>
                </div>

                <dialog class="modal modal-lg" aria-labelledby="profile-editor-title"
                    x-effect="drawer_open ? ($el.open || $el.showModal()) : ($el.open && $el.close())"
                    @cancel.prevent="closeDrawer()" @close="editorClosed($el)">
                    <div class="modal-header">
                        <div>
                            <div class="eyebrow" x-text="current_record.id ? 'Profile' : 'New profile'"></div>
                            <h2 id="profile-editor-title" class="card-title" x-text="current_record.id ? (current_record.full_name || 'Unnamed profile') : 'Create a profile'"></h2>
                            <p class="card-sub truncate" x-text="current_record.email || 'Identity and access details.'"></p>
                        </div>
                        <button type="button" class="btn btn-ghost btn-icon btn-sm" @click="closeDrawer()" aria-label="Close"><i class="fa-solid fa-xmark"></i></button>
                    </div>

                    <div class="modal-body">
                        <section class="modal-section stack">
                            <div><h3 class="strong">Identity</h3><p class="help">Name and contact details.</p></div>
                            <div class="field">
                                <label class="label" for="profile-full-name">Full name</label>
                                <input id="profile-full-name" class="input" type="text" x-model="current_record.full_name" autocomplete="off">
                            </div>
                            <div class="auto-grid" style="--auto-min: 14rem">
                                <div class="field">
                                    <label class="label" for="profile-email">Email</label>
                                    <input id="profile-email" class="input" type="email" x-model="current_record.email" autocomplete="off">
                                </div>
                                <div class="field">
                                    <label class="label" for="profile-mobile">Mobile</label>
                                    <input id="profile-mobile" class="input" type="tel" x-model="current_record.mobile" autocomplete="off">
                                </div>
                            </div>
                        </section>

                        <section class="modal-section stack">
                            <div><h3 class="strong">Picture</h3><p class="help">Shown in menus and lists where there's room.</p></div>
                            <div class="row" style="gap: var(--sp-4)">
                                <span class="avatar avatar-lg">
                                    <template x-if="current_record.profile_picture_id?.thumbnail"><img :src="current_record.profile_picture_id.thumbnail" alt="" /></template>
                                    <template x-if="!current_record.profile_picture_id?.thumbnail"><span x-text="getInitials(current_record.full_name)"></span></template>
                                </span>
                                <div class="cluster">
                                    <label class="btn btn-sm" :aria-disabled="picture_uploading">
                                        <i class="fa-solid" :class="picture_uploading ? 'fa-spinner fa-spin' : 'fa-upload'"></i>
                                        <span x-text="current_record.profile_picture_id?.id ? 'Replace' : 'Upload'"></span>
                                        <input type="file" accept="image/*" hidden @change="uploadPicture($event)">
                                    </label>
                                    <button type="button" class="btn btn-ghost btn-sm" x-show="current_record.profile_picture_id?.id" @click="current_record.profile_picture_id = ''">Remove</button>
                                </div>
                            </div>
                        </section>

                        <section class="modal-section stack">
                            <div><h3 class="strong">Access</h3><p class="help">Roles, and whether this profile can sign in.</p></div>
                            <div class="field">
                                <span class="label">Roles</span>
                                <div class="cluster" style="--cluster-gap: var(--sp-1)">
                                    <template x-for="role in (current_record.roles || [])" :key="role.id">
                                        <span class="badge badge-signal">
                                            <span x-text="role.label || role.name"></span>
                                            <button type="button" @click="removeRole(role.id)" :aria-label="`Remove ${role.label || role.name}`"><i class="fa-solid fa-xmark"></i></button>
                                        </span>
                                    </template>
                                    <span class="muted small" x-show="!(current_record.roles || []).length">None</span>
                                </div>
                                <div class="input-icon">
                                    <i class="fa-solid fa-magnifying-glass"></i>
                                    <input class="input input-sm" type="search" placeholder="Add a role" aria-label="Add a role" x-model="role_q" @input.debounce.250ms="searchRoles()" @focus="searchRoles()">
                                </div>
                                <div class="card list-rows" style="max-height: 12rem; overflow: auto; box-shadow: none" x-show="role_results.length">
                                    <template x-for="role in role_results" :key="role.id">
                                        <button type="button" class="list-row" @click="addRole(role)"><span class="cell-main truncate" x-text="role.label"></span><i class="fa-solid fa-plus muted"></i></button>
                                    </template>
                                </div>
                            </div>
                            <template x-if="isProtectedSysadmin(current_record)">
                                <div class="alert alert-info"><i class="fa-solid fa-shield-halved"></i><span>A configured Hub sysadmin: it must be able to sign in, and it can't be deleted.</span></div>
                            </template>
                            <label class="option" x-show="!isProtectedSysadmin(current_record)">
                                <input type="checkbox" class="switch" x-model="current_record.can_login">
                                <span>Can sign in</span>
                            </label>
                        </section>

                        <section class="modal-section stack">
                            <div><h3 class="strong">Sign-in identities</h3><p class="help">The local or external identities this profile signs in with.</p></div>
                            <div class="card list-rows" style="box-shadow: none" x-show="current_record.auth_identities?.length">
                                <template x-for="identity in (current_record.auth_identities || [])" :key="identity.provider + ':' + identity.provider_subject">
                                    <div class="list-row mono small secondary break" x-text="formatAuthIdentity(identity)"></div>
                                </template>
                            </div>
                            <p class="muted small" x-show="!current_record.auth_identities?.length">None linked.</p>

                            <div class="stack stack-sm" x-show="current_record.id && current_record.can_login">
                                <div><button type="button" class="btn btn-sm" @click="generateInvite()" :disabled="generating_invite">
                                    <i class="fa-solid" :class="generating_invite ? 'fa-spinner fa-spin' : 'fa-key'"></i>
                                    <span x-text="hasLocalPassword(current_record) ? 'Reset password and invite' : 'Generate a password and invite'"></span>
                                </button></div>
                                <template x-if="invite">
                                    <div class="alert alert-warning" style="display: block">
                                        <p class="strong">This temporary password is shown once. Copy the invite now and send it.</p>
                                        <pre class="code-block mt-2" x-text="inviteText()"></pre>
                                        <button type="button" class="btn btn-primary btn-sm mt-2" @click="copyInvite()"><i class="fa-solid fa-copy"></i> Copy invite</button>
                                    </div>
                                </template>
                            </div>
                        </section>
                    </div>

                    <div class="modal-footer" x-show="!pending_drawer_close && !confirming_delete">
                        <button type="button" class="btn btn-ghost btn-sm text-danger" style="margin-right: auto" @click="openDeleteModal(current_record)" x-show="current_record.id && !isProtectedSysadmin(current_record)"><i class="fa-solid fa-trash"></i> Delete</button>
                        <button type="button" class="btn btn-sm" @click="closeDrawer()">Cancel</button>
                        <button type="button" class="btn btn-primary btn-sm" @click="handleSave" :disabled="saving || picture_uploading">
                            <i class="fa-solid" :class="saving ? 'fa-spinner fa-spin' : 'fa-check'"></i> Save
                        </button>
                    </div>
                    <!--- Confirmations stay in the editor: a second modal dialog stacked on this one is fragile in browsers --->
                    <div class="modal-footer" style="align-items: center" x-show="pending_drawer_close" x-cloak role="alertdialog" aria-label="Discard changes">
                        <span class="grow row small"><i class="fa-solid fa-triangle-exclamation text-warning"></i> Discard your unsaved changes?</span>
                        <button type="button" class="btn btn-sm" @click="keepEditing()">Keep editing</button>
                        <button type="button" class="btn btn-danger-solid btn-sm" @click="discardDrawerChanges()">Discard changes</button>
                    </div>
                    <div class="modal-footer" style="align-items: center" x-show="confirming_delete" x-cloak role="alertdialog" aria-label="Delete profile">
                        <span class="grow row small"><i class="fa-solid fa-trash text-danger"></i> Delete <strong x-text="current_record.full_name || 'this profile'"></strong>? This can't be undone.</span>
                        <button type="button" class="btn btn-sm" @click="confirming_delete = false">Cancel</button>
                        <button type="button" class="btn btn-danger-solid btn-sm" @click="deleteRecord"><i class="fa-solid fa-trash"></i> Delete</button>
                    </div>
                </dialog>

                <dialog id="delete_modal" class="modal modal-sm" x-ref="deleteModal" aria-labelledby="profile-delete-title">
                    <div class="modal-body row row-top" style="gap: var(--sp-3)">
                        <span class="avatar" style="background: var(--danger-surface); border-color: var(--danger-border); color: var(--danger)"><i class="fa-solid fa-trash"></i></span>
                        <div class="stack stack-xs">
                            <h2 id="profile-delete-title" class="card-title">Delete <span x-text="current_record.full_name || 'this profile'"></span>?</h2>
                            <p class="muted small">This can't be undone.</p>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-sm" @click="$refs.deleteModal.close()">Cancel</button>
                        <button type="button" class="btn btn-danger-solid btn-sm" @click="deleteRecord"><i class="fa-solid fa-trash"></i> Delete</button>
                    </div>
                </dialog>

                <script>
                document.addEventListener('alpine:init', () => {
                    const default_filters = { term: '', app_name: '' };

                    Alpine.data('profiles_admin', () => ({
                        loading: false,
                        has_loaded: false,
                        loading_request_id: 0,
                        saving: false,
                        load_error: false,
                        drawer_open: false,
                        drawer_reset_timer: null,
                        drawer_original_record: '',
                        pending_drawer_close: false,
                        confirming_delete: false,
                        records: [],
                        total_count: 0,
                        limit: 20,
                        offset: 0,
                        current_record: {},
                        filters: { ...default_filters },
                        app_names: [],
                        invite: null,
                        generating_invite: false,

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
                            await this.openLinkedProfile();
                        },

                        // ?profile_id=<id> opens that profile in the drawer, so other pages can link to it.
                        async openLinkedProfile() {
                            const profileId = new URLSearchParams(window.location.search).get('profile_id');
                            if (!profileId) return;
                            const [profile] = await req({ endpoint: 'search', body: { profile_id: profileId, limit: 20, offset: 0 } });
                            if (profile) {
                                this.select(profile);
                            } else if (window.toast) {
                                window.toast({ type: 'error', message: 'That profile no longer exists.', duration: 3000 });
                            }
                        },

                        async load(options = {}) {
                            if (options.resetOffset) {
                                this.offset = 0;
                            }
                            const requestId = ++this.loading_request_id;
                            this.loading = true;
                            this.load_error = false;
                            try {
                                await saveFilters(this.filters);
                                const records = await req({
                                    endpoint: 'search',
                                    body: {
                                        filter: this.filters,
                                        limit: this.limit,
                                        offset: this.offset
                                    }
                                });
                                if (this.loading_request_id !== requestId) return;
                                const nextRecords = Array.isArray(records) ? records : [];
                                this.records = options.append ? [...this.records, ...nextRecords] : nextRecords;
                                this.total_count = this.records[0]?.total_count || this.records.length;
                                this.has_loaded = true;
                            } catch (error) {
                                if (this.loading_request_id !== requestId) return;
                                this.load_error = true;
                                this.records = [];
                                this.total_count = 0;
                                this.has_loaded = true;
                            } finally {
                                if (this.loading_request_id === requestId) {
                                    this.loading = false;
                                }
                            }
                        },

                        async resetFilters() {
                            this.filters = { ...default_filters };
                            this.offset = 0;
                            await clearFilters();
                            await this.load();
                        },

                        async handleSave() {
                            if (this.saving) return;
                            this.saving = true;
                            try {
                                const isNew = !this.current_record.id;
                                const saved = await req({ endpoint: 'save', body: this.current_record });
                                const savedRecord = typeof saved === 'string' ? JSON.parse(saved) : saved;

                                if (isNew && savedRecord?.id && this.current_record.can_login) {
                                    // New login-enabled profile: keep the drawer open and hand the admin an invite.
                                    this.current_record = { ...this.current_record, ...savedRecord };
                                    this.drawer_original_record = JSON.stringify(this.current_record || {});
                                    await this.load();
                                    await this.generateInvite();
                                    if (window.toast) {
                                        window.toast({ type: 'success', message: 'Profile created — copy the invite below', duration: 4000 });
                                    }
                                    return;
                                }

                                this.drawer_original_record = JSON.stringify(this.current_record || {});
                                this.closeDrawer({ force: true });
                                await this.load();
                                if (window.toast) {
                                    window.toast({ type: 'success', message: 'Profile saved', duration: 2000 });
                                }
                            } finally {
                                this.saving = false;
                            }
                        },

                        hasLocalPassword(profile) {
                            return (profile?.auth_identities || []).some(identity => identity.provider === 'local_password');
                        },

                        async generateInvite() {
                            if (this.generating_invite || !this.current_record.id) return;
                            if (this.hasLocalPassword(this.current_record)
                                && !window.confirm('This replaces the existing password. The user will no longer be able to sign in with their old one. Continue?')) {
                                return;
                            }
                            this.generating_invite = true;
                            try {
                                // Persist any pending drawer edits first so the invite reflects the saved profile.
                                const saved = await req({ endpoint: 'save', body: this.current_record });
                                const savedRecord = typeof saved === 'string' ? JSON.parse(saved) : saved;
                                this.current_record = { ...this.current_record, ...savedRecord };
                                this.invite = await req({ endpoint: 'resetPassword', id: this.current_record.id });
                                this.current_record.auth_identities = [{ provider: 'local_password', provider_subject: this.invite.email }];
                                this.drawer_original_record = JSON.stringify(this.current_record || {});
                                await this.load();
                            } catch (error) {
                                if (window.toast) {
                                    window.toast({ type: 'error', message: 'Could not save the profile and generate a password.', duration: 3000 });
                                }
                            } finally {
                                this.generating_invite = false;
                            }
                        },

                        inviteText() {
                            if (!this.invite) return '';
                            return [
                                `You've been invited to ${window.location.host}.`,
                                '',
                                `Sign in: ${window.location.origin}/login/`,
                                `Email: ${this.invite.email}`,
                                `Temporary password: ${this.invite.temp_password}`,
                                '',
                                "You'll be asked to choose your own password when you first sign in."
                            ].join('\n');
                        },

                        async copyInvite() {
                            try {
                                await navigator.clipboard.writeText(this.inviteText());
                                if (window.toast) {
                                    window.toast({ type: 'success', message: 'Invite copied to clipboard', duration: 2000 });
                                }
                            } catch (error) {
                                if (window.toast) {
                                    window.toast({ type: 'error', message: 'Copy failed — select the text and copy manually.', duration: 3000 });
                                }
                            }
                        },

                        async addNew() {
                            clearTimeout(this.drawer_reset_timer);
                            this.invite = null;
                            this.current_record = await req({ endpoint: 'new' });
                            this.drawer_original_record = JSON.stringify(this.current_record || {});
                            this.drawer_open = true;
                            this.$nextTick(() => this.$refs.drawerPanel?.focus());
                        },

                        // Roles on the editor: search.roles returns [{ id, label }]
                        role_q: '',
                        role_results: [],
                        async searchRoles() {
                            const chosen = new Set((this.current_record.roles || []).map(role => role.id));
                            const found = await req({ endpoint: 'search.roles', q: this.role_q.trim() });
                            this.role_results = (found || []).filter(role => !chosen.has(role.id)).slice(0, 10);
                        },
                        addRole(role) {
                            this.current_record.roles = [...(this.current_record.roles || []), { id: role.id, label: role.label }];
                            this.role_q = '';
                            this.role_results = [];
                        },
                        removeRole(id) {
                            this.current_record.roles = (this.current_record.roles || []).filter(role => role.id !== id);
                        },

                        // The picture: the endpoint makes a moo_file and an upload URL, the browser PUTs the file there,
                        // then the endpoint finishes the record (its thumbnail) — moo_file.uploadFileToServerWithProgress
                        picture_uploading: false,
                        async uploadPicture(event) {
                            const file = event.target.files?.[0];
                            event.target.value = '';
                            if (!file) return;
                            if (!file.type.startsWith('image/')) {
                                window.toast({ type: 'error', message: 'Choose an image file.' });
                                return;
                            }
                            const endpoint = 'uploadFileToServerWithProgress.profile_picture_id';
                            this.picture_uploading = true;
                            try {
                                const started = await req({ endpoint, body: { file_name: file.name, file_size: file.size, parent_table_name: 'moo_profile', parent_field: 'profile_picture_id', parent_id: this.current_record.id || '' } });
                                const put = await fetch(started.presignedURL, { method: 'PUT', headers: { 'Content-Type': file.type || 'application/octet-stream' }, body: file });
                                if (!put.ok) throw new Error(`The upload failed (${put.status}).`);
                                this.current_record.profile_picture_id = await req({ endpoint, body: { file_id: started.file.id } });
                            } catch (error) {
                                if (!String(error.message).startsWith('{')) window.toast({ type: 'error', title: 'The picture was not uploaded', description: error.message });
                            } finally {
                                this.picture_uploading = false;
                            }
                        },

                        select(item) {
                            clearTimeout(this.drawer_reset_timer);
                            this.invite = null;
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
                                return;
                            }
                            this.drawer_open = false;
                            this.pending_drawer_close = false;
                            this.confirming_delete = false;
                            clearTimeout(this.drawer_reset_timer);
                            this.drawer_reset_timer = setTimeout(() => {
                                if (!this.drawer_open) {
                                    this.current_record = {};
                                    this.drawer_original_record = '';
                                    this.invite = null;
                                }
                            }, 220);
                        },

                        keepEditing() {
                            this.pending_drawer_close = false;
                        },

                        discardDrawerChanges() {
                            this.closeDrawer({ force: true });
                        },

                        // The browser closed the editor itself (Chrome only lets a page hold a dialog open on Esc
                        // after the person has interacted since). Unsaved edits: reopen it and ask. Otherwise close
                        // it properly, so drawer_open is false and the editor can open again.
                        editorClosed(el) {
                            if (!this.drawer_open) return;
                            if (this.isDrawerDirty()) {
                                el.showModal();
                                this.pending_drawer_close = true;
                            } else {
                                this.closeDrawer({ force: true });
                            }
                        },

                        openDeleteModal(item) {
                            if (this.isProtectedSysadmin(item)) {
                                if (window.toast) {
                                    window.toast({ type: 'error', message: 'Configured Hub sysadmin profiles cannot be deleted.', duration: 3000 });
                                }
                                return;
                            }
                            // From the open editor, confirm in its footer rather than stacking a second modal on it
                            if (this.drawer_open) {
                                this.pending_drawer_close = false;
                                this.confirming_delete = true;
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

                        canShowMore() {
                            return this.records.length < this.total_count;
                        },

                        async showMore() {
                            if (!this.canShowMore()) return;
                            this.offset = this.records.length;
                            await this.load({ append: true });
                        },

                        resultSummary() {
                            if (!this.has_loaded) return '';
                            const total = this.total_count || this.records.length;
                            if (!total) return 'No profiles';
                            if (total === 1) return '1 profile';
                            return `${total} profiles`;
                        },

                        rangeStart() {
                            return this.records.length ? 1 : 0;
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

        </cfmodule>
    </cffunction>


</cfcomponent>
