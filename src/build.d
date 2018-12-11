#!/usr/bin/env rdmd
/**
DMD builder

Usage:
  ./build.d dmd

TODO:
- add all posix.mak Makefile targets
- support 32-bit builds
- test on OSX
- test on Windows
- allow appending DFLAGS via the environment
- test the script with LDC or GDC as host compiler
*/

version(CoreDdoc) {} else:

import std.algorithm, std.conv, std.datetime, std.exception, std.file, std.format,
       std.getopt, std.parallelism, std.path, std.process, std.range, std.stdio, std.string;
import core.stdc.stdlib : exit;

const thisBuildScript = __FILE_FULL_PATH__;
const srcDir = thisBuildScript.dirName.buildNormalizedPath;
shared bool verbose; // output verbose logging
shared bool force; // always build everything (ignores timestamp checking)

__gshared string[string] env;
__gshared string[][string] flags;
__gshared typeof(sourceFiles()) sources;

void main(string[] args)
{
    int jobs = totalCPUs;
    auto res = getopt(args,
        "j|jobs", "Specifies the number of jobs (commands) to run simultaneously (default: %d)".format(totalCPUs), &jobs,
        "v", "Verbose command output", (cast(bool*) &verbose),
        "f", "Force run (ignore timestamps and always run all tests)", (cast(bool*) &force),
    );
    void showHelp()
    {
        defaultGetoptPrinter(`./build.d <targets>...

Examples
--------

    ./build.d dmd           # build DMD
    ./build.d unittest      # runs internal unittests
    ./build.d clean         # remove all generated files

Important variables:
--------------------

HOST_CXX:             Host C++ compiler to use (g++,clang++)
HOST_DMD:             Host D compiler to use for bootstrapping
AUTO_BOOTSTRAP:       Enable auto-boostrapping by downloading a stable DMD binary
MODEL:                Target architecture to build for (32,64) - defaults to the host architecture

Build modes:
------------
BUILD: release (default) | debug (enabled a build with debug instructions)

Opt-in build features:

ENABLE_RELEASE:       Optimized release built
ENABLE_DEBUG:         Add debug instructions and symbols (set if ENABLE_RELEASE isn't set)
ENABLE_WARNINGS:      Enable C++ build warnings
ENABLE_PROFILING:     Build dmd with a profiling recorder (C++)
ENABLE_PGO_USE:       Build dmd with existing profiling information (C++)
  PGO_DIR:            Directory for profile-guided optimization (PGO) logs
ENABLE_LTO:           Enable link-time optimizations
ENABLE_UNITTEST:      Build dmd with unittests (sets ENABLE_COVERAGE=1)
ENABLE_PROFILE:       Build dmd with a profiling recorder (D)
ENABLE_COVERAGE       Build dmd with coverage counting
ENABLE_SANITIZERS     Build dmd with sanitizer (e.g. ENABLE_SANITIZERS=address,undefined)

Targets
-------

all                   Build dmd
unittest              Run all unittest blocks
clean                 Remove all generated files

The generated files will be in generated/$(OS)/$(BUILD)/$(MODEL)

Command-line parameters
-----------------------
`, res.options);
        return;
    }

    if (res.helpWanted)
        return showHelp;

    // parse arguments
    args.popFront;
    args2Environment(args);

    // default target
    if (!args.length)
        args = ["all"];

    // bootstrap all needed environment variables
    parseEnvironment;

    auto targets = args
        .predefinedTargets // preprocess
        .array;

    processEnvironment;

    // get all sources
    sources = sourceFiles;

    if (targets.length == 0)
        return showHelp;

    if (verbose)
    {
        log("================================================================================");
        foreach (key, value; env)
            log("%s=%s", key, value);
        log("================================================================================");
    }
    foreach (target; targets)
        target();
}

/**
D build dependencies
====================

The strategy of this script is to emulate what the Makefile is doing,
but without a complicated dependency and dependency system.
The "dependency system" used here is rather naive and only parallelizes the
build of the backend and lexer (writing a few config files doesn't take much time).
However, it does skip steps when the source files are younger than the target
and thus supports partial rebuilds.

Below all individual dependencies of DMD are defined.
They have a target path, sources paths and an optional name.
When a dependency is needed either its command or custom commandFunction is executed.
A dependency will be skipped if all targets are older than all sources.
This script is by default part of the sources and thus any change to the build script,
will trigger a full rebuild.

The function buildDMD defines the build order of its dependencies.
*/

