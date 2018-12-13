module build.download;

import build.log;

/**
Downloads a file from a given URL

Params:
    to       = Location to store the file downloaded
    from     = The URL to the file to download
    attempts = The number of times to attempt the download
Returns: `true` if download succeeded
*/
bool tryDownload(string to, string from, uint attempts = 3)
{
    import std.net.curl : download, HTTPStatusException;

    for (auto attempt = 1; attempt <= attempts; attempt++)
    {
        try
        {
            logf("Attempt %s to download %s ...", from);
            download(from, to);
            return true;
        }
        catch(HTTPStatusException e)
        {
            if (e.status == 404) throw e;
            else
            {
                logf("Failed to download %s (Attempt %s of %s)", from, attempt, attempts);
                continue;
            }
        }
    }

    return false;
}
