#!/usr/bin/env rund
//!debug
//!debugSymbols
/**
TODO:
- add all posix.mak Makefile targets
- test on OSX
- allow appending DFLAGS via the environment
- test the script with LDC or GDC as host compiler
- implement testbuild target for testing each rule in "isolation"
- rebuild if we use new settings
  we could hash all the settings and include this in the generated directory
*/
version (CoreDdoc) {} else:

version (HaveLibraries) {} else
{
    //
    // This code bootstraps the build by making sure we have all the build libraries
    //
    import core.stdc.errno;
    import std.string, std.range, std.algorithm, std.path, std.file, std.stdio, std.process;
    auto relpath(string path) { return buildNormalizedPath(__FILE_FULL_PATH__.dirName, path); }
    int main(string[] args)
    {
        string requiredVersion = "0.0";
        // TODO: check for buildlib_$MAJOR, which should be a link to the latest
        //       buildlib of that major version
        //       then check if the minor version is new enough, if not, clone
        //       the required version and update the major version link to the newly cloned repo
        auto buildlib = relpath("../../buildlib");
        if (!exists(buildlib))
        {
            writefln("Error: buildlib repository '%s' does not exist, please clone it", buildlib);
            return 1;
        }
        auto newArgs = ["rund", "-version=HaveLibraries", "-I=" ~ buildlib,
            relpath("build2.d")] ~ args[1 .. $];
        writefln("%s", escapeShellCommand(newArgs));
        version (Windows)
        {
            // Windows doesn't have exec, fall back to spawnProcess then wait
            // NOTE: I think windows may have a way to do exec, look into this more
            auto pid = spawnProcess(newArgs);
            return pid.wait();
        }
        else
        {
            auto newArgv = newArgs.map!toStringz.chain(null.only).array;
            execvp(newArgv[0], newArgv.ptr);
            // should never return
            writefln("Error: execv of '%s' failed (e=%s)", newArgs[0], errno);
            return 1;
        }
    }
}

version (HaveLibraries):

// TODO: maybe make this a runtime configurable option?
//version = SeparateBackendObjects;

import std.meta, std.typecons, std.functional, std.algorithm, std.conv, std.datetime, std.exception, std.file, std.format,
       std.getopt, std.parallelism, std.path, std.process, std.range, std.stdio, std.string;
import core.stdc.stdlib : exit;

import build.log;
import build.error : fatal, SilentException;
import build.filenames : objName, libName, exeName, objExt;
import build.path : shortPath;
import build.proc : which;
import build.make;
import build.cxx;

struct Global
{
    static __gshared string srcDir;
    static __gshared string repoDir;
    static __gshared string genDir;
    static __gshared string resourceDir;
    static __gshared string dmdDir;
    static __gshared string backendDir;
    static __gshared string tkDir;
    static __gshared string rootDir;
    static __gshared string examplesDir;
}

struct EnvVar
{
    string name;
    string description;
    string default_;
}
enum envVars = AliasSeq!(
    EnvVar("GENERATEDIR", "Output file location"),
    EnvVar("SYSCONFDIR", "???", "/etc"),
    //
    // Tools
    //
    EnvVar("DCOMPILER", "The D compiler to use"),
    EnvVar("CXX", "The C++ compiler"),
    EnvVar("CXX_KIND", "The 'kind' of C++ compiler (i.e. gnu, clang, dmc)"),
    EnvVar("AR", "The library archiver"),
    EnvVar("BUILD", "release or debug (default is release)"),
    EnvVar("TARGET_CPU", "The target CPU"),
    EnvVar("TARGET_OS", "The target OS"),
    EnvVar("MODEL", "The target architecture, 32 or 64.  Defaults to host architecture."),
    //
    // Options
    //
    EnvVar("ENABLE_WARNINGS", "Enable C++ build warnings"),
    EnvVar("ENABLE_OPTIMIZATION", "Enable compiler optimizations"),
    EnvVar("ENABLE_PROFILING", "Build dmd with a profiling recorder"),
    EnvVar("ENABLE_PGO_GENERATE", "??"),
    EnvVar("ENABLE_PGO_USE", "Build dmd with existing profiling information"),
    EnvVar("PGO_DIR", "Directory for profile-guided optimization"),
    EnvVar("ENABLE_LTO", "Enable link-time optimization"),
    EnvVar("ENABLE_UNITTEST", "Build dmd with unittests"),
    EnvVar("ENABLE_COVERAGE", "Build dmd with coverage counting"),
    EnvVar("ENABLE_SANITIZERS", "Build dmd with sanitizer"),
    EnvVar("ENABLE_PIC", "Compiler with PIC (Position-Independent Code)"),
);

