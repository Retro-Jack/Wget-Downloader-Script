@ECHO off
CLS
IF [%1] == [] GOTO missing_arg
IF [%2] == [] GOTO missing_arg
IF NOT EXIST %2 GOTO bad_dir

ECHO About to download %1 to %2
ECHO.
PAUSE

CLS
CD /d "%2"
wget64 --execute robots=off --mirror --reject-regex '.*forum.*' --convert-links --adjust-extension --page-requisites --no-parent --progress=bar --no-check-certificate --show-progress --refer=http://google.com --user-agent="Mozilla/5.0 Firefox/4.0.1" %1
rundll32.exe cmdext.dll,MessageBeepStub
ECHO Download complete
GOTO end

:missing_arg
rundll32.exe cmdext.dll,MessageBeepStub
ECHO Correct syntax is "WGET <URL> <"Local Dir">"
GOTO end

:bad_dir
rundll32.exe cmdext.dll,MessageBeepStub
ECHO Unable to find local directory for download - please check your input.

:end
