<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="input w-full" />
    <cfparam name="attributes.placeholder" default="" />
    <cfparam name="attributes.id" default="" />

    <cfoutput>
        <div
            x-data="control_datetime"
            x-modelable="value"
            x-model="#attributes.model#"
        >
            <input
                class="#attributes.class#"
                type="datetime-local"
                :value="formatValue()"
                @focus="$el.dataset.initial = $el.value"
                @blur="if($el.dataset.initial !== $el.value) { changeValue($el.value) }"
                placeholder="#attributes.placeholder#"
                <cfif len(attributes.id)>id="#attributes.id#"</cfif>
            >
        </div>
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