struct Env
{
    static foreach (var; envVars)
    {
        mixin("static __gshared string " ~ var.name ~ ";");
    }
}

bool envEnabled(string member)()
{
    if (!__traits(getMember, Env, member))
        return false;
    if (__traits(getMember, Env, member) != "1")
        throw fatal("Environment Variable '%s' must either be '1' or unset, but is '%s",
            member, __traits(getMember, Env, member));
    return true;
}

alias getHostOS = memoize!determineHostOS;
alias getHostArch = memoize!determineHostArch;

alias getTargetOS = memoize!determineTargetOS;
alias getUserSpecifiedTargetArch = memoize!determineUserSpecifiedTargetArch;
alias getFinalTargetArch = memoize!determineFinalTargetArch;

alias getBuildType = memoize!determineBuildType;

alias getDCompiler = memoize!findDCompiler;
alias getCxxCompiler = memoize!findAndVerifyCxxCompiler;
alias getLibArchiver = memoize!determineLibArchiver;
alias getCxxArgs = memoize!setupCxxArgs;
alias getDFlags = memoize!setupDFlags;

string determineHostOS()
{
    version(Windows)
        return "windows";
    else version(OSX)
        return "osx";
    else version(linux)
        return "linux";
    else version(FreeBSD)
        return "freebsd";
    else version(OpenBSD)
        return "openbsd";
    else version(NetBSD)
        return "netbsd";
    else version(DragonFlyBSD)
        return "dragonflybsd";
    else version(Solaris)
        return "solaris";
    else
        static assert(0, "Unabled to determine a target OS");
}

Arch archFromUname(string uname)
{
    if (!uname.find("x86_64", "amd64", "64-bit")[0].empty)
        return Arch.x86_64;
    if (!uname.find("i386", "i586", "i686", "32-bit")[0].empty)
        return Arch.x86;
    throw fatal("Cannot determine architecture from uname '%s'", uname);
}
Arch determineHostArch()
{
    auto hostOS = getHostOS;
    string uname;
    if (hostOS == "solaris")
        return ["isainfo", "-n"].execute.output.archFromUname;
    else if (hostOS == "windows" || hostOS == "Windows_NT")
        return ["wmic", "OS", "get", "OSArchitecture"].execute.output.archFromUname;
    else
        return ["uname", "-m"].execute.output.archFromUname;
}
string determineTargetOS()
{
    return Env.TARGET_OS ? Env.TARGET_OS : getHostOS;
}

Nullable!Arch determineUserSpecifiedTargetArch()
{
    if (Env.MODEL)
    {
        if (Env.TARGET_CPU)
            throw fatal("Cannot specify both MODEL and TARGET_CPU together");

        if (Env.MODEL == "32")
            return Arch.x86.nullable;
        if (Env.MODEL == "64")
            return Arch.x86_64.nullable;
        throw fatal("Unknown MODEL '%s', expected '32' or '64'", Env.MODEL);
    }
    if (Env.TARGET_CPU)
    {
        throw fatal("TARGET_CPU environment variable not impl");
    }
    return Nullable!Arch.init;
}
Arch determineFinalTargetArch()
{
    auto userSpecifiedArch = getUserSpecifiedTargetArch();
    if (!userSpecifiedArch.isNull)
        return userSpecifiedArch.get;

    return getCxxCompiler().getDefaultTargetArch();
}

enum BuildType { release, debug_ }
string toString(const BuildType type)
{
    final switch (type)
    {
    case BuildType.debug_: return "debug";
    case BuildType.release: return "release";
    }
}
BuildType determineBuildType()
{
    if (Env.BUILD)
    {
        if (Env.BUILD == "debug")
            return BuildType.debug_;
        if (Env.BUILD == "release")
            return BuildType.release;
        throw fatal("BUILD should be 'debug' or 'release' but got '%s'", Env.BUILD);
    }
    return BuildType.release;
}

