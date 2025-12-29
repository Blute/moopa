<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="select w-full" />
    <cfparam name="attributes.list_items" default="#[]#" />
    <cfparam name="attributes.empty_option_name" default="--- select ---" />
    <cfparam name="attributes.id" default="" />

    <cfoutput>
        <select
            class="#attributes.class#"
            x-model="#attributes.model#"
            <cfif len(attributes.id)>id="#attributes.id#"</cfif>
        >
            <cfif len(attributes.empty_option_name)>
                <option value="">#attributes.empty_option_name#</option>
            </cfif>
            <cfloop array="#attributes.list_items#" item="item">
                <option value="#item.value#">#item.name#</option>
            </cfloop>
        </select>
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
