/**
 * Compiler implementation of the
 * $(LINK2 http://www.dlang.org, D programming language).
 *
 * This modules defines the help texts for the CLI options offered by DMD.
 * This file is not shared with other compilers which use the DMD front-end.
 * However, this file will be used to generate the
 * $(LINK2 https://dlang.org/dmd-linux.html, online documentation) and MAN pages.
 *
 * Copyright:   Copyright (C) 1999-2018 by The D Language Foundation, All Rights Reserved
 * Authors:     $(LINK2 http://www.digitalmars.com, Walter Bright)
 * License:     $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source:      $(LINK2 https://github.com/dlang/dmd/blob/master/src/dmd/cli.d, _cli.d)
 * Documentation:  https://dlang.org/phobos/dmd_cli.html
 * Coverage:    https://codecov.io/gh/dlang/dmd/src/master/src/dmd/cli.d
 */
module dmd.cli;

/// Bit decoding of the TargetOS
enum TargetOS
{
    all = int.max,
    linux = 1,
    windows = 2,
    macOS = 4,
    freeBSD = 8,
    solaris = 16,
    dragonFlyBSD = 32,
}

// Detect the current TargetOS
version (linux)
{
    private enum targetOS = TargetOS.linux;
}
else version(Windows)
{
    private enum targetOS = TargetOS.windows;
}
else version(OSX)
{
    private enum targetOS = TargetOS.macOS;
}
else version(FreeBSD)
{
    private enum targetOS = TargetOS.freeBSD;
}
else version(DragonFlyBSD)
{
    private enum targetOS = TargetOS.dragonFlyBSD;
}
else version(Solaris)
{
    private enum targetOS = TargetOS.solaris;
}
else
{
    private enum targetOS = TargetOS.all;
}

/**
Checks whether `os` is the current $(LREF TargetOS).
For `TargetOS.all` it will always return true.

Params:
    os = $(LREF TargetOS) to check

Returns: true iff `os` contains the current targetOS.
*/
bool isCurrentTargetOS(TargetOS os)
{
    return (os & targetOS) > 0;
}

/**
Contains all available CLI $(LREF Usage.Option)s.

See_Also: $(LREF Usage.Option)
*/
struct Usage
{
    /**
    * Representation of a CLI `Option`
    *
    * The DDoc description `ddoxText` is only available when compiled with `-version=DdocOptions`.
    */
    struct Option
    {
        string flag; /// The CLI flag without leading `-`, e.g. `color`
        string helpText; /// A detailed description of the flag
        TargetOS os = TargetOS.all; /// For which `TargetOS` the flags are applicable

        // Needs to be version-ed to prevent the text ending up in the binary
        // See also: https://issues.dlang.org/show_bug.cgi?id=18238
        version(DdocOptions) string ddocText; /// Detailed description of the flag (in Ddoc)

        /**
        * Params:
        *  flag = CLI flag without leading `-`, e.g. `color`
        *  helpText = detailed description of the flag
        *  os = for which `TargetOS` the flags are applicable
        *  ddocText = detailed description of the flag (in Ddoc)
        */
        this(string flag, string helpText, TargetOS os = TargetOS.all)
        {
            this.flag = flag;
            this.helpText = helpText;
            version(DdocOptions) this.ddocText = helpText;
            this.os = os;
        }

        /// ditto
        this(string flag, string helpText, string ddocText, TargetOS os = TargetOS.all)
        {
            this.flag = flag;
            this.helpText = helpText;
            version(DdocOptions) this.ddocText = ddocText;
            this.os = os;
        }
    }

