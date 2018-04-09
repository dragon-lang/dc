module dmd.env;

import core.stdc.string;
import core.sys.posix.stdlib;
import dmd.globals;
import dmd.root.array;
import dmd.root.rmem;

version (Windows) extern (C) static int putenv(const char*);

/**
Used to store an environment variable including its value.
*/
struct Env
{
    private const(char)* setString; /// null-terminated string of the form "VAR=VALUE"
    private uint length;            /// length of setString
    private uint equalsIndex;       /// index of '=' in setString

    /**
    Access the name of the environment variable as a D string.
    */
    auto nameString() const { return setString[0 .. equalsIndex]; }

    /**
    Access the value of the environment variable as a D string.
    */
    auto valueString() const { return setString[equalsIndex + 1 .. length]; }

    /**
    Put this environment variable in the current environment by calling `putenv`.
    Note that this call gives ownership of the memory allocated for this variable
    to the system, it must remain intact even after this call has returned. Also
    note that this function does not cache the current value of the variable to be
    restored laster like `global.putenvWithCache` would do.
    Returns:
        true on succes, false otherwise
    */
    private bool putenv() const
    {
        if (.putenv(cast(char*)setString) == 0)
            return true; // success
        else
            return false; // fail
    }

    /**
    Get current value of this environment variable from the system by calling `getenv`.
    Returns:
        the return value of `getenv`
    */
    private char* getenv() const
    {
        auto nameBuffer = cast(char*)alloca(equalsIndex + 1);
        nameBuffer[0 .. equalsIndex] = setString[0 .. equalsIndex];
        nameBuffer[equalsIndex] = '\0';
        return .getenv(nameBuffer);
    }

    /**
    Save the environment variable so that it can be restored later.
    */
    private void saveEnvForRun()
    {
        if (global.params.doneParsingCommandLine && !global.params.run)
            return; // no need to save command line

        auto nameString = nameString;
        foreach (var; envToRestoreBeforeRun)
        {
            if (var.nameString == nameString)
            {
                //printf("saveEnvForRun already saved %s\n", setString);
                return; // already saved
            }
        }

        auto value = getenv();
        auto newEnv = alloc(nameString, value ? value[0 .. strlen(value)] : null);
        //printf("saveEnvForRun %s\n", newEnv.setString);
        envToRestoreBeforeRun.push(newEnv);
    }

    /**
    Set this environment variable but save the overwritten value so it can be restored
    later if necessary.
    Returns:
        true on success, false on failure
    */
    bool putenvRestorable()
    {
        saveEnvForRun();
        return putenv();
    }

    /**
    Environment variables to restore before executing the compiled program because
    of `-run`.
    */
    private static __gshared Array!Env envToRestoreBeforeRun;

    /**
    Allocate and initialize a new environment variable that can be set to the current environment.
    Params:
        name = name of the environment variable
        value = value of the environment variable
    Returns:
        a newly allocated environment variable
    */
    static Env alloc(const(char)[] name, const(char)[] value)
    {
        uint length = cast(uint)name.length + 1 + cast(uint)value.length;
        auto setString = cast(char*)mem.xmalloc(length + 1);
        setString[0 .. name.length] = name[];
        setString[name.length] = '=';
        setString[name.length + 1 .. length] = value[];
        setString[length] = '\0';
        return Env(setString, length, cast(uint)name.length);
    }

    /**
    Restore environment before running the compiled program.
    */
    static void restoreBeforeRun()
    {
        foreach (var; envToRestoreBeforeRun)
        {
            //printf("restoreEnvBeforeRun %s\n", var.setString);
            if (!var.putenv())
                assert(0, "putenv failed");
        }
    }
}

