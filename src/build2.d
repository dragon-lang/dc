#!/usr/bin/env rund
//!debug
//!debugSymbols
import std.path, std.file, std.stdio, std.process;
auto relpath(string path)
{
    return buildNormalizedPath(__FILE_FULL_PATH__.dirName, path);
}
int main(string[] args)
{
    auto dmakelib = relpath("../../dmakelib");
    if (!exists(dmakelib))
    {
        writefln("Error: dmakelib repository '%s' does not exist, please clone it");
        return 1;
    }
    // TODO: check version of dmakelib
    auto proc = spawnProcess(relpath("buildWithLibs.d") ~ args[1 .. $]);
    return wait(proc);
}