#!/usr/bin/env rund
/**

* invoking a program

  [VAR=VALUE] [VAR=VALUE]... program arg1 arg2 ...

  each VAR=VALUE sets an environment variable to pass to `program`, but do not remain afterwards

* local variable vs environment variable

  a 'local variable' is a variable that just the shell process sees, it does not get passed to child processes.  an 'environment variable' will get propogated to all child process environments.

* referencing variables

  $var     : reference a local variable named 'var' (does not pick up environment variables)
             $var does not pick up environment variables by default because they shouldn't be
             the default.  all variables should be passed into the script explicitly by default
  How to reference environment variables? $env.var?
  Maybe support $any.var?  Access either local or environment variable named `var`?

* shell directives start with an @ symbol, that way it is easy for a developer
  to distinguish between them and normal programs

  @set message "hello"         : set `message` local variable to "hello"

  @set env.message "hello"     : set `message' environment variable to "hello"

  @require message             : require that the `message` local variable be set
  @require env.message         : require that the `message` environment variable be set

  @default message "hello"     : set `message` local variable to "hello" only if it's not already set
  @default env.message "hello" : set `message` environment variable to "hello" only if it's not already set

* You can call a dsh script like this
  ./printMessage message=hello
  OR
  dsh printMessage message=hello

* Need a way to get environment variables from sub processes/shells
  I don't think there's a way to execute a program and take environment variables from it?
  This is because when you start the program via fork/exec the kernel sets up the process
  with it's own copy of the environment and there's no general way to get it that I know of.


*/
import core.stdc.stdlib : exit;
import std.array;
import std.string;
import std.stdio;
import std.process;

//__gshared bool debugOut = false;
__gshared bool debugOut = true;
__gshared string[string] vars;

void usage()
{
    writeln("Usage: dsh [<file>]");
}
int main(string[] args)
{
    args = args[1 .. $];
    {
        size_t newArgsLength = 0;
        scope (exit) args.length = newArgsLength;
        for (size_t i = 0; i < args.length; i++)
        {
            auto arg = args[i];
            if (!arg.startsWith('-'))
            {
                args[newArgsLength++] = arg;
            }
            else if (arg == "-h" || arg == "--help")
            {
                usage();
                return 1;
            }
            else
            {
                writefln("Error: unknown command-line option '%s'", arg);
                return 1;
            }
        }
    }

    File input;
    if (args.length == 0)
    {
        input = stdin;
    }
    else if (args.length == 1)
    {
        input = File(args[0], "r");
    }
    else
    {
        writefln("Error: expected 0 or 1 command-line argument but got %s", args.length);
        return 1;
    }

    auto argsBuilder = appender!(char[][])();
    foreach (line; input.byLine)
    {
        line = line.strip();
        //writeln(line);
        argsBuilder.clear();
        for (;;)
        {
            if (line.length == 0 || line[0] == '#')
                break;
            auto next = peel(line);
            if (next is null)
                break;
            argsBuilder.put(resolveVars(next));
            line = line[ (next.ptr - line.ptr) + next.length .. $];
        }
        if (argsBuilder.data.length == 1)
        {
            auto arg = argsBuilder.data[0];
            auto equalsIndex = arg.indexOf('=');
            if (equalsIndex >= 0)
            {
                auto varName = arg[0 .. equalsIndex].idup;
                auto value = arg[equalsIndex + 1 .. $].idup;
                if (debugOut)
                    writefln("[DSHELL] '%s' = '%s'", varName, value);
                environment[varName] = value;
                continue;
            }
        }
        if (argsBuilder.data.length > 0)
        {
            execute(argsBuilder.data);
        }
    }

    return 0;
}

void appendVar(T)(T builder, const(char)[] varName)
{
    auto result = environment.get(varName, null);
    if (result is null)
    {
        // TODO: in a certain mode, this should probably cause an error
    }
    else
    {
        builder.put(result);
    }
}

bool validFirstCharOfVarName(char c)
{
    if (c < 'A')
        return false;
    if (c <= 'Z')
        return true;
    if (c < 'a')
        return c == '_';
    return c <= 'z';
}
bool validCharOfVarName(char c)
{
    if (c < '0')
        return false;
    if (c <= '9')
        return true;
    return validFirstCharOfVarName(c);
}

inout(char)[] resolveVars(inout(char)[] s)
{
    size_t i = 0;
    for (;; i++)
    {
        if (i >= s.length)
            return s;
        if (s[i] == '$')
            break;
    }
    size_t save = 0;
    auto resolved = appender!(char[])();
  LdollarLoop:
    for (;;)
    {
        // i points to character after '$'
        resolved.put(s[save .. i]);
        i++;
        if (i >= s.length)
        {
            writefln("[DSHELL] Error: string ended with '$' character");
            exit(1);
        }
        if (s[i] == '{')
        {
            i++;
            if (i >= s.length)
            {
                writefln("[DSHELL] Error: string ended with '${'");
                exit(1);
            }
            const varNameStart = i;
            for (;;)
            {
                i++;
                if (i >= s.length)
                {
                    writefln("[DSHELL] Error: unterminated '${...' sequence");
                    exit(1);
                }
                if (s[i] == '}')
                    break;
            }
            auto varName = s[varNameStart .. i];
            if (varName.length == 0)
            {
                writefln("[DSHELL] Error: empty '${}' variable");
                exit(1);
            }
            appendVar(resolved, varName);
            i++;
        }
        else if (s[i] == '$')
        {
            resolved.put("$");
            i++;
        }
        else
        {
            if (!validFirstCharOfVarName(s[i]))
            {
                writefln("[DSHELL] Error: expected '{', '$', 'A-Z', 'a-z' or '_' after '$' but got '%c' (0x%x)",
                    s[i], cast(ubyte)s[i]);
                exit(1);
            }
            const varNameStart = i;
            for (;;)
            {
                i++;
                if (i >= s.length || !validCharOfVarName(s[i]))
                    break;
            }
            appendVar(resolved, s[varNameStart .. i]);
        }
        save = i;
        for (;; i++)
        {
            if (i >= s.length)
                break LdollarLoop;
            if (s[i] == '$')
                break;
        }
    }
    resolved.put(s[save .. i]);
    if (debugOut)
        writefln("[DSHELL] '%s' => '%s'", s, resolved.data);
    return cast(inout(char)[])resolved.data;
}

bool isspace(char c)
{
    return c == ' ' || c == '\t';
}

inout(char)[] peel(inout(char)[] str)
{
    size_t next = 0;
    for (;; next++)
    {
        if (next >= str.length)
            return null;
        if (!isspace(str[next]))
            break;
    }
    if (str[next] == '"')
    {
        assert(0, "quoted not impl");
    }
    auto start = next;
    for (;;)
    {
        next++;
        if (next >= str.length || isspace(str[next]))
            return str[start .. next];
    }
}

void execute(char[][] args)
{
    if (debugOut)
    {
        writefln("+ %s", escapeShellCommand(args));
    }
    auto proc = spawnProcess(args);
    auto exitCode = wait(proc);
    if (exitCode != 0)
    {
        writefln("Error: last command exited with code %s", exitCode);
        exit(exitCode);
    }
}
