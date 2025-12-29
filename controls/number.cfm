<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="input w-full text-right" />
    <cfparam name="attributes.placeholder" default="" />
    <cfparam name="attributes.id" default="" />

    <cfoutput>
        <div
            x-data="control_number"
            x-modelable="value"
            x-model="#attributes.model#"
        >
            <input
                type="text"
                inputmode="numeric"
                class="#attributes.class#"
                placeholder="#attributes.placeholder#"
                :value="formatValue()"
                @change="changeValue($event.target.value)"
                @mouseup="$el.select()"
                <cfif len(attributes.id)>id="#attributes.id#"</cfif>
            >
        </div>

        <cf_once id="control_number_script" position="body">
            <script defer>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("control_number", () => ({
                        value: 0,

                        formatValue() {
                            if (this.value === null || this.value === undefined || this.value === '') return '';
                            return new Intl.NumberFormat('en-US', {
                                minimumFractionDigits: 0,
                                maximumFractionDigits: 6
                            }).format(this.value);
                        },

                        changeValue(inputValue) {
                            if (!inputValue) {
                                this.value = 0;
                                return;
                            }
                            const sanitized = inputValue.replace(/[^0-9.\-]/g, '');
                            const parsed = parseFloat(sanitized);
                            this.value = isNaN(parsed) ? 0 : Math.round(parsed * 10000) / 10000;
                        }
                    }));
                });
            </script>
        </cf_once>
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
