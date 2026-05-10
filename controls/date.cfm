<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="input w-full" />
    <cfparam name="attributes.placeholder" default="" />
    <cfparam name="attributes.id" default="" />
    <cfparam name="attributes.show_quick_options" default="true" />

    <cfoutput>
        <div
            x-data="control_date"
            x-modelable="value"
            x-model="#attributes.model#"
            class="join"
        >
            <input
                class="#attributes.class# join-item"
                type="date"
                :value="formatValue()"
                @focus="$el.dataset.initial = $el.value"
                @blur="if($el.dataset.initial !== $el.value) { changeValue($el.value) }"
                placeholder="#attributes.placeholder#"
                <cfif len(attributes.id)>id="#attributes.id#"</cfif>
            >
            <cfif attributes.show_quick_options>
                <div class="dropdown dropdown-end">
                    <button class="btn join-item" type="button" tabindex="0"><i class="fal fa-chevron-down"></i></button>
                    <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-10 w-40 p-2 shadow">
                        <li><button type="button" @click="setDate(0, 'day')">Today</button></li>
                        <li><button type="button" @click="setDate(1, 'day')">Tomorrow</button></li>
                        <li><button type="button" @click="setDate(1, 'week')">Next Week</button></li>
                        <li><button type="button" @click="setDate(1, 'month')">Next Month</button></li>
                    </ul>
                </div>
            </cfif>
        </div>
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
