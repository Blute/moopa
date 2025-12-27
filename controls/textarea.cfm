<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="textarea" />
    <cfparam name="attributes.placeholder" default="" />
    <cfparam name="attributes.rows" default="3" />
    <cfparam name="attributes.id" default="" />

    <cfoutput>
        <textarea
            class="#attributes.class#"
            rows="#attributes.rows#"
            placeholder="#attributes.placeholder#"
            x-model="#attributes.model#"
            <cfif len(attributes.id)>id="#attributes.id#"</cfif>
        ></textarea>
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
