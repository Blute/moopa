<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.id" default="#createUniqueID()#" />
    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="input w-full" />
    <cfparam name="attributes.placeholder" default="" />
    <cfparam name="attributes.required" type="boolean" default="false" />

    <cfoutput>
        <input id="#attributes.id#"
            type="text"
            class="#attributes.class#"
            placeholder="#attributes.placeholder#"
            x-model="#attributes.model#"
            <cfif attributes.required>aria-required="true"</cfif>
        >
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
