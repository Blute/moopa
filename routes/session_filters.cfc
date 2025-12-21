<cfcomponent key="5a9b1c1e-6a54-4d1e-9a3f-6b9d6b2d2f13" open_to="logged_in">

	<cffunction name="get">
		<!--- Return saved filters for the given route (URL path) --->
		<cfparam name="url.for_route" default="" />

		<cfset for_route = url.for_route ?: '' />

		<cfif !structKeyExists(session, 'auth')>
			<cfset session.auth = {} />
		</cfif>
		<cfif !structKeyExists(session.auth, 'filters')>
			<cfset session.auth.filters = {} />
		</cfif>

		<cfif !len(for_route)>
			<cfreturn {} />
		</cfif>

		<cfif structKeyExists(session.auth.filters, for_route)>
			<cfreturn session.auth.filters[for_route] />
		</cfif>

		<cfreturn {} />
	</cffunction>


	<cffunction name="save">
		<!--- Save filters for the given route (URL path) --->
		<cfparam name="request.data.for_route" />
		<cfparam name="request.data.filters" default={} />

		<cfif !structKeyExists(session, 'auth')>
			<cfset session.auth = {} />
		</cfif>
		<cfif !structKeyExists(session.auth, 'filters')>
			<cfset session.auth.filters = {} />
		</cfif>

		<cfset session.auth.filters[ request.data.for_route ] = request.data.filters />

		<cfreturn { success: true } />
	</cffunction>


	<cffunction name="clear">
		<!--- Clear filters for the given route; if none provided, clear all --->
		<cfparam name="request.data.for_route" default="" />

		<cfif structKeyExists(session, 'auth') AND structKeyExists(session.auth, 'filters')>
			<cfif len(request.data.for_route)>
				<cfif structKeyExists(session.auth.filters, request.data.for_route)>
					<cfset structDelete(session.auth.filters, request.data.for_route) />
				</cfif>
			<cfelse>
				<cfset session.auth.filters = {} />
			</cfif>
		</cfif>

		<cfreturn { success: true } />
	</cffunction>

</cfcomponent>
