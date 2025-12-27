<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="input text-right" />
    <cfparam name="attributes.placeholder" default="" />
    <cfparam name="attributes.id" default="" />

    <cfoutput>
        <div
            x-data="control_percentage"
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

        <cf_once id="control_percentage_script" position="body">
            <script defer>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("control_percentage", () => ({
                        value: 0,

                        formatValue() {
                            if (this.value === null || this.value === undefined || this.value === '') return '';
                            // Convert from decimal storage (0.1) to percentage display (10%)
                            return (parseFloat(this.value) * 100).toFixed(2) + '%';
                        },

                        changeValue(inputValue) {
                            if (!inputValue) {
                                this.value = 0;
                                return;
                            }
                            // Convert from percentage input (10%) to decimal storage (0.1)
                            const sanitized = inputValue.replace(/[^0-9.\-]/g, '');
                            const parsed = parseFloat(sanitized);
                            this.value = isNaN(parsed) ? 0 : parsed / 100;
                        }
                    }));
                });
            </script>
        </cf_once>
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
