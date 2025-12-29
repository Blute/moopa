<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="input w-full" />
    <cfparam name="attributes.placeholder" default="" />
    <cfparam name="attributes.id" default="" />

    <cfoutput>
        <input
            type="tel"
            class="#attributes.class#"
            placeholder="#attributes.placeholder#"
            x-model="#attributes.model#"
            <cfif len(attributes.id)>id="#attributes.id#"</cfif>
        >
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
