#!/usr/bin/env rund
import core.stdc.stdlib : exit;
import std.string;
import std.path;
import std.file;
import std.stdio;
import std.process;

auto scriptRelativePath(string path)
{
    if (isAbsolute(path))
        return path;
    return buildPath(dirName(__FILE_FULL_PATH__), path);
}

int main(string[] args)
{
    run(["git", "fetch", "https://github.com/marler8997/dc", "master:merge_from_dmd"]);
    run(["git", "checkout", "merge_from_dmd"]);
    run(["git", "fetch", "https://github.com/dlang/dmd"]);
    //auto mergeBase = runGetOutput(["git", "merge-base", "master_dmd", "master_update"], 80).strip();
    //writefln("mergeBase '%s'", mergeBase);
    run(["git", "merge", "FETCH_HEAD"]);
    run(["git", "push", "origin", "merge_from_dmd"]);
    return 0;
}

// TODO: move these to a common library
auto tryRun(string[] args)
{
    writefln("[RUN] %s", escapeShellCommand(args));
    auto proc = spawnProcess(args);
    return wait(proc);
}
void run(string[] args)
{
    auto exitCode = tryRun(args);
    if (exitCode != 0)
    {
        writefln("Error: last command exited with code %s", exitCode);
        exit(1);
    }
}

string runGetOutput(string[] args, size_t readChunkSize = 500)
{
    writefln("[RUN-GET-OUTPUT] %s", escapeShellCommand(args));
    auto pipes = pipeProcess(args);
    auto exitCode = wait(pipes.pid);
    if (exitCode != 0)
    {
        writefln("Error: last command exited with code %s", exitCode);
        exit(1);
    }
    string output;
    foreach (chunk; pipes.stdout.byChunk(readChunkSize)) output ~= chunk;
    return output;
}