    /// Returns all available CLI options
    static immutable options = [
        Option("allinst",
            "generate code for all template instantiations"
        ),
        Option("betterC",
            "omit generating some runtime information and helper functions",
            "Adjusts the compiler to implement D as a $(LINK2 $(ROOT_DIR)spec/betterc.html, better C):
            $(UL
                $(LI Predefines `D_BetterC` $(LINK2 $(ROOT_DIR)spec/version.html#predefined-versions, version).)
                $(LI $(LINK2 $(ROOT_DIR)spec/expression.html#AssertExpression, Assert Expressions), when they fail,
                call the C runtime library assert failure function
                rather than a function in the D runtime.)
                $(LI $(LINK2 $(ROOT_DIR)spec/arrays.html#bounds, Array overflows)
                call the C runtime library assert failure function
                rather than a function in the D runtime.)
                $(LI $(LINK2 spec/statement.html#final-switch-statement/, Final switch errors)
                call the C runtime library assert failure function
                rather than a function in the D runtime.)
                $(LI Does not automatically link with phobos runtime library.)
                $(UNIX
                $(LI Does not generate Dwarf `eh_frame` with full unwinding information, i.e. exception tables
                are not inserted into `eh_frame`.)
                )
                $(LI Module constructors and destructors are not generated meaning that
                $(LINK2 $(ROOT_DIR)spec/class.html#StaticConstructor, static) and
                $(LINK2 $(ROOT_DIR)spec/class.html#SharedStaticConstructor, shared static constructors) and
                $(LINK2 $(ROOT_DIR)spec/class.html#StaticDestructor, destructors)
                will not get called.)
                $(LI `ModuleInfo` is not generated.)
                $(LI $(LINK2 $(ROOT_DIR)phobos/object.html#.TypeInfo, `TypeInfo`)
                instances will not be generated for structs.)
            )",
        ),
        Option("boundscheck=[on|safeonly|off]",
            "bounds checks on, in @safe only, or off",
            `Controls if bounds checking is enabled.
                $(UL
                    $(LI $(I on): Bounds checks are enabled for all code. This is the default.)
                    $(LI $(I safeonly): Bounds checks are enabled only in $(D @safe) code.
                                        This is the default for $(SWLINK -release) builds.)
                    $(LI $(I off): Bounds checks are disabled completely (even in $(D @safe)
                                   code). This option should be used with caution and as a
                                   last resort to improve performance. Confirm turning off
                                   $(D @safe) bounds checks is worthwhile by benchmarking.)
                )`
        ),
        Option("c",
            "compile only, do not link"
        ),
        Option("check=[assert|bounds|in|invariant|out|switch][=[on|off]]",
            "Enable or disable specific checks",
            `Overrides default, -boundscheck, -release and -unittest options to enable or disable specific checks.
                $(UL
                    $(LI $(B assert): assertion checking)
                    $(LI $(B bounds): array bounds)
                    $(LI $(B in): in contracts)
                    $(LI $(B invariant): class/struct invariants)
                    $(LI $(B out): out contracts)
                    $(LI $(B switch): switch default)
                )
                $(UL
                    $(LI $(B on) or not specified: specified check is enabled.)
                    $(LI $(B off): specified check is disabled.)
                )`
        ),
        Option("checkaction=D|C|halt",
            "behavior on assert/boundscheck/finalswitch failure",
            `Sets behavior when an assert fails, and array boundscheck fails,
             or a final switch errors.
                $(UL
                    $(LI $(B D): Default behavior, which throws an unrecoverable $(D Error).)
                    $(LI $(B C): Calls the C runtime library assert failure function.)
                    $(LI $(B halt): Executes a halt instruction, terminating the program.)
                )`
        ),
        Option("color",
            "turn colored console output on"
        ),
        Option("color=[on|off|auto]",
            "force colored console output on or off, or only when not redirected (default)",
            `Show colored console output. The default depends on terminal capabilities.
            $(UL
                $(LI $(B auto): use colored output if a tty is detected (default))
                $(LI $(B on): always use colored output.)
                $(LI $(B off): never use colored output.)
            )`
        ),
        Option("conf=<filename>",
            "use config file at filename"
        ),
        Option("cov",
            "do code coverage analysis"
        ),
        Option("cov=<nnn>",
            "require at least nnn% code coverage",
            `Perform $(LINK2 $(ROOT_DIR)code_coverage.html, code coverage analysis) and generate
            $(TT .lst) file with report.)
---
dmd -cov -unittest myprog.d
---
            `,
        ),
        Option("D",
            "generate documentation",
            `$(P Generate $(LINK2 $(ROOT_DIR)spec/ddoc.html, documentation) from source.)
            $(P Note: mind the $(LINK2 $(ROOT_DIR)spec/ddoc.html#security, security considerations).)
            `,
        ),
        Option("Dd<directory>",
            "write documentation file to directory",
            `Write documentation file to $(I directory) . $(SWLINK -op)
            can be used if the original package hierarchy should
            be retained`,
        ),
        Option("Df<filename>",
            "write documentation file to filename"
        ),
        Option("d",
            "silently allow deprecated features and symbols",
            `Silently allow $(DDLINK deprecate,deprecate,deprecated features) and use of symbols with
            $(DDSUBLINK $(ROOT_DIR)spec/attribute, deprecated, deprecated attributes).`,
        ),
        Option("dw",
            "issue a message when deprecated features or symbols are used (default)"
        ),
        Option("de",
            "issue an error when deprecated features or symbols are used (halt compilation)"
        ),
        Option("debug",
            "compile in debug code",
            `Compile in $(LINK2 spec/version.html#debug, debug) code`,
        ),
        Option("debug=<level>",
            "compile in debug code <= level",
            `Compile in $(LINK2 spec/version.html#debug, debug level) &lt;= $(I level)`,
        ),
        Option("debug=<ident>",
            "compile in debug code identified by ident",
            `Compile in $(LINK2 spec/version.html#debug, debug identifier) $(I ident)`,
        ),
        Option("debuglib=<name>",
            "set symbolic debug library to name",
            `Link in $(I libname) as the default library when
            compiling for symbolic debugging instead of $(B $(LIB)).
            If $(I libname) is not supplied, then no default library is linked in.`
        ),
        Option("defaultlib=<name>",
            "set default library to name",
            `Link in $(I libname) as the default library when
            not compiling for symbolic debugging instead of $(B $(LIB)).
            If $(I libname) is not supplied, then no default library is linked in.`,
        ),
        Option("deps",
            "print module dependencies (imports/file/version/debug/lib)"
        ),
        Option("deps=<filename>",
            "write module dependencies to filename (only imports)",
            `Without $(I filename), print module dependencies
            (imports/file/version/debug/lib).
            With $(I filename), write module dependencies as text to $(I filename)
            (only imports).`,
        ),
        Option("dip25",
            "implement https://github.com/dlang/DIPs/blob/master/DIPs/archive/DIP25.md",
            "implement $(LINK2 https://github.com/dlang/DIPs/blob/master/DIPs/archive/DIP25.md, DIP25 (Sealed references))"
        ),
        Option("dip1000",
            "implement https://github.com/dlang/DIPs/blob/master/DIPs/DIP1000.md",
            "implement $(LINK2 https://github.com/dlang/DIPs/blob/master/DIPs/DIP1000.md, DIP1000 (Scoped Pointers))"
        ),
        Option("dip1008",
            "implement https://github.com/dlang/DIPs/blob/master/DIPs/DIP1008.md",
            "implement $(LINK2 https://github.com/dlang/DIPs/blob/master/DIPs/DIP1008.md, DIP1008 (@nogc Throwable))"
        ),
        Option("fPIC",
            "generate position independent code",
            TargetOS.all & ~(TargetOS.windows | TargetOS.macOS)
        ),
        Option("g",
            "add symbolic debug info",
            `$(WINDOWS
                Add CodeView symbolic debug info with
                $(LINK2 $(ROOT_DIR)spec/abi.html#codeview, D extensions)
                for debuggers such as
                $(LINK2 http://ddbg.mainia.de/releases.html, Ddbg)
            )
            $(UNIX
                Add symbolic debug info in Dwarf format
                for debuggers such as
                $(D gdb)
            )`,
        ),
        Option("gf",
            "emit debug info for all referenced types"
        ),
        Option("gs",
            "always emit stack frame"
        ),
        Option("gx",
            "add stack stomp code",
            `Adds stack stomp code, which overwrites the stack frame memory upon function exit.`,
        ),
        Option("H",
            "generate 'header' file",
            `Generate $(RELATIVE_LINK2 $(ROOT_DIR)interface-files, D interface file)`,
        ),
        Option("Hd=<directory>",
            "write 'header' file to directory",
            `Write D interface file to $(I dir) directory. $(SWLINK -op)
            can be used if the original package hierarchy should
            be retained.`,
        ),
        Option("Hf=<filename>",
            "write 'header' file to filename"
        ),
        Option("-help",
            "print help and exit"
        ),
        Option("I=<directory>",
            "look for imports also in directory"
        ),
        Option("i[=<pattern>]",
            "include imported modules in the compilation",
            q"{$(P Enables "include imports" mode, where the compiler will include imported
             modules in the compilation, as if they were given on the command line. By default, when
             this option is enabled, all imported modules are included except those in
             druntime/phobos. This behavior can be overriden by providing patterns via `-i=<pattern>`.
             A pattern of the form `-i=<package>` is an "inclusive pattern", whereas a pattern
             of the form `-i=-<package>` is an "exclusive pattern". Inclusive patterns will include
             all module's whose names match the pattern, whereas exclusive patterns will exclude them.
             For example. all modules in the package `foo.bar` can be included using `-i=foo.bar` or excluded
             using `-i=-foo.bar`. Note that each component of the fully qualified name must match the
             pattern completely, so the pattern `foo.bar` would not match a module named `foo.barx`.)

             $(P The default behavior of excluding druntime/phobos is accomplished by internally adding a
             set of standard exclusions, namely, `-i=-std -i=-core -i=-etc -i=-object`. Note that these
             can be overriden with `-i=std -i=core -i=etc -i=object`.)

             $(P When a module matches multiple patterns, matches are prioritized by their component length, where
             a match with more components takes priority (i.e. pattern `foo.bar.baz` has priority over `foo.bar`).)

             $(P By default modules that don't match any pattern will be included. However, if at
             least one inclusive pattern is given, then modules not matching any pattern will
             be excluded. This behavior can be overriden by usig `-i=.` to include by default or `-i=-.` to
             exclude by default.)

             $(P Note that multiple `-i=...` options are allowed, each one adds a pattern.)}"
        ),
        Option("ignore",
            "ignore unsupported pragmas"
        ),
        Option("inline",
            "do function inlining",
            `Inline functions at the discretion of the compiler.
            This can improve performance, at the expense of making
            it more difficult to use a debugger on it.`,
        ),
        Option("J=<directory>",
            "look for string imports also in directory",
            `Where to look for files for
            $(LINK2 $(ROOT_DIR)spec/expression.html#ImportExpression, $(I ImportExpression))s.
            This switch is required in order to use $(I ImportExpression)s.
            $(I path) is a ; separated
            list of paths. Multiple $(B -J)'s can be used, and the paths
            are searched in the same order.`,
        ),
        Option("L=<linkerflag>",
            "pass linkerflag to link",
            `Pass $(I linkerflag) to the
            $(WINDOWS linker $(OPTLINK))
            $(UNIX linker), for example,`,
        ),
        Option("lib",
            "generate library rather than object files",
            `Generate library file as output instead of object file(s).
            All compiled source files, as well as object files and library
            files specified on the command line, are inserted into
            the output library.
            Compiled source modules may be partitioned into several object
            modules to improve granularity.
            The name of the library is taken from the name of the first
            source module to be compiled. This name can be overridden with
            the $(SWLINK -of) switch.`,
        ),
        Option("m32",
            "generate 32 bit code",
            `$(UNIX Compile a 32 bit executable. This is the default for the 32 bit dmd.)
            $(WINDOWS Compile a 32 bit executable. This is the default.
            The generated object code is in OMF and is meant to be used with the
            $(LINK2 http://www.digitalmars.com/download/freecompiler.html, Digital Mars C/C++ compiler)).`,
            (TargetOS.all & ~TargetOS.dragonFlyBSD)  // available on all OS'es except DragonFly, which does not support 32-bit binaries
        ),
        Option("m32mscoff",
            "generate 32 bit code and write MS-COFF object files",
            TargetOS.windows
        ),
        Option("m64",
            "generate 64 bit code",
            `$(UNIX Compile a 64 bit executable. This is the default for the 64 bit dmd.)
            $(WINDOWS The generated object code is in MS-COFF and is meant to be used with the
            $(LINK2 https://msdn.microsoft.com/en-us/library/dd831853(v=vs.100).aspx, Microsoft Visual Studio 10)
            or later compiler.`,
        ),
        Option("main",
            "add default main() (e.g. for unittesting)",
            `Add a default $(D main()) function when compiling. This is useful when
            unittesting a library, as it enables running the unittests
            in a library without having to manually define an entry-point function.`,
        ),
        Option("man",
            "open web browser on manual page",
            `$(WINDOWS
                Open default browser on this page
            )
            $(LINUX
                Open browser specified by the $(B BROWSER)
                environment variable on this page. If $(B BROWSER) is
                undefined, $(B x-www-browser) is assumed.
            )
            $(FREEBSD
                Open browser specified by the $(B BROWSER)
                environment variable on this page. If $(B BROWSER) is
                undefined, $(B x-www-browser) is assumed.
            )
            $(OSX
                Open browser specified by the $(B BROWSER)
                environment variable on this page. If $(B BROWSER) is
                undefined, $(B Safari) is assumed.
            )`,
        ),
        Option("map",
            "generate linker .map file",
            `Generate a $(TT .map) file`,
        ),
        Option("mcpu=<id>",
            "generate instructions for architecture identified by 'id'",
            `Set the target architecture for code generation,
            where:
            $(DL
            $(DT ?)$(DD list alternatives)
            $(DT baseline)$(DD the minimum architecture for the target platform (default))
            $(DT avx)$(DD
            generate $(LINK2 https://en.wikipedia.org/wiki/Advanced_Vector_Extensions, AVX)
            instructions instead of $(LINK2 https://en.wikipedia.org/wiki/Streaming_SIMD_Extensions, SSE)
            instructions for vector and floating point operations.
            Not available for 32 bit memory models other than OSX32.
            )
            $(DT native)$(DD use the architecture the compiler is running on)
            )`,
        ),
        Option("mcpu=?",
            "list all architecture options"
        ),
        Option("mixin=<filename>",
            "expand and save mixins to file specified by <filename>"
        ),
        Option("mscrtlib=<name>",
            "MS C runtime library to reference from main/WinMain/DllMain",
            "If building MS-COFF object files with -m64 or -m32mscoff, embed a reference to
            the given C runtime library $(I libname) into the object file containing `main`,
            `DllMain` or `WinMain` for automatic linking. The default is $(TT libcmt)
            (release version with static linkage), the other usual alternatives are
            $(TT libcmtd), $(TT msvcrt) and $(TT msvcrtd).
            If $(I libname) is empty, no C runtime library is automatically linked in.",
            TargetOS.windows,
        ),
        Option("mv=<package.module>=<filespec>",
            "use <filespec> as source file for <package.module>",
            `Use $(I path/filename) as the source file for $(I package.module).
            This is used when the source file path and names are not the same
            as the package and module hierarchy.
            The rightmost components of the  $(I path/filename) and $(I package.module)
            can be omitted if they are the same.`,
        ),
        Option("noboundscheck",
            "no array bounds checking (deprecated, use -boundscheck=off)",
            `Turns off all array bounds checking, even for safe functions. $(RED Deprecated
            (use $(TT $(SWLINK -boundscheck)=off) instead).)`,
        ),
        Option("O",
            "optimize",
            `Optimize generated code. For fastest executables, compile
            with the $(TT $(SWLINK -O) $(SWLINK -release) $(SWLINK -inline) $(SWLINK -boundscheck)=off)
            switches together.`,
        ),
        Option("o-",
            "do not write object file",
            `Suppress generation of object file. Useful in
            conjuction with $(SWLINK -D) or $(SWLINK -H) flags.`
        ),
        Option("od=<directory>",
            "write object & library files to directory",
            `Write object files relative to directory $(I objdir)
            instead of to the current directory. $(SWLINK -op)
            can be used if the original package hierarchy should
            be retained`,
        ),
        Option("of=<filename>",
            "name output file to filename",
            `Set output file name to $(I filename) in the output
            directory. The output file can be an object file,
            executable file, or library file depending on the other
            switches.`
        ),
        Option("op",
            "preserve source path for output files",
            `Normally the path for $(B .d) source files is stripped
            off when generating an object, interface, or Ddoc file
            name. $(SWLINK -op) will leave it on.`,
        ),
        Option("profile",
            "profile runtime performance of generated code"
        ),
        Option("profile=gc",
            "profile runtime allocations",
            `$(LINK2 http://www.digitalmars.com/ctg/trace.html, profile)
            the runtime performance of the generated code.
            $(UL
                $(LI $(B gc): Instrument calls to memory allocation and write a report
                to the file $(TT profilegc.log) upon program termination.)
            )`,
        ),
        Option("release",
            "compile release version",
            `Compile release version, which means not emitting run-time
            checks for contracts and asserts. Array bounds checking is not
            done for system and trusted functions, and assertion failures
            are undefined behaviour.`
        ),
        Option("run <srcfile>",
            "compile, link, and run the program srcfile",
            `Compile, link, and run the program $(I srcfile) with the
            rest of the
            command line, $(I args...), as the arguments to the program.
            No .$(OBJEXT) or executable file is left behind.`
        ),
        Option("shared",
            "generate shared library (DLL)",
            `$(UNIX Generate shared library)
             $(WINDOWS Generate DLL library)`,
        ),
        Option("transition=<id>",
            "help with language change identified by 'id'",
            `Show additional info about language change identified by $(I id)`,
        ),
        Option("transition=?",
            "list all language changes"
        ),
        Option("unittest",
            "compile in unit tests",
            `Compile in $(LINK2 spec/unittest.html, unittest) code, turns on asserts, and sets the
             $(D unittest) $(LINK2 spec/version.html#PredefinedVersions, version identifier)`,
        ),
        Option("v",
            "verbose",
            `Enable verbose output for each compiler pass`,
        ),
        Option("vcolumns",
            "print character (column) numbers in diagnostics"
        ),
        Option("verrors=<num>",
            "limit the number of error messages (0 means unlimited)"
        ),
        Option("verrors=spec",
            "show errors from speculative compiles such as __traits(compiles,...)"
        ),
        Option("-version",
            "print compiler version and exit"
        ),
        Option("version=<level>",
            "compile in version code >= level",
            `Compile in $(LINK2 $(ROOT_DIR)spec/version.html#version, version level) >= $(I level)`,
        ),
        Option("version=<ident>",
            "compile in version code identified by ident",
            `Compile in $(LINK2 $(ROOT_DIR)spec/version.html#version, version identifier) $(I ident)`
        ),
        Option("vgc",
            "list all gc allocations including hidden ones"
        ),
        Option("vtls",
            "list all variables going into thread local storage"
        ),
        Option("w",
            "warnings as errors (compilation will halt)",
            `Enable $(LINK2 $(ROOT_DIR)articles/warnings.html, warnings)`
        ),
        Option("wi",
            "warnings as messages (compilation will continue)",
            `Enable $(LINK2 $(ROOT_DIR)articles/warnings.html, informational warnings (i.e. compilation
            still proceeds normally))`,
        ),
        Option("X",
            "generate JSON file"
        ),
        Option("Xf=<filename>",
            "write JSON file to filename"
        ),
    ];

    /// Representation of a CLI transition
    struct Transition
    {
        string bugzillaNumber; /// bugzilla issue number (if existent)
        string name; /// name of the transition
        string paramName; // internal transition parameter name
        string helpText; // detailed description of the transition
    }

    /// Returns all available transitions
    static immutable transitions = [
        Transition("3449", "field", "vfield",
            "list all non-mutable fields which occupy an object instance"),
        Transition("10378", "import", "bug10378",
            "revert to single phase name lookup"),
        Transition("14246", "dtorfields", "dtorFields",
            "destruct fields of partially constructed objects"),
        Transition(null, "checkimports", "check10378",
            "give deprecation messages about 10378 anomalies"),
        Transition("14488", "complex", "vcomplex",
            "give deprecation messages about all usages of complex or imaginary types"),
        Transition("16997", "intpromote", "fix16997",
            "fix integral promotions for unary + - ~ operators"),
        Transition(null, "tls", "vtls",
            "list all variables going into thread local storage"),
        Transition(null, "fixAliasThis", "fixAliasThis",
            "when a symbol is resolved, check alias this scope before going to upper scopes"),
        Transition(null, "markdown", "markdown",
            "enable Markdown replacements in Ddoc"),
        Transition(null, "vmarkdown", "vmarkdown",
            "list instances of Markdown replacements in Ddoc"),
    ];
}

/**
Formats the `Options` for CLI printing.
*/
struct CLIUsage
{
    /**
    Returns a string of all available CLI options for the current targetOS.
    Options are separated by newlines.
    */
    static string usage()
    {
        enum maxFlagLength = 18;
        enum s = () {
            string buf;
            foreach (option; Usage.options)
            {
                if (option.os.isCurrentTargetOS)
                {
                    buf ~= "  -";
                    buf ~= option.flag;
                    // emulate current behavior of DMD
                    if (option.flag == "defaultlib=<name>")
                    {
                            buf ~= "\n                    ";
                    }
                    else if (option.flag.length <= maxFlagLength)
                    {
                        foreach (i; 0 .. maxFlagLength - option.flag.length - 1)
                            buf ~= " ";
                    }
                    else
                    {
                            buf ~= "  ";
                    }
                    buf ~= option.helpText;
                    buf ~= "\n";
                }
            }
            return buf;
        }();
        return s;
    }

    /// CPU architectures supported -mcpu=id
    static string mcpu()
    {
        return "
CPU architectures supported by -mcpu=id:
  =?             list information on all architecture choices
  =baseline      use default architecture as determined by target
  =avx           use AVX 1 instructions
  =avx2          use AVX 2 instructions
  =native        use CPU architecture that this compiler is running on
";
    }

    /// Language changes listed by -transition=id
    static string transitionUsage()
    {
        enum maxFlagLength = 20;
        enum s = () {
            auto buf = "Language changes listed by -transition=id:
";
            auto allTransitions = [Usage.Transition(null, "all", null,
                "list information on all language changes")] ~ Usage.transitions;
            foreach (t; allTransitions)
            {
                buf ~= "  =";
                buf ~= t.name;
                auto lineLength = 3 + t.name.length;
                if (t.bugzillaNumber !is null)
                {
                    buf ~= "," ~ t.bugzillaNumber;
                    lineLength += t.bugzillaNumber.length + 1;
                }
                foreach (i; 0 .. maxFlagLength - lineLength)
                    buf ~= " ";
                buf ~= t.helpText;
                buf ~= "\n";
            }
            return buf;
        }();
        return s;
    }
}
