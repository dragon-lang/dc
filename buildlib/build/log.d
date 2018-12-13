module build.log;

// TODO: possibly makethe log output File configurable (not just stdout)

__gshared bool verboseBuildEnabled = false;

/**
Logs message to stdout `enableVerbose` was called.
Params:
    args = the data to write to the log
Note: marked inline so the caller doesn't have to generate arguments if verbose is disabled
*/
pragma(inline)
void verbosef(T...)(T args)
{
    import std.stdio;
    if (verboseBuildEnabled)
        writefln(args);
}

/**
Logs the message to stdout.
Params:
    args = the data to write to the log
*/
void logf(T...)(T args)
{
    import std.stdio;
    writefln(args);
}
