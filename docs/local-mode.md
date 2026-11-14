# Local mode

Moopa runs in **modern local mode**: a variable a function assigns without a scope belongs to that call, exactly as if it were declared with `var`.

```cfml
<cffunction name="total">
    <cfset sum = 0 />                                      <!--- local to this call --->
    <cfloop array="#arguments.items#" item="entry">        <!--- so is entry --->
        <cfset sum += entry.amount />
    </cfloop>
    <cfquery name="qRates">…</cfquery>                      <!--- and qRates --->
    <cfreturn sum />
</cffunction>
```

`moopa.application` sets it (`this.localMode = "modern"`), so every project has it by extending that component. A project's `Application.cfc` must not set `this.localMode`.

## Why

Moopa's libraries (`application.lib`), table services and routing objects are single instances that every request shares. In classic local mode, the engine's default, an unscoped assignment inside a component's function goes to that component's `variables` scope. On a shared instance, two requests running the same function at the same time then write the same variable, and one reads the other's value: a loop over the wrong record's fields, a query result from another request.

In modern mode no unscoped assignment can do that. State a component means to keep is written with its scope, `variables.name` or `this.name`, and for a shared instance that happens in `init()` only.

## The app refuses to start without it

`OnApplicationStart` checks what the engine does, not what was configured: it runs a function that assigns a variable without a scope, and looks for that variable in the component's `variables` scope. Finding it there throws `moopa.config.classicLocalMode`, and the app does not start. Each request tries again, so it starts once the cause is gone:

- the project's `Application.cfc` sets `this.localMode` to something else: remove it;
- the engine does not support `this.localMode`.

`scripts/test_local_mode.sh` runs the check in both modes.

## Writing code

- `var` and `local.` still work and mean the same thing. Neither is needed to keep a variable out of the shared scope.
- To change an argument, write `arguments.name`. A bare `name = …` makes a new local and leaves `arguments.name` as it was.
- A function-local variable is not visible to another function. Pass it, or keep it in `variables` deliberately (not on a shared instance, outside `init()`).
- Code outside any function (a page, a custom tag, a component's pseudo-constructor) has no local scope, and is unchanged.

## Upgrading

Before this, Moopa did not set the mode, so an app ran in the engine's default: classic. Moving to this version changes how the project's own components behave as well as Moopa's.

Check the project's functions for a variable that one function assigns without a scope and another function (or the same one, on a later call) reads. That worked in classic mode by way of the shared `variables` scope; in modern mode the second read fails with an undefined variable. Write the assignment as `variables.name` if the sharing is meant, or pass the value. Then remove any `this.localMode` from the project's `Application.cfc`.
