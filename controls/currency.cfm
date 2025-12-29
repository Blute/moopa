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

        <cf_once id="control_currency_script" position="body">
            <script defer>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("control_currency", (config) => ({
                        value: 0,
                        minDecimals: config.minDecimals || 2,
                        maxDecimals: config.maxDecimals || 4,

                        formatValue() {
                            return new Intl.NumberFormat('en-US', {
                                style: 'currency',
                                currency: 'USD',
                                minimumFractionDigits: this.minDecimals,
                                maximumFractionDigits: this.maxDecimals
                            }).format(this.value || 0);
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