private CxxKind determineCxxKind(string program)
{
    version (Windows)
    {
       assert(0, "determineCxxKind not fully implemented");
    }
    else
    {
        import std.range : empty;
        import std.algorithm : find;
        import build.log : errorf, logf;
        import build.proc : tryExecute;

        auto cxxVersion = tryExecute([program, "--version"]).output;
        if (!cxxVersion.find("gcc", "Free Software")[0].empty)
            return CxxKind.gnu;
        errorf("Cannot determine compiler kind from version output:");
        logf(cxxVersion);
        throw fatal("unknown cxx compiler");
    }
}
static CxxCompiler cxxFromProgramOnly(string program)
{
    return CxxCompiler(program, determineCxxKind(program));
}
CxxCompiler findAndVerifyCxxCompiler()
{
    auto cxx = findCxxCompiler();

    // Check if the user has specified an architecture
    const userSpecifiedArch = getUserSpecifiedTargetArch;
    if (!userSpecifiedArch.isNull)
    {
        // verify that the compiler supports this arch
        if (!cxx.supports(userSpecifiedArch.get))
            throw fatal("The compiler does not support the given target architecture '%s'", userSpecifiedArch.get);
    }
    return cxx;
}
CxxCompiler findCxxCompiler()
{
    if (Env.CXX)
    {
        CxxKind kind;
        if (Env.CXX_KIND)
        {
            if (Env.CXX_KIND == "g++")
                kind = CxxKind.gnu;
            else if (Env.CXX_KIND == "clang++")
                kind = CxxKind.clang;
            else
                throw fatal("unknown CXX_KIND '%s'", Env.CXX_KIND);
            return CxxCompiler(Env.CXX, kind);
        }
        return cxxFromProgramOnly(Env.CXX);
    }
    if (Env.CXX_KIND)
        throw fatal("TODO: implement CXX_KIND without CXX");

    static string find(string prog)
    {
        const cxx = which(prog);
        if (cxx.empty)
            throw fatal("Cannot find C++ Compiler, CXX is not set and cannot find '%s' in PATH", prog);
        return cxx;
    }

    version (Windows)
    {
        bool skipDmc = false;
        const userSpecifiedArch = getUserSpecifiedTargetArch;
        if (!userSpecifiedArch.isNull)
        {
            if (userSpecifiedArch.get != Arch.x86)
                skipDmc = true;
        }

        if (!skipDmc)
        {
            const dmcProg = which("dmc");
            if (dmcProg.length > 0)
                return CxxCompiler(dmcProg, CxxKind.dmc);
        }
        return CxxCompiler(find("cl"), CxxKind.msvc);
    }
    else
    {
        return cxxFromProgramOnly(find("c++"));
    }
}

