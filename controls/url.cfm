<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.id" default="#createUniqueID()#" />
    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="input w-full" />
    <cfparam name="attributes.placeholder" default="" />

    <cfoutput>
        <input id="#attributes.id#"
            type="url"
            class="#attributes.class#"
            placeholder="#attributes.placeholder#"
            x-model="#attributes.model#"
        >
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
