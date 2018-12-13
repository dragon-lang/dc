module build.visualstudio;

import std.file;

import build.log;
import build.error;
import build.proc;

/**
Tries to find vswhere in PATH or in the standard install location

Returns: a string that is the absolute path of the host's vswhere executable
*/
string tryFindVSWhere()
{
    import std.algorithm : canFind;
    import std.string : strip;
    import std.process : environment;
    import build.string : firstLine, sliceInsideQuotes;

    {
        verbosef("looking for 'vswhere' in PATH...");
        const result = execute(["where", "vswhere"]);
        if (result.status == 0)
        {
            auto text = result.output.strip;
            if (text.length > 0)
            {
                auto vswhere = text.firstLine.strip();
                logf("found vswhere '%s'", vswhere);
                return vswhere;
            }
        }
    }

    // Check if vswhere.exe is in the standard location
    auto programFilesDirs = [`C:\Program Files (x86)`];
    {
        auto result = environment.get(`%ProgramFiles(x86)`, null);
        if (result && !programFilesDirs.canFind(result))
            programFilesDirs ~= result;
    }
    foreach (dir; programFilesDirs)
    {
        const vswhere = dir ~ `\Microsoft Visual Studio\Installer\vswhere.exe`;
        verbosef("looking for 'vswhere' in '%s'...", vswhere);
        if (exists(vswhere))
        {
            logf("found vswhere '%s'", vswhere);
            return vswhere;
        }
    }
    return null;
}


/**
Determine which technique we are going to use to find visual studio.
1. use vswhere

Params:
    vswhereDownloadPath = if not null, it will try to download vswhere to this path

*/
VisualStudioFinder getVisualStudioFinder(string vswhereDownloadPath)
{
    import std.path : buildPath;
    import build.download : tryDownload;

    // first check if we've already downloaded vswhere
    string vswhereDownloadFile = null;
    if (vswhereDownloadPath)
    {
        vswhereDownloadFile = buildPath(vswhereDownloadPath, "vswhere.exe");
        if (exists(vswhereDownloadFile))
        {
            logf("vswhere has already been downloaded '%s'", vswhereDownloadPath);
            return new VSWhereFinder(vswhereDownloadFile);
        }
    }
    {
        auto vswhere = tryFindVSWhere();
        if (vswhere)
        {
            return new VSWhereFinder(vswhere);
        }
    }

    // TODO: should probably try backup methods before attempting to download vswhere

    string errorAction;
    if (vswhereDownloadPath)
    {
        if (tryDownload(vswhereDownloadFile,
            "https://github.com/Microsoft/vswhere/releases/download/2.5.2/vswhere.exe"))
        {
            logf("downloaded vswhere '%s'", vswhereDownloadFile);
            return new VSWhereFinder(vswhereDownloadFile);
        }
    }
    throw fatal("Could not find%s 'vswhere.exe'. Consider downloading it from https://github.com/Microsoft/vswhere and placing it in your PATH", vswhereDownloadPath ? " or download" : "");
}

class VisualStudioFinder
{
    
}

class VSWhereFinder : VisualStudioFinder
{
    string exePath;
    this(string exePath)
    {
        this.exePath = exePath;
    }
}
