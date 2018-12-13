#!/usr/bin/env rund
//!debug
//!debugSymbols

import stepbuild;

int main(string[] args)
{
    Config config = {
        envAllowed: ["PATH", "DFLAGS"],
        steps: [
            new Command("hello", ["dmd", "hello.d"]),
        ]
    };

    filterEnv(config.envAllowed);
    dumpEnv();

    foreach (arg; args)
    {
        
    }

    return 0;
}