/// Returns: the dependency that builds the lexer
auto lexer()
{
    Dependency dependency = {
        target: env["G"].buildPath("lexer").libName,
        sources: sources.lexer,
        rebuildSources: configFiles,
        name: "(DC) D_LEXER_OBJ",
        command: [
            env["HOST_DMD_RUN"],
            "-of$@",
            "-lib",
            "-J"~env["G"], "-J../res",
        ].chain(flags["DFLAGS"], "$<".only).array
    };
    return dependency;
}

/// Returns: the dependency that generates the dmd.conf file in the output folder
auto dmdConf()
{
    // TODO: add support for Windows
    string exportDynamic;
    version(OSX) {} else
        exportDynamic = " -L--export-dynamic";

    auto conf = `[Environment32]
DFLAGS=-I%@P%/../../../../../druntime/import -I%@P%/../../../../../phobos -L-L%@P%/../../../../../phobos/generated/$(OS)/$(BUILD)/32{exportDynamic}

[Environment64]
DFLAGS=-I%@P%/../../../../../druntime/import -I%@P%/../../../../../phobos -L-L%@P%/../../../../../phobos/generated/$(OS)/$(BUILD)/64{exportDynamic} -fPIC`.replace("{exportDynamic}", exportDynamic);

    auto target = env["G"].buildPath("dmd.conf");
    auto commandFunction = (){
        conf.toFile(target);
    }; // defined separately to support older D compilers
    Dependency dependency = {
        target: target,
        name: "(TX) DMD_CONF",
        commandFunction: commandFunction,
    };
    return dependency;
}

/// Returns: the dependency that builds and executes the optabgen utility
auto opTabGen()
{
    auto opTabFiles = ["debtab.d", "optab.d", "cdxxx.d", "elxxx.d", "fltables.d", "tytab.d"];
    auto opTabFilesBin = opTabFiles.map!(e => env["G"].buildPath(e)).array;
    auto opTabBin = env["G"].buildPath("optabgen").exeName;
    auto opTabSourceFile = env["C"].buildPath("optabgen.d");

    auto commandFunction = (){
        auto args = [env["HOST_DMD_RUN"], opTabSourceFile, "-of" ~ opTabBin];
        args ~= flags["DFLAGS"];

        writefln("(DC) BUILD_OPTABGEN");
        args.runCanThrow;

        writefln("(RUN) OPTABBIN %-(%s, %)", opTabFiles);
        [opTabBin].runCanThrow;

        // move the generated files to the generated folder
        opTabFiles.map!(a => srcDir.buildPath(a)).zip(opTabFilesBin).each!(a => a.expand.rename);
    }; // defined separately to support older D compilers
    Dependency dependency = {
        targets: opTabFilesBin,
        sources: [opTabSourceFile],
        commandFunction: commandFunction,
    };
    return dependency;
}