string findDCompiler()
{
    if (Env.DCOMPILER)
        return Env.DCOMPILER;

    string dmd = which("dmd");
    if (dmd.empty)
        throw fatal("DCOMPILER is not set and cannot find 'dmd' in PATH");
    return dmd;
}
string determineLibArchiver()
{
    version (Posix)
        return Env.AR ? Env.AR : "ar";
    return "lib";
}
CxxArgs* setupCxxArgs()
{
    static __gshared CxxArgs args;

    args
        .noExcept
        .noRtti
        .warningsAsErrors
        .compileCAsCxx
        .define("MARS=1")
        .define("TARGET_" ~ getTargetOS.toUpper ~ "=1")
        ;
    if (envEnabled!"ENABLE_PIC")
        args.pic;

    auto cxx = getCxxCompiler();
    {
        const userSpecifiedArch = getUserSpecifiedTargetArch;
        if (!userSpecifiedArch.isNull)
        {
            final switch (cxx.supports(userSpecifiedArch.get))
            {
            case ArchSupport.no:
                throw fatal("This compiler does not support arch '%s'", userSpecifiedArch.get);
            case ArchSupport.yesDefault:
                logf("This compiler compiles to '%s' by default", userSpecifiedArch.get);
                break;
            case ArchSupport.yesNotDefault:
                logf("This compiler compiles to '%s', but not by default", userSpecifiedArch.get);
                args.overrideTargetArch(userSpecifiedArch.get);
                break;
            }
        }
    }
    if (cxx.kind == CxxKind.dmc)
        args.define("DM_TARGET_CPU_" ~ getFinalTargetArch.to!string.capitalize ~ "=1");

/+
    // TODO: design common API for warnings
    if (envEnabled!"ENABLE_WARNINGS")
    {
        flags ~= ["-Wall", "-Wextra", "-Werror",
            "-Wno-attributes",
            "-Wno-char-subscripts",
            "-Wno-deprecated",
            "-Wno-empty-body",
            "-Wno-format",
            "-Wno-missing-braces",
            "-Wno-missing-field-initializers",
            "-Wno-overloaded-virtual",
            "-Wno-parentheses",
            "-Wno-reorder",
            "-Wno-return-type",
            "-Wno-sign-compare",
            "-Wno-strict-aliasing",
            "-Wno-switch",
            "-Wno-type-limits",
            "-Wno-unknown-pragmas",
            "-Wno-unused-function",
            "-Wno-unused-label",
            "-Wno-unused-parameter",
            "-Wno-unused-value",
            "-Wno-unused-variable",
        ];
        if (cxx.kind == CxxKind.gnu)
            flags ~= [
                "-Wno-logical-op",
                "-Wno-narrowing",
                "-Wno-unused-but-set-variable",
                "-Wno-uninitialized",
                "-Wno-class-memaccess",
                "-Wno-implicit-fallthrough",
            ];
    }
    else
    {
        if (cxx.kind == CxxKind.gnu || cxx.kind == CxxKind.clang)
        {
            flags ~= ["-Wno-deprecated", "-Wstrict-aliasing", "-Werror"];
            if (cxx.kind == CxxKind.clang)
                flags ~= "-Wno-logical-op-parentheses";
        }
    }
    */

    if (cxx.kind == CxxKind.gnu || cxx.kind == CxxKind.clang)
    {
        flags ~= [
            "-D__pascal=",
            // TODO: add target model to build.cxx module !!!
            //       args.targetArch or args.targetModel or something
            "-m" ~ getTargetModel,
        ];
    }

    if (cxx.kind == CxxKind.gnu)
        flags ~= ["-std=gnu++98"];
    if (cxx.kind == CxxKind.clang)
        flags ~= ["-xc++"];

    // TODO: add support for dObjc
    auto dObjc = false;
    version(OSX) version(X86_64)
        dObjc = true;
+/

    //if (getBuildType == BuildType.debug_)
    //    flags ~= ["-g", "-g3", "-DDEBUG=1", "-DUNITTEST"];
    if (getBuildType == BuildType.debug_)
    {
        args.define("DEBUG=1");
        args.define("UNITTEST");
    }
/+
    if (envEnabled!"ENABLE_OPTIMIZATION")
    {
        if (getCxxCompiler.kind == CxxKind.dmc)
            flags ~= ["-o"];
        else
            flags ~= ["-O2"];
    }

    if (envEnabled!"ENABLE_PROFILING")
        flags ~= ["-pg", "-fprofile-arcs", "-ftest-coverage"];
    if (envEnabled!"ENABLE_PGO_GENERATE")
    {
        enforce(Env.PGO_DIR, "ENABLE_PGO_GENERATE requires PGO_DIR to be set");
        flags ~= ["-fprofile-generate=" ~ Env.PGO_DIR];
    }
    if (envEnabled!"ENABLE_PGO_USE")
    {
        enforce(Env.PGO_DIR, "ENABLE_PGO_GENERATE requires PGO_DIR to be set");
        flags ~= ["-fprofile-use=" ~ Env.PGO_DIR, "-freorder-blocks-and-partition"];
    }
    if (envEnabled!"ENABLE_LTO")
        flags ~= ["-flto"];
    if (envEnabled!"ENABLE_COVERAGE")
        flags ~= ["--coverage"];
    if (envEnabled!"ENABLE_SANITIZERS")
        flags ~= ["-fsanitize=" ~ Env.ENABLE_SANITIZERS];
        /+
    // cxx debug flags
    if (env.get("DEBUG"))
        assert(0, "not impl: parse DEBUG ENV into array");
    else
        Global.DEBUG = ["-gl", "-D", "-DUNITTEST"];
    if (env.get("DDEBUG"))
        assert(0, "not impl: parse DDEBUG ENV into array");
    else
        Global.DDEBUG = ["-debug", "-g", "-unittest"];
        +/
    +/
    return &args;
}
string[] setupDFlags()
{
    string[] flags = ["-version=MARS", "-w", "-de", "-J" ~ Global.genDir];
    final switch (getFinalTargetArch)
    {
        case Arch.x86: flags ~= "-m32"; break;
        case Arch.x86_64: flags ~= "-m64"; break;
    }
    if (envEnabled!"ENABLE_PIC")
        flags ~= "-fPIC";
/+
    // TODO: add support for dObjc
    auto dObjc = false;
    version(OSX) version(X86_64)
        dObjc = true;
+/
    if (getBuildType == BuildType.debug_)
        flags ~= ["-g", "-debug"];
    else // BuildType.release
        flags ~= ["-release"];

    if (envEnabled!"ENABLE_OPTIMIZATION")
        flags ~= ["-O", "-inline"];
    if (envEnabled!"ENABLE_UNITTEST")
        flags ~= ["-unittest", "-cov"];
    if (envEnabled!"ENABLE_PROFILING")
        flags ~= ["-profile"];
    if (envEnabled!"ENABLE_COVERAGE")
        flags ~= ["-cov", "-L-lgcov"];

    {
        const cxx = getCxxCompiler;
        if (cxx.kind == CxxKind.msvc)
        {
            final switch (getFinalTargetArch)
            {
                case Arch.x86: flags ~= "-m32mscoff"; break;
                case Arch.x86_64: flags ~= "-m64"; break;
            }
        }
    }

    return flags;
}

