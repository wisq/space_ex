# To-do list

## Expression builder

It'd be nice to have some minor macros / DSL to build expressions.  They're currently fairly ugly due to the constant need for `conn` arguments.

Even just a macro to automatically insert `conn` arguments would be cool, but I think we can do better — e.g. automatically creating procedures for `call` expressions.