version(Windows)
{
    /// Returns: the dependency that builds msvc-dmd.exe
    auto buildMsvcDmc()
    {
        enum targetName = "msvc-dmc";

        Dependency dependency = {
            target: env["G"].buildPath(targetName).exeName,
            sources: [`vcbuild\` ~ targetName],
            name: "(DC) MSCV-CC " ~ targetName,
            command: [env["HOST_DMD_RUN"], "-of$@", "$<"]
        };
        return dependency;
    }

    /// Returns: the dependency that builds msvc-lib.exe
    auto buildMsvcLib()
    {
        enum targetName = "msvc-lib";

        Dependency dependency = {
            target: env["G"].buildPath(targetName).exeName,
            sources: [`vcbuild\` ~ targetName],
            name: "(DC) MSCV-LIB " ~ targetName,
            command: [env["HOST_DMD_RUN"], "-of$@", "$<"]
        };
        return dependency;
    }
}

/**
Gets the dependency that generates the given object file from the given source file

Params:
    obj      = the object file that the dependency should generate
    fileName = the source file to build, generating the object file
Returns:
    the dependency that generates the given object file from the given source file
*/
auto buildCXX(string obj, string fileName)
{
    Dependency dependency = {
        target: obj,
        sources: [fileName],
        rebuildSources: sources.backendC ~ configFiles,
        name: "(CC) BACK_OBJS %s".format(fileName),
        command: [env["HOST_CXX"], "-c", "-o$@"].chain(flags["CXXFLAGS"], flags["BACK_FLAGS"], "$<".only).array
    };
    return dependency;
}

/// Returns: the dependencies that build the D backend
auto dBackend()
{
    Dependency dependency = {
        target: env["G"].buildPath("dbackend").objName,
        sources: sources.backend,
        name: "(DC) D_BACK_OBJS %-(%s %)".format(sources.backend),
        command: [
            env["HOST_DMD_RUN"],
            "-c",
            "-of$@",
            "-betterC",
        ].chain(flags["DFLAGS"], "$<".only).array
    };
    return dependency;
}

/// Returns: the dependencies that build the C++ backend
auto cxxBackend()
{
    Dependency[] dependencies;
    foreach (obj; sources.backendObjects)
        dependencies ~= buildCXX(obj, env["C"].buildPath(obj.baseName.stripExtension ~ ".c"));

    return dependencies;
}

/// Execute the sub-dependencies of the backend and pack everything into one object file
auto buildBackend()
{
    opTabGen.run;

    Dependency[] dependencies = cxxBackend();
    dependencies ~= dBackend;
    foreach (dependency; dependencies.parallel(1))
        dependency.run;

    // Pack the backend
    Dependency dependency = {
        sources: sources.backendObjects.chain(env["G"].buildPath("dbackend").objName.only).array,
        target: env["G"].buildPath("backend").libName,
        command: [env["AR"], "rcs", "$@", "$<"],
    };
    dependency.run;
    return dependency;
}

/// Returns: the dependencies that generate required string files: VERSION and SYSCONFDIR.imp
auto buildStringFiles()
{
    const versionFile = env["G"].buildPath("VERSION");
    auto commandFunction = (){
        "(TX) VERSION".writeln;
        ["git", "describe", "--dirty"].runCanThrow.toFile(versionFile);
    };
    Dependency versionDependency = {
        target: versionFile,
        commandFunction: commandFunction,
    };
    const sysconfDirFile = env["G"].buildPath("SYSCONFDIR.imp");
    commandFunction = (){
        "(TX) SYSCONFDIR".writeln;
        env["SYSCONFDIR"].toFile(sysconfDirFile);
    };
    Dependency sysconfDirDependency = {
        sources: [thisBuildScript],
        target: sysconfDirFile,
        commandFunction: commandFunction,
    };
    return [versionDependency, sysconfDirDependency];
}

/// Returns: a list of config files that are required by the DMD build
auto configFiles()
{
    return buildStringFiles.map!(a => a.target).array ~ dmdConf.target;
}

/**
Main build routine for the DMD compiler.
Defines the required order for the build dependencies, runs all these dependency dependencies
and afterwards builds the DMD compiler.

Params:
  extra_flags = Flags to apply to the main build but not the dependencies
*/
auto buildDMD(string[] extraFlags...)
{
    version(Windows)
    {
        immutable model = detectModel;
        if (model == "64")
        {
            foreach (dependency; [buildMsvcDmc, buildMsvcLib].parallel(1))
                dependency.run;
        }
    }

    // The string files are required by most targets
    Dependency[] dependencies = buildStringFiles();
    foreach (dependency; dependencies.parallel(1))
        dependency.run;

    dependencies = [lexer, dmdConf];
    foreach (ref dependency; dependencies.parallel(1))
        dependency.run;

    auto backend = buildBackend();

    // Main DMD build dependency
    Dependency dependency = {
        // newdelete.o + lexer.a + backend.a
        sources: sources.dmd.chain(sources.root, dependencies[0].targets, backend.targets).array,
        target: env["DMD_PATH"],
        name: "(DC) MAIN_DMD_BUILD",
        command: [
            env["HOST_DMD_RUN"],
            "-of$@",
            "-vtls",
            "-J"~env["G"],
            "-J../res",
        ].chain(extraFlags).chain(flags["DFLAGS"], "$<".only).array
    };
    dependency.run;
}

/**
Goes through the target list and replaces short-hand targets with their expanded version.
Special targets:
- clean -> removes generated directory + immediately stops the builder

Params:
    targets = the target list to process
Returns:
    the expanded targets
*/
auto predefinedTargets(string[] targets)
{
    import std.functional : toDelegate;
    Appender!(void delegate()[]) newTargets;
    foreach (t; targets)
    {
        t = t.buildNormalizedPath; // remove trailing slashes
        switch (t)
        {
            case "auto-tester-build":
                "TODO: auto-tester-all".writeln; // TODO
                break;

            case "toolchain-info":
                "TODO: info".writeln; // TODO
                break;

            case "unittest":
                flags["DFLAGS"] ~= "-version=NoMain";
                newTargets.put((){
                    buildDMD("-main", "-unittest");
                    spawnProcess(env["DMD_PATH"]); // run the unittests
                }.toDelegate);
                break;

            case "cxx-unittest":
                "TODO: cxx-unittest".writeln; // TODO
                break;

            case "check-examples":
                "TODO: cxx-unittest".writeln; // TODO
                break;

            case "build-examples":
                "TODO: build-examples".writeln; // TODO
                break;

            case "checkwhitespace":
                "TODO: checkwhitespace".writeln; // TODO
                break;

            case "html":
                "TODO: html".writeln; // TODO
                break;

            case "install":
                "TODO: install".writeln; // TODO
                break;

            case "man":
                "TODO: man".writeln; // TODO
                break;

            dmd:
            case "dmd":
                newTargets.put({buildDMD();}.toDelegate);
                break;

            case "clean":
                if (env["G"].exists)
                    env["G"].rmdirRecurse;
                exit(0);
                break;

            case "all":
                goto dmd;
            default:
                writefln("ERROR: Target `%s` is unknown.", t);
                writeln;
                break;
        }
    }
    return newTargets.data;
}

/// Sets the environment variables
void parseEnvironment()
{
    env.getDefault("TARGET_CPU", "X86");
    auto os = env.getDefault("OS", detectOS);
    auto build = env.getDefault("BUILD", "release");
    enforce(build.among("release", "debug"), "BUILD must be 'debug' or 'release'");

    // detect Model
    auto model = env.getDefault("MODEL", detectModel);
    env["MODEL_FLAG"] = "-m" ~ env["MODEL"];

    // detect PIC
    version(Posix)
    {
        // default to PIC on x86_64, use PIC=1/0 to en-/disable PIC.
        // Note that shared libraries and C files are always compiled with PIC.
        bool pic;
        version(X86_64)
            pic = true;
        else version(X86)
            pic = false;
        if (environment.get("PIC", "0") == "1")
            pic = true;

        env["PIC_FLAG"]  = pic ? "-fPIC" : "";
    }
    else
    {
        env["PIC_FLAG"] = "";
    }

    env.getDefault("GIT", "git");
    env.getDefault("GIT_HOME", "https://github.com/dlang");
    env.getDefault("SYSCONFDIR", "/etc");
    env.getDefault("TMP", tempDir);
    env.getDefault("PGO_DIR", srcDir.buildPath("pgo"));
    auto d = env.getDefault("D", srcDir.buildPath("dmd"));
    env.getDefault("C", d.buildPath("backend"));
    env.getDefault("TK", d.buildPath("tk"));
    env.getDefault("ROOT", d.buildPath("root"));
    env.getDefault("EX", d.buildPath("examples"));
    auto generated = env.getDefault("GENERATED", srcDir.dirName.buildPath("generated"));
    auto g = env.getDefault("G", generated.buildPath(os, build, model));
    mkdirRecurse(g);

    env.getDefault("HOST_DMD", "dmd");

    // Auto-bootstrapping of a specific host compiler
    if (env.getDefault("AUTO_BOOTSTRAP", "0") != "0")
    {
        auto hostDMDVer = "2.074.1";
        writefln("Using Bootstrap compiler: %s", hostDMDVer);
        auto hostDMDRoot = env["G"].buildPath("host_dmd-"~hostDMDVer);
        auto hostDMDBase = hostDMDVer~"."~os;
        auto hostDMDURL = "http://downloads.dlang.org/releases/2.x/"~hostDMDVer~"/dmd."~hostDMDBase;
        env["HOST_DMD"] = hostDMDRoot.buildPath("dmd2", os, os == "osx" ? "bin" : "bin"~model, "dmd");
        env["HOST_DMD_PATH"] = env["HOST_DMD"];
        // TODO: use dmd.conf from the host too (in case there's a global or user-level dmd.conf)
        env["HOST_DMD_RUN"] = env["HOST_DMD"];
        if (!env["HOST_DMD"].exists)
        {
            writefln("Downloading DMD %s", hostDMDVer);
            auto curlFlags = "-fsSL --retry 5 --retry-max-time 120 --connect-timeout 5 --speed-time 30 --speed-limit 1024";
            hostDMDRoot.mkdirRecurse;
            ("curl " ~ curlFlags ~ " " ~ hostDMDURL~".tar.xz | tar -C "~hostDMDRoot~" -Jxf - || rm -rf "~hostDMDRoot).spawnShell.wait;
        }
    }
    else
    {
        env["HOST_DMD_PATH"] = getHostDMDPath(env["HOST_DMD"]).strip.absolutePath;
        env["HOST_DMD_RUN"] = env["HOST_DMD_PATH"];
    }

    if (!env["HOST_DMD_PATH"].exists)
    {
        stderr.writefln("No DMD compiler is installed. Try AUTO_BOOTSTRAP=1 or manually set the D host compiler with HOST_DMD");
        exit(1);
    }

    version(Windows)
    {
        const vswhere = getHostVSWhere(env["G"]);
        const vcBinDir = getHostMSVCBinDir(model, vswhere);

        // environment variable `MSVC_CC` will be read by `msvc-dmd.exe`
        env.getDefault("MSVC_CC", vcBinDir.buildPath("cl.exe"));

        // environment variable `MSVC_AR` will be read by `msvc-lib.exe`
        env.getDefault("MSVC_AR", vcBinDir.buildPath("lib.exe"));
    }

    env.getDefault("HOST_CXX", getHostCXX);
    env.getDefault("CXX_KIND", getHostCXXKind);

    env.getDefault("AR", "ar");
}

/// Checks the environment variables and flags
void processEnvironment()
{
    auto os = env["OS"];

    auto hostDMDVersion = [env["HOST_DMD_RUN"], "--version"].execute.output;
    if (hostDMDVersion.find("DMD"))
        env["HOST_DMD_KIND"] = "dmd";
    else if (hostDMDVersion.find("LDC"))
        env["HOST_DMD_KIND"] = "ldc";
    else if (!hostDMDVersion.find("GDC", "gdmd")[0].empty)
        env["HOST_DMD_KIND"] = "gdc";
    else
        enforce(0, "Invalid Host DMD found: " ~ hostDMDVersion);

    env["DMD_PATH"] = env["G"].buildPath("dmd").exeName;

    env.getDefault("ENABLE_WARNINGS", "0");
    string[] warnings;
    if (env["ENABLE_WARNINGS"] != "0")
    {
        warnings = ["-Wall", "-Wextra", "-Werror",
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
        if (env["CXX_KIND"] == "g++")
            warnings ~= [
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
        // default warnings
        warnings = ["-Wno-deprecated", "-Wstrict-aliasing", "-Werror"];
        if (env["CXX_KIND"] == "clang++")
            warnings ~= "-Wno-logical-op-parentheses";
    }

    auto targetCPU = "X86";
    auto cxxFlags = warnings;
    cxxFlags ~= [
        "-fno-exceptions", "-fno-rtti",
        "-D__pascal=", "-DMARS=1", "-DTARGET_"~os.toUpper~"=1",
        "-DDM_TARGET_CPU_"~targetCPU~"=1",
        env["MODEL_FLAG"],
        env["PIC_FLAG"],
    ];
    if (env["CXX_KIND"] == "g++")
        cxxFlags ~= ["-std=gnu++98"];
    if (env["CXX_KIND"] == "clang++")
        cxxFlags ~= ["-xc++"];

    // TODO: allow adding new flags from the environment
    string[] dflags = ["-version=MARS", "-w", "-de", env["PIC_FLAG"], env["MODEL_FLAG"], "-J"~env["G"]];

    flags["BACK_FLAGS"] = ["-I"~env["ROOT"], "-I"~env["TK"], "-I"~env["C"], "-I"~env["G"], "-I"~env["D"], "-DDMDV2=1"];

    // TODO: add support for dObjc
    auto dObjc = false;
    version(OSX) version(X86_64)
        dObjc = true;

    if (env.getDefault("ENABLE_DEBUG", "0") != "0")
    {
        cxxFlags ~= ["-g", "-g3", "-DDEBUG=1", "-DUNITTEST"];
        dflags ~= ["-g", "-debug"];
    }
    if (env.getDefault("ENABLE_RELEASE", "0") != "0")
    {
        cxxFlags ~= ["-O2"];
        dflags ~= ["-O", "-release", "-inline"];
    }
    else
    {
        // add debug symbols for all non-release builds
        if (!dflags.canFind("-g"))
            dflags ~= ["-g"];
    }
    if (env.getDefault("ENABLE_PROFILING", "0") != "0")
    {
        cxxFlags ~= ["-pg", "-fprofile-arcs", "-ftest-coverage"];
    }
    if (env.getDefault("ENABLE_PGO_GENERATE", "0") != "0")
    {
        enforce("PGO_DIR" in env, "No PGO_DIR variable set.");
        cxxFlags ~= ["-fprofile-generate="~env["PGO_DIR"]];
    }
    if (env.getDefault("ENABLE_PGO_USE", "0") != "0")
    {
        enforce("PGO_DIR" in env, "No PGO_DIR variable set.");
        cxxFlags ~= ["-fprofile-use="~env["PGO_DIR"], "-freorder-blocks-and-partition"];
    }
    if (env.getDefault("ENABLE_LTO", "0") != "0")
    {
        cxxFlags ~= ["-flto"];
    }
    if (env.getDefault("ENABLE_UNITTEST", "0") != "0")
    {
        dflags ~= ["-unittest", "-cov"];
    }
    if (env.getDefault("ENABLE_PROFILE", "0") != "0")
    {
        dflags ~= ["-profile"];
    }
    if (env.getDefault("ENABLE_COVERAGE", "0") != "0")
    {
        cxxFlags ~= ["--coverage"];
        dflags ~= ["-cov", "-L-lgcov"];
    }
    if (env.getDefault("ENABLE_SANITIZERS", "0") != "0")
    {
        cxxFlags ~= ["-fsanitize="~env["ENABLE_SANITIZERS"]];
    }
    flags["DFLAGS"] ~= dflags;
    flags["CXXFLAGS"] ~= cxxFlags;
}

////////////////////////////////////////////////////////////////////////////////
// D source files
////////////////////////////////////////////////////////////////////////////////

/// Returns: all source files for the compiler
auto sourceFiles()
{
    struct Sources
    {
        string[] frontend, lexer, root, glue, dmd, backend;
        string[] backendHeaders, backendC, backendObjects;
    }
    string targetCH;
    string[] targetObjs;
    if (env["TARGET_CPU"] == "X86")
    {
        targetCH = "code_x86.h";
    }
    else if (env["TARGET_CPU"] == "stub")
    {
        targetCH = "code_stub.h";
        targetObjs = ["platform_stub"];
    }
    else
    {
        assert(0, "Unknown TARGET_CPU: " ~ env["TARGET_CPU"]);
    }
    Sources sources = {
        frontend:
            dirEntries(env["D"], "*.d", SpanMode.shallow)
                .map!(e => e.name)
                .filter!(e => !e.canFind("asttypename.d", "frontend.d"))
                .array,
        lexer: [
            "console",
            "entity",
            "errors",
            "globals",
            "id",
            "identifier",
            "lexer",
            "tokens",
            "utf",
        ].map!(e => env["D"].buildPath(e ~ ".d")).chain([
            "array",
            "ctfloat",
            "file",
            "filename",
            "hash",
            "outbuffer",
            "port",
            "rmem",
            "rootobject",
            "stringtable",
        ].map!(e => env["ROOT"].buildPath(e ~ ".d"))).array,
        root:
            dirEntries(env["ROOT"], "*.d", SpanMode.shallow)
                .map!(e => e.name)
                .array,
        backend:
            dirEntries(env["C"], "*.d", SpanMode.shallow)
                .map!(e => e.name)
                .filter!(e => !e.canFind("dt.d", "obj.d"))
                .array ~ buildPath(env["C"], "elfobj.d"),
        backendHeaders: [
            // can't be built with -betterC
            "dt",
            "obj",
        ].map!(e => env["C"].buildPath(e ~ ".d")).array,
        backendC:
            // all backend files in C
            ["fp", "strtold", "tk"]
                .map!(a => env["G"].buildPath(a).objName)
                .array,
        backendObjects: ["fp", "strtold", "tk"]
                .map!(a => env["G"].buildPath(a).objName)
                .array,
    };
    sources.backendC.writeln;
    sources.dmd = sources.frontend ~ sources.backendHeaders;

    return sources;
}

/**
Downloads a file from a given URL

Params:
    to    = Location to store the file downloaded
    from  = The URL to the file to download
    tries = The number of times to try if an attempt to download fails
Returns: `true` if download succeeded
*/
bool download(string to, string from, uint tries = 3)
{
    import std.net.curl : download, HTTPStatusException;

    foreach(i; 0..tries)
    {
        try
        {
            log("Downloading %s ...", from);
            download(from, to);
            return true;
        }
        catch(HTTPStatusException e)
        {
            if (e.status == 404) throw e;
            else
            {
                log("Failed to download %s (Attempt %s of %s)", from, i + 1, tries);
                continue;
            }
        }
    }

    return false;
}

/**
Detects the host OS.

Returns: a string from `{windows, osx,linux,freebsd,openbsd,netbsd,dragonflybsd,solaris}`
*/
string detectOS()
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
        static assert(0, "Unrecognized or unsupported OS.");
}

/**
Detects the host model

Returns: 32, 64 or throws an Exception
*/
auto detectModel()
{
    string uname;
    if (detectOS == "solaris")
        uname = ["isainfo", "-n"].execute.output;
    else if (detectOS == "windows")
        uname = ["wmic", "OS", "get", "OSArchitecture"].execute.output;
    else
        uname = ["uname", "-m"].execute.output;

    if (!uname.find("x86_64", "amd64", "64-bit")[0].empty)
        return "64";
    if (!uname.find("i386", "i586", "i686", "32-bit")[0].empty)
        return "32";

    throw new Exception(`Cannot figure 32/64 model from "` ~ uname ~ `"`);
}

/// Returns: the command for querying or invoking the host C++ compiler
auto getHostCXX()
{
    version(Posix)
        return "c++";
    else version(Windows)
    {
        immutable model = detectModel;
        if (model == "32")
            return "dmc";
        else if (model == "64")
            return buildMsvcDmc.target;
        else
            assert(false, `Unknown model "` ~ model ~ `"`);
    }
    else
        static assert(false, "Unrecognized or unsupported OS.");
}

/// Returns: a string describing the type of host C++ compiler
auto getHostCXXKind()
{
    version(Posix)
    {
        auto cxxVersion = execute([getHostCXX, "--version"]).output;
        return !cxxVersion.find("gcc", "Free Software")[0].empty ? "g++" : "clang++";
    }
    else version(Windows)
        return "dmc";
    else
        static assert(false, "Unrecognized or unsupported OS.");
}

/**
Gets the absolute path of the host's dmd executable

Params:
    hostDmd = the command used to launch the host's dmd executable
Returns: a string that is the absolute path of the host's dmd executable
*/
auto getHostDMDPath(string hostDmd)
{
    version(Posix)
        return ["which", hostDmd].execute.output;
    else version(Windows)
        return ["where", hostDmd].execute.output;
    else
        static assert(false, "Unrecognized or unsupported OS.");
}

version(Windows)
{
    /**
    Gets the absolute path to the host's vshwere executable

    Params:
        outputFolder = this build's output folder
    Returns: a string that is the absolute path of the host's vswhere executable
    */
    auto getHostVSWhere(string outputFolder)
    {
        // Check if vswhere.exe can be found in the host's PATH
        const where = ["where", "vswhere"].execute;
        if (where.status == 0)
            return where.output;

        // Check if vswhere.exe is in the standard location
        const standardPath = ["cmd", "/C", "echo", `%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe`]
            .execute.output       // Execute command and return standard output
            .replace(`"`, "")     // Remove quotes surrounding the path
            .replace("\r\n", ""); // Remove trailing newline characters
        if (standardPath.exists)
            return standardPath;

        // Check if it has already been dowloaded to this build's output folder
        const outputPath = outputFolder.buildPath("vswhere").exeName;
        if (outputPath.exists)
            return outputPath;

        // try to download it
        if (download(outputPath, "https://github.com/Microsoft/vswhere/releases/download/2.5.2/vswhere.exe"))
            return outputPath;

        // Could not find or obtain vswhere.exe
        throw new Exception("Could not obtain vswhere.exe. Consider downloading it from https://github.com/Microsoft/vswhere and placing it in your PATH");
    }

    /**
    Gets the absolute path to the host's MSVC bin directory

    Params:
        model   = a string describing the host's model, "64" or "32"
        vswhere = a string that is the path to the vswhere executable
    Returns: a string that is the absolute path to the host's MSVC bin directory
    */
    auto getHostMSVCBinDir(string model, string vswhere)
    {
        // See https://github.com/Microsoft/vswhere/wiki/Find-VC

        const vsInstallPath = [vswhere, "-latest", "-products", "*", "-requires",
            "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"].execute.output
            .replace("\r\n", "");

        if (!vsInstallPath.exists)
            throw new Exception("Could not locate the Visual Studio installation directory");

        const vcVersionFile = vsInstallPath.buildPath("VC", "Auxiliary", "Build", "Microsoft.VCToolsVersion.default.txt");
        if (!vcVersionFile.exists)
            throw new Exception(`Could not locate the Visual C++ version file "%s"`.format(vcVersionFile));

        const vcVersion = vcVersionFile.readText().replace("\r\n", "");
        const vcArch = model == "64" ? "x64" : "x86";
        const vcPath = vsInstallPath.buildPath("VC", "Tools", "MSVC", vcVersion, "bin", "Host" ~ vcArch, vcArch);
        if (!vcPath.exists)
            throw new Exception("Could not locate the Visual C++ installation directory");

        return vcPath;
    }
}

/**
Add the executable filename extension to the given `name` for the current OS.

Params:
    name = the name to append the file extention to
*/
auto exeName(T)(T name)
{
    version(Windows)
        return name ~ ".exe";
    return name;
}

/**
Add the object file extension to the given `name` for the current OS.

Params:
    name = the name to append the file extention to
*/
auto objName(T)(T name)
{
    version(Windows)
        return name ~ ".obj";
    return name ~ ".o";
}

/**
Add the library file extension to the given `name` for the current OS.

Params:
    name = the name to append the file extention to
*/
auto libName(T)(T name)
{
    version(Windows)
        return name ~ ".dll";
    return name ~ ".a";
}

/**
Add additional make-like assignments to the environment
e.g. ./build.d ARGS=foo -> sets the "ARGS" internal environment variable to "foo"

Params:
    args = the command-line arguments from which the assignments will be parsed
*/
void args2Environment(ref string[] args)
{
    bool tryToAdd(string arg)
    {
        if (!arg.canFind("="))
            return false;

        auto sp = arg.splitter("=");
        environment[sp.front] = sp.dropOne.front;
        return true;
    }
    args = args.filter!(a => !tryToAdd(a)).array;
}

/**
Checks whether the environment already contains a value for key and if so, sets
the found value to the new environment object.
Otherwise uses the `default_` value as fallback.

Params:
    env = environment to write the check to
    key = key to check for existence and write into the new env
    default_ = fallback value if the key doesn't exist in the global environment
*/
auto getDefault(ref string[string] env, string key, string default_)
{
    if (key in environment)
        env[key] = environment[key];
    else
        env[key] = default_;

    return env[key];
}

////////////////////////////////////////////////////////////////////////////////
// Mini build system
////////////////////////////////////////////////////////////////////////////////

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
    if (force)
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
A dependency has one or more sources and yields one or more targets.
It knows how to build these target by invoking either the external command or
the commandFunction.

If a run fails, the entire build stops.

Command strings support the Make-like $@ (target path) and $< (source path)
shortcut variables.
*/
struct Dependency
{
    string target; // path to the resulting target file (if target is used, it will set targets)
    string[] targets; // list of all target files
    string[] sources; // list of all source files
    string[] rebuildSources; // Optional list of files that trigger a rebuild of this dependency
    string[] command; // the dependency command
    void delegate() commandFunction; // a custom dependency command which gets called instead of command
    string name; // name of the dependency that is e.g. written to the CLI when it's executed
    string[] trackSources;

    /**
    Executes the dependency
    */
    auto run()
    {
        // allow one or multiple targets
        if (target !is null)
            targets = [target];

        if (targets.isUpToDate(sources, [thisBuildScript], rebuildSources))
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

/**
Logging primitive

Params:
    args = the data to write to the log
*/
auto log(T...)(T args)
{
    if (verbose)
        writefln(args);
}

/**
Run a command and optionally log the invocation

Params:
    args = the command and command arguments to execute
*/
auto run(T)(T args)
{
    log("Run: %s", args.join(" "));
    return execute(args, null, Config.none, size_t.max, srcDir);
}

/**
Wrapper around execute that logs the execution
and throws an exception for a non-zero exit code.

Params:
    args = the command and command arguments to execute
*/
auto runCanThrow(T)(T args)
{
    auto res = run(args);
    enforce(!res.status, res.output);
    return res.output;
}
