<cfcomponent key="0aa8578a-1123-4130-b117-a236c0bb36cc" open_to="logged_in">

    <!---
        Edit profile: the signed-in person changes their own name and picture (profile menu > Edit profile). A
        sysadmin can edit anyone's with ?profile=<id>; anyone else asking for another profile is refused. Email,
        roles and sign-in stay with System > Profiles: email is how a person signs in.

        A project replaces this page with its own route at the same path (code/apps/<app>/routes/account/profile.cfc
        or code/shared/routes/account/profile.cfc): a project's route wins over Moopa's at the same URL.
    --->

    <cffunction name="get">
        <cfset var who = target(url.profile ?: "") />
        <cfif NOT who.allowed>
            <cfmodule template="/moopa/tags/moopa_status.cfm" code="403" route="/account/profile" />
            <cfabort>
        </cfif>
        <cfset var own = who.id EQ session.auth.profile.id />

        <cfmodule template="/moopa/tags/moopa_layout.cfm" title="#own ? 'Your profile' : 'Edit profile'#">
        <cfoutput>
            <div class="page" x-data="editProfile(#encodeForHTMLAttribute(serializeJSON(who.profile))#)">
                <div class="page-header">
                    <div>
                        <div class="eyebrow">#own ? "Your account" : encodeForHTML(who.profile.email)#</div>
                        <h1>#own ? "Your profile" : "Edit profile"#</h1>
                        <p class="page-lede">#own ? "Your name and picture, as others see them. To change your email or roles, ask an administrator." : "This person's name and picture. Their email and roles are changed in System › Profiles."#</p>
                    </div>
                    <cfif own><div class="page-actions"><a class="btn btn-sm" href="/account/signins"><i class="fa-solid fa-clock-rotate-left"></i> Sign-in activity</a></div></cfif>
                </div>

                <section class="card" style="max-width: 40rem">
                    <form class="card-body stack" @submit.prevent="save()">
                        <div class="row" style="gap: var(--sp-4)">
                            <span class="avatar avatar-lg">
                                <template x-if="picture?.thumbnail"><img :src="picture.thumbnail" alt="" /></template>
                                <template x-if="!picture?.thumbnail"><span x-text="getInitials(form.full_name)"></span></template>
                            </span>
                            <div class="cluster">
                                <label class="btn btn-sm" :aria-disabled="uploading">
                                    <i class="fa-solid" :class="uploading ? 'fa-spinner fa-spin' : 'fa-upload'"></i>
                                    <span x-text="picture?.id ? 'Replace picture' : 'Upload a picture'"></span>
                                    <input type="file" accept="image/*" hidden @change="upload($event)">
                                </label>
                                <button type="button" class="btn btn-ghost btn-sm" x-show="picture?.id" @click="picture = null">Remove</button>
                            </div>
                        </div>

                        <div class="field">
                            <label class="label" for="profile-full-name">Name</label>
                            <input id="profile-full-name" class="input" type="text" x-model="form.full_name" maxlength="255" autocomplete="name" required>
                        </div>
                        <div class="field">
                            <label class="label" for="profile-preferred-name">Preferred name <span class="muted">(optional)</span></label>
                            <input id="profile-preferred-name" class="input" type="text" x-model="form.preferred_name" maxlength="255" autocomplete="nickname">
                            <p class="help">What you'd like to be called, if not your full name.</p>
                        </div>
                        <div class="field">
                            <label class="label">Email</label>
                            <p>#encodeForHTML(who.profile.email)#</p>
                            <p class="help">#own ? "It's how you sign in, so only an administrator can change it." : "It's how they sign in: change it in System › Profiles."#</p>
                        </div>

                        <div class="cluster">
                            <button type="submit" class="btn btn-primary" :disabled="saving || uploading">
                                <i class="fa-solid" :class="saving ? 'fa-spinner fa-spin' : 'fa-check'"></i> <span x-text="saving ? 'Saving…' : 'Save'"></span>
                            </button>
                        </div>
                    </form>
                </section>
            </div>

            <script>
                function editProfile(profile) {
                    return {
                        form: { full_name: profile.full_name || '', preferred_name: profile.preferred_name || '' },
                        picture: profile.picture,
                        profile: profile.id,
                        saving: false,
                        uploading: false,
                        // The picture: the endpoint makes a file record and an upload URL, the browser PUTs the file
                        // there, then the endpoint finishes the record (its thumbnail), as System > Profiles does
                        async upload(event) {
                            const file = event.target.files?.[0];
                            event.target.value = '';
                            if (!file) return;
                            if (!file.type.startsWith('image/')) { window.toast({ type: 'error', message: 'Choose an image file.' }); return; }
                            const endpoint = 'uploadFileToServerWithProgress.profile_picture_id';
                            this.uploading = true;
                            try {
                                const started = await req({ endpoint, body: { file_name: file.name, file_size: file.size, parent_table_name: 'moo_profile', parent_field: 'profile_picture_id', parent_id: this.profile } });
                                const put = await fetch(started.presignedURL, { method: 'PUT', headers: { 'Content-Type': file.type || 'application/octet-stream' }, body: file });
                                if (!put.ok) throw new Error('The upload failed (' + put.status + ').');
                                this.picture = await req({ endpoint, body: { file_id: started.file.id, parent_id: this.profile } });
                            } catch (error) {
                                if (!String(error.message).startsWith('{')) window.toast({ type: 'error', title: 'The picture was not uploaded', description: error.message });
                            } finally {
                                this.uploading = false;
                            }
                        },
                        async save() {
                            this.saving = true;
                            try {
                                await req({ endpoint: 'save', body: { profile: this.profile, full_name: this.form.full_name, preferred_name: this.form.preferred_name, profile_picture_id: this.picture?.id || '' } });
                                window.toast({ type: 'success', message: 'Profile saved', duration: 2000 });
                                // The menu shows the name and picture: show them fresh
                                setTimeout(() => window.location.reload(), 600);
                            } finally {
                                this.saving = false;
                            }
                        }
                    };
                }
            </script>
        </cfoutput>
        </cfmodule>
    </cffunction>


    <cffunction name="uploadFileToServerWithProgress.profile_picture_id" hint="Start or finish uploading a picture for the profile being edited.">
        <cfset var who = target(request.data.parent_id ?: "") />
        <cfif NOT who.allowed>
            <cfreturn refuse("You can only change your own picture.") />
        </cfif>
        <cfset request.data.parent_id = who.id />
        <cfreturn application.lib.db.getService(table_name = "moo_file").uploadFileToServerWithProgress(data = request.data) />
    </cffunction>


    <cffunction name="save" hint="Save the name and picture of the profile being edited. Nothing else on the profile changes.">
        <cfset var who = target(request.data.profile ?: "") />
        <cfif NOT who.allowed>
            <cfreturn refuse("You can only edit your own profile.") />
        </cfif>

        <cfset var fullName = trim(request.data.full_name ?: "") />
        <cfif NOT len(fullName)>
            <cfreturn refuse("Enter a name.", 422) />
        </cfif>

        <!--- A new picture must be a file the person saving uploaded; the current one stays whoever uploaded
              it (a sysadmin, or System › Profiles); empty removes it --->
        <cfset var pictureId = trim(request.data.profile_picture_id ?: "") />
        <cfif len(pictureId) AND pictureId NEQ (who.profile.picture.id ?: "")>
            <cfquery name="local.qFile" returntype="array">
                SELECT 1 AS present
                FROM moo_file
                WHERE id = <cfqueryparam cfsqltype="other" value="#pictureId#" />
                  AND created_by = <cfqueryparam cfsqltype="other" value="#session.auth.profile.id#" />
            </cfquery>
            <cfif NOT arrayLen(local.qFile)>
                <cfreturn refuse("That picture can't be used. Upload it again.", 422) />
            </cfif>
        </cfif>

        <cfquery>
            UPDATE moo_profile
            SET full_name = <cfqueryparam cfsqltype="varchar" value="#left(fullName, 255)#" />,
                preferred_name = NULLIF(<cfqueryparam cfsqltype="varchar" value="#left(trim(request.data.preferred_name ?: ''), 255)#" />, ''),
                profile_picture_id = NULLIF(<cfqueryparam cfsqltype="varchar" value="#pictureId#" />, '')::uuid,
                last_updated_at = now(),
                last_updated_by = <cfqueryparam cfsqltype="other" value="#session.auth.profile.id#" />
            WHERE id = <cfqueryparam cfsqltype="other" value="#who.id#" />
        </cfquery>

        <!--- The menu reads the signed-in person's name from the session and caches their picture --->
        <cfif who.id EQ session.auth.profile.id>
            <cfset session.auth.profile.full_name = left(fullName, 255) />
            <cfset session.auth.profile.profile_picture_id = pictureId />
            <cfset application.lib.system.forgetAvatar() />
        </cfif>
        <cfreturn { "ok": true } />
    </cffunction>


    <!--- ===================================================================================== --->

    <cffunction name="target" access="private" returntype="struct" output="false"
        hint="The profile asked for, and whether the signed-in person may edit it: their own, or anyone's for a sysadmin.">
        <cfargument name="profileId" type="string" required="true" />

        <cfset var id = len(arguments.profileId) ? arguments.profileId : session.auth.profile.id />
        <cfset var allowed = id EQ session.auth.profile.id OR application.lib.auth.isSysAdmin() />
        <cfif NOT reFindNoCase("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id)>
            <cfreturn { id: "", allowed: false, profile: {} } />
        </cfif>
        <cfif NOT allowed>
            <cfreturn { id: id, allowed: false, profile: {} } />
        </cfif>

        <cfquery name="local.qProfile" returntype="array">
            SELECT p.id::text AS id, COALESCE(p.full_name, '') AS full_name, COALESCE(p.preferred_name, '') AS preferred_name,
                   COALESCE(p.email, '') AS email, f.id::text AS picture_id, f.thumbnail AS picture_thumbnail
            FROM moo_profile p
            LEFT JOIN moo_file f ON f.id = p.profile_picture_id
            WHERE p.id = <cfqueryparam cfsqltype="other" value="#id#" />
              AND p.app_name = <cfqueryparam cfsqltype="varchar" value="#application.app_name#" />
        </cfquery>
        <cfif NOT arrayLen(local.qProfile)>
            <cfreturn { id: id, allowed: false, profile: {} } />
        </cfif>
        <cfset var row = local.qProfile[1] />
        <cfreturn {
            id: row.id,
            allowed: true,
            profile: {
                "id": row.id,
                "full_name": row.full_name,
                "preferred_name": row.preferred_name,
                "email": row.email,
                "picture": len(row.picture_id ?: "") ? { "id": row.picture_id, "thumbnail": row.picture_thumbnail ?: "" } : {}
            }
        } />
    </cffunction>


    <cffunction name="refuse" access="private" returntype="struct" output="false" hint="A refusal: a 4xx marked X-Refusal, with the error req() shows the person.">
        <cfargument name="error" type="string" required="true" />
        <cfargument name="status" type="numeric" default="403" />
        <cfheader statuscode="#arguments.status#" />
        <cfheader name="X-Refusal" value="true" />
        <cfreturn { "error": arguments.error } />
    </cffunction>

</cfcomponent>