string archDirName(Arch arch)
{
    final switch (arch)
    {
        case Arch.x86: return "32";
        case Arch.x86_64: return "64";
    }
}

int main(string[] args)
{
    try { return main2(args); }
    catch (SilentException) { return 1; }
    catch (MakeException e)
    {
        errorf(e.msg);
        return 1;
    }
}
int main2(string[] args)
{
    //
    // Initialize Env.*
    //
    {
        string*[string] varMap;
        foreach (member; __traits(allMembers, Env))
        {
            varMap[member] = &__traits(getMember, Env, member);
        }
        // TODO: should filter environment variables? (i.e. PATH, DFLAGS, HTTP_PROXY etc)
        loadEnvVars(varMap);
        args = loadCmdLine(varMap, args);
        foreach (var; envVars)
        {
            static if(var.default_)
            {
                if (!__traits(getMember, Env, var.name))
                {
                    __traits(getMember, Env, var.name) = var.default_;
                }
            }
        }
    }
    //
    // Initialize Global.*
    //
    Global.srcDir = shortPath(__FILE_FULL_PATH__.dirName);
    Global.repoDir = shortPath(__FILE_FULL_PATH__.dirName.dirName);
    Global.genDir = buildPath(Global.repoDir, "generated", getTargetOS, getBuildType.toString, getFinalTargetArch.archDirName);
    Global.resourceDir = buildPath(Global.repoDir, "res");

    Global.dmdDir = buildPath(Global.srcDir, "dmd");
    Global.backendDir = buildPath(Global.dmdDir, "backend");
    Global.tkDir = buildPath(Global.dmdDir, "tk");
    Global.rootDir = buildPath(Global.dmdDir, "root");
    Global.examplesDir = buildPath(Global.dmdDir, "examples");

    int jobs = totalCPUs;
    bool force; // always build everything (ignores timestamp checking)
    auto res = getopt(args,
        "j|jobs", "Specifies the number of jobs (commands) to run simultaneously (default: %d)".format(totalCPUs), &jobs,
        "v", "Verbose command output", (cast(bool*) &verboseBuildEnabled),
        "f", "Force run (ignore timestamps and always run all tests)", (cast(bool*) &force),
    );
    if (force)
        assert(0, "force not implemented");

    int showHelp()
    {
        import std.ascii : newline;

        auto envVarString = "";
        foreach(envVar; envVars)
        {
            envVarString ~= format("%s%-30s%s", newline, envVar.name, envVar.description);
        }
        defaultGetoptPrinter(`
Usage: ./build2.d <targets>...
       rund build2.d <targets>...

Examples
--------

    ./build2.d dmd           # build DMD
    ./build2.d unittest      # runs internal unittests
    ./build2.d clean         # remove all generated files

Environment Variables
--------` ~ envVarString ~ `

Targets
-------

unittest              Run all unittest blocks

Command-line parameters
-----------------------`, res.options);
        return 1;
    }

    if (res.helpWanted)
        return showHelp;

    /*
    if (verboseBuildEnabled)
    {
        logf("================================================================================");
        foreach (key, value; env.aa)
            logf("%s=%s", key, value);
        logf("================================================================================");
    }
    */

    // default target
    args.popFront;
    if (args.length == 0)
        args = ["dmd"];

    auto make = Make();
    make.addGlobalDepend(shortPath(__FILE_FULL_PATH__));
    make.addRule
        .phonyTarget("testrules")
        .action(delegate(Rule rule) {
            testrules(make);
        })
        ;
    make.addRule
        .phonyTarget("testbuild")
        .action(delegate(Rule rule) {
            const testDir = buildPath(Global.repoDir, "testbuild");
            make.testBuild(testDir, ["testdepends", "testbuild"]);
        })
        ;
    make.addRule
        .target(Global.genDir)
        .action(delegate(Rule rule) {
            mkdirRecurse(rule.target);
        })
        ;
    const versionFile = buildPath(Global.genDir, "VERSION");
    make.addRule
        .target(versionFile)
        .depend(Global.genDir)
        .action(delegate(Rule rule) {
            run(["git", "describe", "--dirty"]).toFile(rule.target);
        })
        ;
    const sysconfDirFile = buildPath(Global.genDir, "SYSCONFDIR.imp");
    make.addRule
        .target(sysconfDirFile)
        .depend(Global.genDir)
        .action(delegate(Rule rule) {
            toFile(Env.SYSCONFDIR, sysconfDirFile);
        })
        ;
    //
    // backend
    //
    const opTabBin = buildPath(Global.genDir, "optabgen".exeName);
    make.addRule
        .target(opTabBin)
        .depend(buildPath(Global.backendDir, "optabgen.d"))
        .action(delegate(Rule rule ) {
            run([getDCompiler(), rule.depend, "-of=" ~ opTabBin, "-I=" ~ Global.srcDir]
                .chain(getDFlags)
                .array);
        })
        ;
    const opTabFiles = ["debtab.d", "optab.d", "cdxxx.d", "elxxx.d", "fltables.d", "tytab.d"];
    auto opTabGenerated = opTabFiles.map!(e => buildPath(Global.genDir, e)).array;
    make.addRule
        .target(opTabGenerated)
        .depend(opTabBin)
        .action(delegate(Rule rule) {
            // optabgen generates files in cwd (TODO: fix this)
            run([rule.depend]);
            // move the generated files to the generated folder
            opTabFiles.zip(opTabGenerated).each!(a => a.expand.rename);
        })
        ;
    const cBackendObjects = ["fp", "strtold", "tk"].map!(e => buildPath(Global.genDir, e.objName)).array;
    foreach (obj; cBackendObjects)
    {
        make.addRule
            .target(obj)
            .dependGroup("source", buildPath(Global.backendDir, obj.baseName.setExtension("c")))
            .depend(Global.genDir)
            //.depend(configFiles)
            .action(delegate(Rule rule) {
                run(getCxxCompiler.makeCommand
                    .merge(*getCxxArgs())
                    .noLink
                    .outName(rule.target)
                    .define("DMDV2=1")
                    .includePath(Global.rootDir)
                    .includePath(Global.tkDir)
                    .includePath(Global.backendDir)
                    .includePath(Global.genDir)
                    .includePath(Global.dmdDir)
                    .sources(rule.dependGroup("source"))
                    .makeArgs);
            })
            ;
    }
    const dBackendSource = `
aarray backconfig barray bcomplex blockopt compress cg cgcs
cgelem cgen cgobj cgreg cgsched cgxmm cg87 cgcod
cod1 cod2 cod3 cod4 cod5 cv8 dcode dcgcv debugprint divcoeff
drtlsym dtype dvarstats dvec dwarfdbginf dwarfeh ee elem
elfobj evalu8 filespec gdag gflow glocal gloop go goh gother
gsroa md5 memh mscoffobj newman nteh os out pdata ph2 ptrntab
symbol util2 var`.split
        .map!(e => buildPath(Global.backendDir, e ~ ".d")).array;
    version (SeparateBackendObjects)
    {
        const dBackendObjects = dBackendSource.map!(e => e.objName).array;
        foreach (i, obj; dBackendObjects)
        {
            make.addRule
                .target(obj)
                .dependGroup("input", dBackendSource[i])
                .depend(opTabGenerated)
                .action(delegate(Rule rule) {
                    run([getDCompiler, "-c", "-of" ~ rule.target, "-betterC", "-I=" ~ Global.srcDir]
                        .chain(getDFlags, rule.dependGroup("input")).array);
                })
                ;
        }
    }
    else
    {
        const dBackendObjects = buildPath(Global.genDir, "dbackend".objName);
        make.addRule
            .phonyTarget("dbackend")
            .depend(dBackendObjects)
            ;
        make.addRule
            .target(dBackendObjects)
            .dependGroup("source", dBackendSource)
            .depend(opTabGenerated)
            .action(delegate(Rule rule) {
                run([getDCompiler, "-c", "-of" ~ rule.target, "-betterC", "-J" ~ Global.genDir, "-I=" ~ Global.srcDir]
                    .chain(getDFlags, rule.dependGroup("source")).array);
            })
            ;
    }
    const backendLib = buildPath(Global.genDir, "backend".libName);
    make.addRule
        .target(backendLib)
        .dependGroup("input", cBackendObjects)
        .dependGroup("input", dBackendObjects)
        .action(delegate(Rule rule) {
            makeLibArchive(rule.target, rule.dependGroup("input"));
        })
        ;
    //
    // lexer library
    //
    const lexerSource =
        `console entity errors globals id identifier lexer tokens utf`.split
        .map!(e => buildPath(Global.dmdDir, e ~ ".d")).chain(
        `array ctfloat file filename hash outbuffer port rmem rootobject stringtable`.split
        .map!(e => buildPath(Global.rootDir, e ~ ".d"))).array;
    const lexerLib = buildPath(Global.genDir, "lexer".libName);
    make.addRule
        .phonyTarget("lexer")
        .depend(lexerLib)
        ;
    make.addRule
        .target(lexerLib)
        .dependGroup("source", lexerSource)
        .depend(versionFile)
        //.depend(configFiles)
        .action(delegate(Rule rule) {
            run([getDCompiler, "-of" ~ rule.target, "-lib", "-J" ~ Global.genDir, "-J" ~ Global.resourceDir, "-I=" ~ Global.srcDir]
                .chain(getDFlags, rule.dependGroup("source")).array);
        })
        ;
    //
    // dmd
    //
    const dmdConf = buildPath(Global.genDir, "dmd.conf");
    make.addRule
        .target(dmdConf)
        .depend(Global.genDir)
        .action(delegate(Rule rule) {
            // TODO: add support for Windows
            writefln("generating '%s'", rule.target);
            string exportDynamic;
            version(OSX) {} else
                exportDynamic = " -L--export-dynamic";

           `[Environment32]
DFLAGS=-I%@P%/../../../../../druntime/import -I%@P%/../../../../../phobos -L-L%@P%/../../../../../phobos/generated/{OS}/{BUILD}/32{exportDynamic}

[Environment64]
DFLAGS=-I%@P%/../../../../../druntime/import -I%@P%/../../../../../phobos -L-L%@P%/../../../../../phobos/generated/{OS}/{BUILD}/64{exportDynamic} -fPIC`
            .replace("{exportDynamic}", exportDynamic)
            .replace("{OS}", getHostOS)
            .replace("{BUILD}", getBuildType.toString)
            .toFile(rule.target);
        })
        ;
    const dmdBin = buildPath(Global.genDir, "dmd".exeName);
    if (dmdBin != "dmd")
    {
        make.addRule
            .phonyTarget("dmd")
            .depend(dmdBin)
            ;
    }

    const frontSource = `
access aggregate aliasthis apply argtypes arrayop arraytypes
astcodegen attrib blockexit builtin canthrow cli clone compiler
complex cond constfold cppmangle cppmanglewin ctfeexpr ctorflow
dcast dclass declaration delegatize denum dimport dinifile dinterpret
dmacro dmangle dmodule doc dscope dstruct dsymbol dsymbolsem
dtemplate dversion env escape expression expressionsem func hdrgen
id impcnvtab imphint init initsem inline inlinecost intrange json
lambdacomp lib link mars mtype nogc nspace objc opover optimize
parse parsetimevisitor permissivevisitor printast safe sapply
semantic2 semantic3 sideeffect statement statement_rewrite_walker
statementsem staticassert staticcond target templateparamsem typesem
traits transitivevisitor typinf utils visitor`.split
        .map!(e => buildPath(Global.dmdDir, e ~ ".d")).array;

    const rootSource = `
aav array ctfloat file filename man outbuffer port response
rmem rootobject speller stringtable hash`.split
        .chain(getCxxCompiler.kind == CxxKind.dmc ? null : ["longdouble"])
        .map!(e => buildPath(Global.rootDir, e ~ ".d")).array;

    const objectFormatsSource =
        ((getTargetOS == "windows") ?
            ["libmscoff", "libomf", "scanmscoff", "scanomf"] :
            ["libelf", "libmach", "scanelf", "scanmach"])
            .map!(e => buildPath(Global.dmdDir, e ~ ".d")).array;

    const glueSource = `
irstate toctype glue gluelayer todt tocsym toir dmsc
tocvdebug s2ir toobj e2ir eh iasm iasmdmd iasmgcc objc_glue`.split
        .map!(e => buildPath(Global.dmdDir, e ~ ".d")).array;

    const backendHeaders = `
cc cdef cgcv code cv4 dt el global obj oper outbuf rtlsym code_x86
iasm codebuilder ty type exh mach mscoff dwarf dwarf2 xmm dlist melf`.split
        .map!(e => buildPath(Global.backendDir, e ~ ".d"))
        .chain(buildPath(Global.backendDir, "varstats.di").only)
        .array;

    make.addRule
        .target(dmdBin)
        .depend(sysconfDirFile)
        .dependGroup("input", backendLib)
        .dependGroup("input", lexerLib)
        .dependGroup("input", rootSource)
        .dependGroup("input", frontSource)
        .dependGroup("input", objectFormatsSource)
        .dependGroup("input", glueSource)
        .dependGroup("input", backendHeaders)
        .depend(dmdConf)
        .action(delegate(Rule rule) {
            string[] extra;
            version (Windows)
                extra ~= ["-L/STACK:8388608", "-L/ma/co/la"];
            run([getDCompiler, "-of" ~ rule.target, "-vtls",
                "-J" ~ Global.genDir, "-J" ~ Global.resourceDir, "-I=" ~ Global.srcDir]
                .chain(getDFlags, extra, rule.dependGroup("input")).array);
        })
        ;
    if (verboseBuildEnabled)
    {
        writeln("Make Rules:");
        writeln("--------------------------------------------------------------------------------");
        make.dump();
        writeln("--------------------------------------------------------------------------------");
    }
    writefln("Building '%s'...", args);
    make.build(args, null);
    writeln("Success");
    return 0;
}

