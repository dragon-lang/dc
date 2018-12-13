module build.deps;

__gshared bool forceBuildEnabled = false;

/**
Determines if a target is up to date with respect to its source files

Params:
    target = the target to check
    source = the source file to check against
Returns: `true` if the target is up to date
*/
auto isUpToDate(string target, string source)
{
    return isUpToDate(target, [source]);
}

/**
Determines if a target is up to date with respect to its source files

Params:
    target = the target to check
    source = the source files to check against
Returns: `true` if the target is up to date
*/
auto isUpToDate(string target, string[][] sources...)
{
    return isUpToDate([target], sources);
}

/**
Checks whether any of the targets are older than the sources

Params:
    targets = the targets to check
    sources = the source files to check against
Returns:
    `true` if the target is up to date
*/
auto isUpToDate(string[] targets, string[][] sources...)
{
    import std.range : front;
    import std.string : empty;
    import std.exception : ifThrown;
    import std.datetime : SysTime, seconds;
    import std.file : timeLastModified;

    if (forceBuildEnabled)
        return false;

    foreach (target; targets)
    {
        auto sourceTime = target.timeLastModified.ifThrown(SysTime.init);
        // if a target has no sources, it only needs to be built once
        if (sources.empty || sources.length == 1 && sources.front.empty)
            return sourceTime > SysTime.init;
        foreach (arg; sources)
            foreach (a; arg)
                if (sourceTime < a.timeLastModified.ifThrown(SysTime.init + 1.seconds))
                    return false;
    }

    return true;
}

/**
A `Ruld` has one or more sources that yield one or more targets.
It knows how to build these target by invoking either the external command or
the commandFunction.

If a run fails, the entire build stops.

Command strings support the Make-like $@ (target path) and $< (source path)
shortcut variables.
*/
struct BuildRule
{
    string[] targets; /// list of all target files
    string[] sources; /// list of all source files
    //string[] rebuildSources; /// Optional list of files that trigger a rebuild of this dependency
    //string[] command; /// the dependency command
    void delegate(BuildRule* rule) func; /// a custom dependency command which gets called instead of command
    //string name; /// name of the dependency that is e.g. written to the CLI when it's executed
    string[] trackSources;

    /**
    Executes the dependency
    */
    auto run()
    {
        // allow one or multiple targets
        if (target !is null)
            targets = [target];

        if (targets.isUpToDate(sources, rebuildSources))
        {
            if (sources !is null)
                log("Skipping build of %-(%s%) as it's newer than %-(%s%)", targets, sources);
            return;
        }

        if (commandFunction !is null)
            return commandFunction();

        resolveShorthands();

        // Display the execution of the dependency
        if (name)
            name.writeln;

        command.runCanThrow;
    }

    /**
    Resolves variables shorthands like $@ (target) and $< (source)
    */
    void resolveShorthands()
    {
        // Support $@ (shortcut for the target path)
        foreach (i, c; command)
            command[i] = c.replace("$@", target);

        // Support $< (shortcut for the source path)
        if (command[$ - 1].find("$<"))
            command = command.remove(command.length - 1) ~ sources;
    }
}

