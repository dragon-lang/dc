module build.error;

/**
Used to exit the program via the exception unwind path but indicates
the error has already been reported.
*/
class SilentException : Exception { this() { super("error already reported"); } }

/**
Call `throw fatal("got error %s", error);` to print an error and exit the program.

Note: returns an exception instead of throwing one so the caller code
      knows that an exception is being thrown (helps callers code path analysis).
*/
SilentException fatal(T...)(T args)
{
    import std.stdio : writefln;
    writefln(args);
    return new SilentException();
}