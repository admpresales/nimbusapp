@echo off
rem Nimbusapp for Windows Launcher

rem TODO: Remove this
rem Fix PATH, sometimes the shell does not include perl
set PATH=%PATH%;C:\Strawberry\perl\bin

perl -x -S "%~dpn0.pl" %*