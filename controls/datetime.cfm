<cfif thisTag.executionMode EQ "start">

    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="input" />
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

        <cf_once id="control_datetime_script" position="body">
            <script defer>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("control_datetime", () => ({
                        value: '',

                        formatValue() {
                            if (!this.value) return '';
                            // Handle ISO datetime format, return YYYY-MM-DDTHH:MM for datetime-local input
                            if (typeof this.value === 'string' && this.value.match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/)) {
                                return this.value.substring(0, 16);
                            }
                            const date = new Date(this.value);
                            if (isNaN(date.getTime())) return '';
                            const year = date.getFullYear();
                            const month = String(date.getMonth() + 1).padStart(2, '0');
                            const day = String(date.getDate()).padStart(2, '0');
                            const hours = String(date.getHours()).padStart(2, '0');
                            const minutes = String(date.getMinutes()).padStart(2, '0');
                            return `${year}-${month}-${day}T${hours}:${minutes}`;
                        },

                        changeValue(inputValue) {
                            if (!inputValue) {
                                this.value = '';
                                return;
                            }
                            // Validate YYYY-MM-DDTHH:MM format
                            if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(inputValue)) {
                                this.value = '';
                                return;
                            }
                            // Store as ISO string
                            const [datePart, timePart] = inputValue.split('T');
                            const [year, month, day] = datePart.split('-').map(Number);
                            const [hours, minutes] = timePart.split(':').map(Number);
                            const date = new Date(year, month - 1, day, hours, minutes);
                            this.value = date.toISOString();
                        }
                    }));
                });
            </script>
        </cf_once>
    </cfoutput>

<cfelseif thisTag.executionMode EQ "end">
    <!--- not required --->
</cfif>
