<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            title: "Route Endpoint",
            title_plural: "Route Endpoints",
            order_by: "name",
            fields: {
                
                route_id: {
                  type: "uuid",
                  foreign_key_table: "moo_route",
                  foreign_key_onDelete: "CASCADE"
                },
                name: {},
            }
          }

        />

        <cfreturn this>
    </cffunction>



</cfcomponent>
