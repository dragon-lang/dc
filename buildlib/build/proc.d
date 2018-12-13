module build.proc;

import build.log;

/**
Add additional make-like assignments to the environment
e.g. ./build.d ARGS=foo -> sets the "ARGS" internal environment variable to "foo"

Params:
    args = the command-line arguments from which the assignments will be parsed
*/
void takeEnvArgs(string[]* args)
{
    import std.algorithm : canFind, splitter, filter;
    import std.range : dropOne, array;
    import std.process : environment;

    bool tryToAdd(string arg)
    {
        if (!arg.canFind("="))
            return false;

        auto sp = arg.splitter("=");
        environment[sp.front] = sp.dropOne.front;
        return true;
    }
    *args = (*args).filter!(a => !tryToAdd(a)).array;
}

auto execute(T...)(scope const(char[])[] args, T extra)
{
    import std.typecons : Tuple;
    static import std.process;

    verbosef("[EXECUTE] %s", std.process.escapeShellCommand(args));
    try
    {
        return std.process.execute(args, extra);
    }
    catch (std.process.ProcessException e)
    {
        return Tuple!(int, "status", string, "output")(-1, e.msg);
    }
}
