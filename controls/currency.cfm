<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="input w-full text-right" />
    <cfparam name="attributes.placeholder" default="" />
    <cfparam name="attributes.id" default="" />
    <cfparam name="attributes.minDecimals" default="2" />
    <cfparam name="attributes.maxDecimals" default="4" />

    <cfoutput>
        <div
            x-data="control_currency({ minDecimals: #attributes.minDecimals#, maxDecimals: #attributes.maxDecimals# })"
            x-modelable="value"
            x-model="#attributes.model#"
        >
            <input
                type="text"
                inputmode="decimal"
                class="#attributes.class#"
                placeholder="#attributes.placeholder#"
                :value="formatValue()"
                @change="changeValue($event.target.value)"
                @mouseup="$el.select()"
                <cfif len(attributes.id)>id="#attributes.id#"</cfif>
            >
        </div>
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
