<cfcomponent key="5a9b1c1e-6a54-4d1e-9a3f-6b9d6b2d2f13" open_to="logged_in">

    <cffunction name="ensureSessionFilters" access="private" returntype="void" output="false">
        <cfif !structKeyExists(session, 'auth') OR !isStruct(session.auth)>
            <cfset session.auth = {} />
        </cfif>
        <cfif !structKeyExists(session.auth, 'filters') OR !isStruct(session.auth.filters)>
            <cfset session.auth.filters = {} />
        </cfif>
    </cffunction>


	<cffunction name="get">
		<!--- Return saved filters for the given route (URL path) --->
		<cfparam name="url.for_route" default="" />

		<cfset for_route = url.for_route ?: '' />
        <cfset ensureSessionFilters() />

		<cfif !len(for_route)>
			<cfreturn {} />
		</cfif>

		<cfif structKeyExists(session.auth.filters, for_route) AND isStruct(session.auth.filters[for_route])>
			<cfreturn session.auth.filters[for_route] />
		</cfif>

		<cfreturn {} />
	</cffunction>


	<cffunction name="save">
		<!--- Save filters for the given route (URL path) --->
		<cfparam name="request.data.for_route" />
		<cfparam name="request.data.filters" default={} />

        <cfset ensureSessionFilters() />

		<cfif !isStruct(request.data.filters)>
			<cfthrow type="moopa.sessionFilters.invalidFilters" message="Session filters must be submitted as an object." />
		</cfif>

		<cfset session.auth.filters[ request.data.for_route ] = request.data.filters />

		<cfreturn { success: true } />
	</cffunction>


	<cffunction name="clear">
		<!--- Clear filters for the given route; if none provided, clear all --->
		<cfparam name="request.data.for_route" default="" />

        <cfset ensureSessionFilters() />

		<cfif len(request.data.for_route)>
			<cfif structKeyExists(session.auth.filters, request.data.for_route)>
				<cfset structDelete(session.auth.filters, request.data.for_route) />
			</cfif>
		<cfelse>
			<cfset session.auth.filters = {} />
		</cfif>

		<cfreturn { success: true } />
	</cffunction>

</cfcomponent>
