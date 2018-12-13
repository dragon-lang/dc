module stepbuild;
/*
Instead of targets/dependencies and actions, what about just actions?

On the initial build, just execute all the actions and track the files they use and create to know when a rebuild is required.

So for this command:

dmd hello.d

We could track that it read hello.d, and many other files like the compiler, libraries, etc. It should also consider the file that contains the command itself as a dependency of this operation.

It should also track all the output files. It will see that 'hello' was created.

It should also save the environment variables that were passed to it. Note that it should mask the environmnet variables that we know it uses so that changes to other environment variables dont cause a rebuild.

Env: PATH DFLAGS
Input: dc default=dmd
Step: $dc hello.d

The script can also declare input parameters. Like environment variables, these parameters should be considered as inputs.

Each step is hashed after all is variables are resolved and that hash is used as the input to know whether it's already built.


Step Sequence:

  a sequence of steps that must be executed in order one after the other.
  the next step cannot be executed until the previous succeeds.

Step Group:

    


*/

class Step
{
    string name;
    this(string name) { this.name = name; }
}

// A single command to run
class Command : Step
{
    string[] command;
    this(string name, string[] command)
    {
        super(name);
        this.command = command;
    }
}
// Each step must be executed in order and all previous steps must finish successfully before the next.
class StepSequence : Step
{
    Step[] steps;
    this(string name, Step[] steps)
    {
        super(name);
        this.steps = steps;
    }
}
// A group of steps that can all be run in parallel
class StepGroup : Step
{
    Step[] steps;
    this(string name, Step[] steps)
    {
        super(name);
        this.steps = steps;
    }
}

struct Config
{
    string[] envAllowed;
    Step[] steps;
}

void verbosef(T...)(T args)
{
    import std.stdio;
    write("[VERBOSE] ");
    writefln(args);
}
void logf(T...)(T args)
{
    import std.stdio;
    writefln(args);
}

void filterEnv(string[] allowed)
{
    import std.algorithm : canFind;
    import std.process : environment;

    auto envCopy = environment.toAA();
    foreach (pair; envCopy.byKeyValue)
    {
        if (!allowed.canFind(pair.key))
        {
            environment.remove(pair.key);
            verbosef("Removed Env '%s'", pair.key);
        }
        else
        {
            verbosef("Allowed Env '%s'", pair.key);
        }
    }
}
void dumpEnv()
{
    import std.process : environment;

    logf("--------------------------------------------------------------------------------");
    foreach (env; environment.toAA.byKeyValue)
    {
        logf("%s=%s", env.key, env.value);
    }
    logf("--------------------------------------------------------------------------------");
}

