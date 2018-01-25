# To-do list

## Rename `Procedure`

I'll probably rename the `SpaceEx.Procedure` class to `ProcedureCall`.  It would match the upstream terminology, plus I just don't think `Procedure.create` makes any sense for what it's doing.  (I originally called it `Procedure.call`, hence the `Procedure` name, but decided I didn't like that either.)

## Expression builder

It'd be nice to have some minor macros / DSL to build expressions.  They're currently fairly ugly due to the constant need for `conn` arguments.

Even just a macro to automatically insert `conn` arguments would be cool, but I think we can do better — e.g. automatically creating procedures for `call` expressions.
