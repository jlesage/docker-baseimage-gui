/*
Copyright (C) 2016 Alex Kost

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <X11/Xlib.h>

#include "config.h"

#define EXIT_DRY_RUN 255
#define FALSE 0
#define TRUE (!FALSE)

typedef int bool;
typedef struct settings_t {
    char *display_name;
    bool quiet;
} settings_t;

int main (int argc, char *argv[]);
void usage (void);
void version (void);
void display_message (settings_t *settings, char *value);
void set_defaults (settings_t *settings);
void parse_args (int argc, char *argv[], settings_t *settings);

int
main (int argc, char *argv[])
{
    Display *display;
    settings_t settings;

    set_defaults(&settings);
    parse_args(argc, argv, &settings);

    display = XOpenDisplay(settings.display_name);
    if (display) {
        XCloseDisplay(display);
        display_message(&settings, "yes");
        exit(EXIT_SUCCESS);
    } else {
        display_message(&settings, "no");
        exit(EXIT_FAILURE);
    }
}

void
usage (void)
{
    printf("Usage: %s [OPTIONS] [DISPLAY]\n", PACKAGE_NAME);
    printf("Check connectivity of the X server defined by DISPLAY.\n"
           "If DISPLAY is not specified, use $DISPLAY environment variable.\n\n");
    printf("Options:\n"
           "  -q, --quiet       do not display any output\n"
           "  -h, --help        display help message and exit\n"
           "  -v, --version     display version message and exit\n\n");
    printf("Exit status:\n"
           " %3d  if connection to DISPLAY succeeded;\n"
           " %3d  if connection to DISPLAY failed;\n"
           " %3d  if X server connectivity was not probed (e.g., when\n"
           "      the help message is displayed).\n",
           EXIT_SUCCESS, EXIT_FAILURE, EXIT_DRY_RUN);
    exit(EXIT_DRY_RUN);
}

void
version (void)
{
    printf("%s\n", PACKAGE_STRING);
    printf("Copyright (C) %d Alex Kost\n"
           "License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.\n"
           "This is free software: you are free to change and redistribute it.\n"
           "There is NO WARRANTY, to the extent permitted by law.\n",
           COPYRIGHT_YEAR);
    exit(EXIT_DRY_RUN);
}

void
display_message (settings_t *settings, char *value)
{
    if (!settings->quiet)
        printf("DISPLAY '%s' is available?  %s\n",
               settings->display_name, value);
}

void
set_defaults(settings_t *settings)
{
    settings->display_name = getenv("DISPLAY");
    settings->quiet        = FALSE;
}

void
parse_args (int argc, char *argv[], settings_t *settings)
{
    int opt;
    int opt_index = 0;

    struct option opts[] = {
        {"quiet",     no_argument,       NULL, 'q'},
        {"help",      no_argument,       NULL, 'h'},
        {"version",   no_argument,       NULL, 'v'},
        {NULL,        0,                 NULL, 0},
    };

    while ((opt = getopt_long(argc, argv, "qhv", opts, &opt_index)) != -1)
        switch (opt) {
        case 'q':
            settings->quiet = TRUE;
            break;
        case 'h':
            usage();
        case 'v':
            version();
        default:
            usage();
        }

    switch (argc - optind) {  /* arguments left */
    case 0:
        break;
    case 1:
        settings->display_name = argv[optind];
        break;
    default:
        fprintf(stderr, "Too many arguments\n");
        usage();
    }
}
