<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="checkbox" />
    <cfparam name="attributes.id" default="" />

    <cfoutput>
        <input
            type="checkbox"
            class="#attributes.class#"
            x-model="#attributes.model#"
            <cfif len(attributes.id)>id="#attributes.id#"</cfif>
        >
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
