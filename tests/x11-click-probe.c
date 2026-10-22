#include <X11/Xlib.h>

#include <stdio.h>

int main(void) {
    Display* display = XOpenDisplay(NULL);
    if (!display) {
        fputs("cannot open X display\n", stderr);
        return 1;
    }

    const int screen = DefaultScreen(display);
    Window window = XCreateSimpleWindow(
        display, RootWindow(display, screen), 0, 0, 680, 780, 0,
        BlackPixel(display, screen), WhitePixel(display, screen));
    XStoreName(display, window, "PaperDesk double-click probe");
    XSelectInput(display, window, ButtonPressMask | ButtonReleaseMask);
    XMapRaised(display, window);
    XFlush(display);

    int buttonEvents = 0;
    while (buttonEvents < 4) {
        XEvent event;
        XNextEvent(display, &event);
        if (event.type != ButtonPress && event.type != ButtonRelease)
            continue;
        const XButtonEvent* button = &event.xbutton;
        printf("%s time=%lu root=%d,%d button=%u\n",
               event.type == ButtonPress ? "press" : "release",
               button->time, button->x_root, button->y_root, button->button);
        fflush(stdout);
        ++buttonEvents;
    }

    XDestroyWindow(display, window);
    XCloseDisplay(display);
    return 0;
}
