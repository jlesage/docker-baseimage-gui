/*
 * Stripped-down version of hsetroot that only supports solid color.
 * https://github.com/himdel/hsetroot
 */

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void
usage(char *commandline)
{
  printf(
    "hsetroot - yet another wallpaper application\n"
    "\n"
    "Syntax: %s [command1 [arg1..]] [command2 [arg1..]]..."
    "\n"
    "Solid:\n"
    " -solid <color>             Render a solid using the specified color\n"
    "\n"
    "Colors are in the #rgb, #rrggbb, #rrggbbaa, rgb:1/2/3 formats or a X color name.\n"
    "\n"
    "Create issues at https://github.com/himdel/hsetroot/issues\n\n"
  , commandline);
}

// Globals:
Display *display;
int screen;

// Adapted from fluxbox' bsetroot
static int
setRootAtoms(Pixmap pixmap)
{
  Atom atom_root, atom_eroot, type;
  unsigned char *data_root, *data_eroot;
  int format;
  unsigned long length, after;

  atom_root = XInternAtom(display, "_XROOTMAP_ID", True);
  atom_eroot = XInternAtom(display, "ESETROOT_PMAP_ID", True);

  // doing this to clean up after old background
  if (atom_root != None && atom_eroot != None) {
    XGetWindowProperty(display, RootWindow(display, screen), atom_root, 0L, 1L, False, AnyPropertyType, &type, &format, &length, &after, &data_root);

    if (type == XA_PIXMAP) {
      XGetWindowProperty(display, RootWindow(display, screen), atom_eroot, 0L, 1L, False, AnyPropertyType, &type, &format, &length, &after, &data_eroot);

      if (data_root && data_eroot && type == XA_PIXMAP && *((Pixmap *) data_root) == *((Pixmap *) data_eroot))
        XKillClient(display, *((Pixmap *) data_root));
    }
  }

  atom_root = XInternAtom(display, "_XROOTPMAP_ID", False);
  atom_eroot = XInternAtom(display, "ESETROOT_PMAP_ID", False);

  if (atom_root == None || atom_eroot == None)
    return 0;

  // setting new background atoms
  XChangeProperty(display, RootWindow(display, screen), atom_root, XA_PIXMAP, 32, PropModeReplace, (unsigned char *) &pixmap, 1);
  XChangeProperty(display, RootWindow(display, screen), atom_eroot, XA_PIXMAP, 32, PropModeReplace, (unsigned char *) &pixmap, 1);

  return 1;
}

typedef struct {
  int r, g, b, a;
  unsigned long pixel;
} Color;

static int
parse_color(char *arg, Color *c, int default_alpha)
{
  Colormap colormap = DefaultColormap(display, screen);
  XColor color;

  c->a = default_alpha;

  // we support #rrggbbaa..
  if ((arg[0] == '#') && (strlen(arg) == 9)) {
    sscanf(arg + 7, "%2x", &(c->a));
    // ..but XParseColor wouldn't
    arg[7] = 0;
  }

  Status ret = XParseColor(display, colormap, arg, &color);
  if (ret == 0)
    return 0;

  c->r = color.red >> 8;
  c->g = color.green >> 8;
  c->b = color.blue >> 8;
  c->pixel = color.pixel;

  return 1;
}

int
main(int argc, char **argv)
{
  int width, height, depth, i, alpha;
  Pixmap pixmap;

  /* global */ display = XOpenDisplay(NULL);

  if (!display) {
    fprintf(stderr, "Cannot open X display!\n");
    exit(123);
  }

  for (/* global */ screen = 0; screen < ScreenCount(display); screen++) {
    width = DisplayWidth(display, screen);
    height = DisplayHeight(display, screen);
    depth = DefaultDepth(display, screen);

    pixmap = XCreatePixmap(display, RootWindow(display, screen), width, height, depth);

    alpha = 255;

    Color c;

    for (i = 1; i < argc; i++) {
      if (strcmp(argv[i], "-solid") == 0) {
        if ((++i) >= argc) {
          fprintf(stderr, "Missing color\n");
          continue;
        }
        if (parse_color(argv[i], &c, alpha) == 0) {
          fprintf (stderr, "Bad color (%s)\n", argv[i]);
          continue;
        }
      } else {
        usage(argv[0]);
        exit(1);
      }
    }

    if (setRootAtoms(pixmap) == 0)
      fprintf(stderr, "Couldn't create atoms...\n");

    XKillClient(display, AllTemporary);
    XSetCloseDownMode(display, RetainTemporary);

    XSetWindowBackground(display, RootWindow(display, screen), c.pixel);
    XClearWindow(display, RootWindow(display, screen));

    XFlush(display);
    XSync(display, False);
  }

  return 0;
}