void makeLibArchive(string lib, string[] objs)
{
    // TODO: determine based on tools (not POSIX vs WINDOWS)
    auto cxx = getCxxCompiler;
    if (cxx.kind == CxxKind.gnu || cxx.kind == CxxKind.clang)
    {
        run([getLibArchiver, "rcs", lib].chain(objs).array);
    }
    else if (cxx.kind == CxxKind.dmc)
    {
        run([getLibArchiver, "-p512", "-n", "-c", lib].chain(objs).array);
    }
    else
    {
        assert(cxx.kind == CxxKind.msvc, "code bug");
        run([getLibArchiver, "/out:" ~ lib].chain(objs).array);
    }
}

auto execute(T...)(scope const(char[])[] args, T extra)
{
    logf("[EXECUTE] %s", escapeShellCommand(args));
    try { return std.process.execute(args, extra); }
    catch (Exception e)
    {
        throw fatal("'%s' failed: %s", args[0], e.msg);
    }
}
auto tryRun(scope const(char[])[] args)
{
    auto result = execute(args, null, Config.none, size_t.max);
    if (result.status != 0)
    {
        writefln("Error: '%s' failed:\n%s", args[0], result.output);
    }
    return result;
}
auto run(scope const(char[])[] args)
{
    auto result = tryRun(args);
    if (result.status != 0)
        throw fatal("'%s' failed", args[0]); // error already logged
    return result.output;
}

