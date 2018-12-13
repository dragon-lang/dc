module build.string;

auto firstLine(T)(T str)
{
/*
    import std.algorithm : until;
    import std.string : stripRight;

    // THIS ISN'T WORKING, `.until` returns a type that stripRight doesn't understand
    return str.until("\n").stripRight("\r");
*/
    import std.string : indexOf, stripRight;

    auto newlineIndex = str.indexOf("\n");
    if (newlineIndex < 0)
        return str;
    return str[0 .. newlineIndex].stripRight("\r");
}

auto sliceInsideQuotes(inout(char)[] str)
{
    import std.exception : enforce;
    import std.string : indexOf;
    import std.format : format;

    auto firstQuote = str.indexOf(`"`);
    enforce(firstQuote >=0, format("string did not contain quotes '%s'", str));
    auto result = str[firstQuote + 1 .. $];
    auto secondQuote = result.indexOf(`"`);
    enforce(secondQuote >= 0, format("string did not end with quote '%s'", str));
    return result[0 .. secondQuote];
}