// test each rule from a clean state
// TODO: do even better isolation by executing each step in it's own temporary
//       directory with all it's dependencies
//       copy depends <temp_dir>
//       cd <temp_dir>
//       ./src/build2.d
void testrules(ref const Make currentMake)
{
    // make sure we are currently clean
    auto output = run(["git", "clean", "-xfd", "--dry-run", Global.repoDir]);
    writeln(output);
    if (output.length > 0)
        throw fatal("cannot run 'testrules' because the repo is not clean");

    auto makeCopy = currentMake.copy();
    import std.algorithm : canFind;
    import std.stdio;

    // build every target from a clean state, but only build it declared dependencies
  RuleLoop:
    foreach (ruleIndex, testRule; makeCopy.getRules)
    {
       assert(testRule.targets.length > 0, "code bug: have a rule with no targets");
       if (testRule.targets[0].among("testrules", "testbuild"))
       {
           writefln("Skipping rule %s (target=%s)", ruleIndex + 1, testRule.targets[0]);
           continue;
       }

       writefln("Testing rule %s of %s...", ruleIndex + 1, makeCopy.getRules.length);
       foreach (target; testRule.targets)
       {
           writefln(" target '%s'", target);
       }
       writeln("--------------------------------------------------------------------------------");
       run(["git", "clean", "-xfd", Global.repoDir]);
       makeCopy.resetBuildState();
       foreach (targetInfo; testRule.targetInfos)
       {
           if (!targetInfo.isPhony)
           {
               if (exists(targetInfo.name))
                   throw new MakeException(format(
                   "target '%s' still exists after running the clean command", targetInfo));
           }
       }
       makeCopy.build(testRule.targets[0], null);
    }
}
