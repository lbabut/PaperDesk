#include <linux/input.h>
#include <linux/uinput.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

#define FIFO_PATH "/tmp/paperdesk-touch.fifo"
#define READY_PATH "/tmp/paperdesk-touch.ready"
#define SCREEN_WIDTH 1404
#define SCREEN_HEIGHT 1872

static volatile sig_atomic_t running = 1;

static void stop_handler(int sig) { (void)sig; running = 0; }

static int emit_event(int fd, int type, int code, int value) {
    struct input_event event;
    memset(&event, 0, sizeof(event));
    event.type = type;
    event.code = code;
    event.value = value;
    return write(fd, &event, sizeof(event)) == (ssize_t)sizeof(event) ? 0 : -1;
}

static void sync_event(int fd) { emit_event(fd, EV_SYN, SYN_REPORT, 0); }

static int raw_x(int screen_x) { return screen_x; }
static int raw_y(int screen_y) { return SCREEN_HEIGHT - 1 - screen_y; }

static void touch_down(int fd, int screen_x, int screen_y, int tracking_id) {
    emit_event(fd, EV_ABS, ABS_MT_SLOT, 0);
    emit_event(fd, EV_ABS, ABS_MT_TRACKING_ID, tracking_id);
    emit_event(fd, EV_ABS, ABS_MT_POSITION_X, raw_x(screen_x));
    emit_event(fd, EV_ABS, ABS_MT_POSITION_Y, raw_y(screen_y));
    emit_event(fd, EV_ABS, ABS_MT_TOUCH_MAJOR, 12);
    emit_event(fd, EV_ABS, ABS_MT_TOUCH_MINOR, 12);
    emit_event(fd, EV_ABS, ABS_MT_ORIENTATION, 0);
    emit_event(fd, EV_ABS, ABS_MT_TOOL_TYPE, MT_TOOL_FINGER);
    emit_event(fd, EV_ABS, ABS_MT_PRESSURE, 80);
    emit_event(fd, EV_ABS, ABS_PRESSURE, 80);
    emit_event(fd, EV_KEY, BTN_TOOL_FINGER, 1);
    emit_event(fd, EV_KEY, BTN_TOUCH, 1);
    sync_event(fd);
}

static void touch_move(int fd, int screen_x, int screen_y) {
    emit_event(fd, EV_ABS, ABS_MT_POSITION_X, raw_x(screen_x));
    emit_event(fd, EV_ABS, ABS_MT_POSITION_Y, raw_y(screen_y));
    sync_event(fd);
}

static void touch_up(int fd) {
    emit_event(fd, EV_ABS, ABS_MT_PRESSURE, 0);
    emit_event(fd, EV_ABS, ABS_PRESSURE, 0);
    emit_event(fd, EV_ABS, ABS_MT_TOUCH_MAJOR, 0);
    emit_event(fd, EV_ABS, ABS_MT_TOUCH_MINOR, 0);
    emit_event(fd, EV_ABS, ABS_MT_TRACKING_ID, -1);
    emit_event(fd, EV_KEY, BTN_TOUCH, 0);
    emit_event(fd, EV_KEY, BTN_TOOL_FINGER, 0);
    sync_event(fd);
}

static void tap(int fd, int x, int y, int tracking_id) {
    touch_down(fd, x, y, tracking_id);
    usleep(110000);
    touch_up(fd);
}

static void hold(int fd, int x, int y, int duration_ms, int tracking_id) {
    touch_down(fd, x, y, tracking_id);
    usleep((useconds_t)(duration_ms * 1000));
    touch_up(fd);
}

static void swipe(int fd, int x1, int y1, int x2, int y2, int duration_ms, int tracking_id) {
    const int steps = 12;
    touch_down(fd, x1, y1, tracking_id);
    for (int step = 1; step <= steps; ++step) {
        usleep((useconds_t)(duration_ms * 1000 / steps));
        touch_move(fd, x1 + (x2 - x1) * step / steps, y1 + (y2 - y1) * step / steps);
    }
    touch_up(fd);
}

static void slot_position(int fd, int slot, int x, int y) {
    emit_event(fd, EV_ABS, ABS_MT_SLOT, slot);
    emit_event(fd, EV_ABS, ABS_MT_POSITION_X, raw_x(x));
    emit_event(fd, EV_ABS, ABS_MT_POSITION_Y, raw_y(y));
}

static void pinch(int fd, int x1, int y1, int x2, int y2,
                  int end_x1, int end_y1, int end_x2, int end_y2,
                  int duration_ms, int tracking_id) {
    emit_event(fd, EV_ABS, ABS_MT_SLOT, 0);
    emit_event(fd, EV_ABS, ABS_MT_TRACKING_ID, tracking_id);
    slot_position(fd, 0, x1, y1);
    emit_event(fd, EV_ABS, ABS_MT_SLOT, 1);
    emit_event(fd, EV_ABS, ABS_MT_TRACKING_ID, tracking_id + 1);
    slot_position(fd, 1, x2, y2);
    emit_event(fd, EV_KEY, BTN_TOUCH, 1);
    emit_event(fd, EV_KEY, BTN_TOOL_DOUBLETAP, 1);
    sync_event(fd);
    for (int step = 1; step <= 12; ++step) {
        usleep((useconds_t)(duration_ms * 1000 / 12));
        slot_position(fd, 0, x1 + (end_x1 - x1) * step / 12,
                      y1 + (end_y1 - y1) * step / 12);
        slot_position(fd, 1, x2 + (end_x2 - x2) * step / 12,
                      y2 + (end_y2 - y2) * step / 12);
        sync_event(fd);
    }
    emit_event(fd, EV_ABS, ABS_MT_SLOT, 0);
    emit_event(fd, EV_ABS, ABS_MT_TRACKING_ID, -1);
    emit_event(fd, EV_ABS, ABS_MT_SLOT, 1);
    emit_event(fd, EV_ABS, ABS_MT_TRACKING_ID, -1);
    emit_event(fd, EV_KEY, BTN_TOOL_DOUBLETAP, 0);
    emit_event(fd, EV_KEY, BTN_TOUCH, 0);
    sync_event(fd);
}

static int create_device(void) {
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) return -1;
    ioctl(fd, UI_SET_PHYS, "2-0024/input0");
    ioctl(fd, UI_SET_EVBIT, EV_SYN);
    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    ioctl(fd, UI_SET_KEYBIT, BTN_TOUCH);
    ioctl(fd, UI_SET_KEYBIT, BTN_TOOL_FINGER);
    ioctl(fd, UI_SET_KEYBIT, BTN_TOOL_DOUBLETAP);
    ioctl(fd, UI_SET_EVBIT, EV_ABS);
    ioctl(fd, UI_SET_ABSBIT, ABS_MT_SLOT);
    ioctl(fd, UI_SET_ABSBIT, ABS_MT_TRACKING_ID);
    ioctl(fd, UI_SET_ABSBIT, ABS_MT_POSITION_X);
    ioctl(fd, UI_SET_ABSBIT, ABS_MT_POSITION_Y);
    ioctl(fd, UI_SET_ABSBIT, ABS_MT_TOUCH_MAJOR);
    ioctl(fd, UI_SET_ABSBIT, ABS_MT_TOUCH_MINOR);
    ioctl(fd, UI_SET_ABSBIT, ABS_MT_ORIENTATION);
    ioctl(fd, UI_SET_ABSBIT, ABS_MT_TOOL_TYPE);
    ioctl(fd, UI_SET_ABSBIT, ABS_MT_PRESSURE);
    ioctl(fd, UI_SET_ABSBIT, ABS_PRESSURE);
    ioctl(fd, UI_SET_PROPBIT, INPUT_PROP_DIRECT);

    struct uinput_user_dev device;
    memset(&device, 0, sizeof(device));
    // Xochitl selects the RM2 capacitive panel by its kernel device identity,
    // so the test device must look like pt_mt and must exist before Xochitl.
    strcpy(device.name, "pt_mt");
    device.id.bustype = 0;
    device.id.vendor = 0;
    device.id.product = 0;
    device.id.version = 0;
    device.absmin[ABS_MT_SLOT] = 0;
    device.absmax[ABS_MT_SLOT] = 31;
    device.absmin[ABS_MT_TRACKING_ID] = 0;
    device.absmax[ABS_MT_TRACKING_ID] = 65535;
    device.absmin[ABS_MT_POSITION_X] = 0;
    // Xochitl expects the synthetic pt_mt geometry in portrait orientation
    // and applies the panel's vertical inversion itself.
    device.absmax[ABS_MT_POSITION_X] = SCREEN_WIDTH - 1;
    device.absmin[ABS_MT_POSITION_Y] = 0;
    device.absmax[ABS_MT_POSITION_Y] = SCREEN_HEIGHT - 1;
    device.absmin[ABS_MT_TOUCH_MAJOR] = 0;
    device.absmax[ABS_MT_TOUCH_MAJOR] = 255;
    device.absmin[ABS_MT_TOUCH_MINOR] = 0;
    device.absmax[ABS_MT_TOUCH_MINOR] = 255;
    device.absmin[ABS_MT_ORIENTATION] = -127;
    device.absmax[ABS_MT_ORIENTATION] = 127;
    device.absmin[ABS_MT_TOOL_TYPE] = 0;
    device.absmax[ABS_MT_TOOL_TYPE] = MT_TOOL_FINGER;
    device.absmin[ABS_MT_PRESSURE] = 0;
    device.absmax[ABS_MT_PRESSURE] = 255;
    device.absmin[ABS_PRESSURE] = 0;
    device.absmax[ABS_PRESSURE] = 255;
    if (write(fd, &device, sizeof(device)) != (ssize_t)sizeof(device) || ioctl(fd, UI_DEV_CREATE) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

int main(void) {
    signal(SIGTERM, stop_handler);
    signal(SIGINT, stop_handler);
    unlink(FIFO_PATH);
    unlink(READY_PATH);
    if (mkfifo(FIFO_PATH, 0600) < 0 && errno != EEXIST) return 2;
    int touch_fd = create_device();
    if (touch_fd < 0) return 3;
    usleep(500000);
    int fifo_fd = open(FIFO_PATH, O_RDWR);
    if (fifo_fd < 0) return 4;
    FILE *fifo = fdopen(fifo_fd, "r");
    if (!fifo) return 5;
    int ready_fd = open(READY_PATH, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (ready_fd >= 0) { write(ready_fd, "ready\n", 6); close(ready_fd); }

    char line[160];
    int tracking_id = 1;
    while (running && fgets(line, sizeof(line), fifo)) {
        int x1, y1, x2, y2, x3, y3, x4, y4, duration;
        if (sscanf(line, "tap %d %d", &x1, &y1) == 2) {
            fprintf(stderr, "tap %d %d\n", x1, y1);
            fflush(stderr);
            tap(touch_fd, x1, y1, tracking_id++);
        } else if (sscanf(line, "hold %d %d %d", &x1, &y1, &duration) == 3) {
            fprintf(stderr, "hold %d %d %d\n", x1, y1, duration);
            fflush(stderr);
            hold(touch_fd, x1, y1, duration, tracking_id++);
        } else if (sscanf(line, "swipe %d %d %d %d %d", &x1, &y1, &x2, &y2, &duration) == 5) {
            fprintf(stderr, "swipe %d %d %d %d %d\n", x1, y1, x2, y2, duration);
            fflush(stderr);
            swipe(touch_fd, x1, y1, x2, y2, duration, tracking_id++);
        } else if (sscanf(line, "pinch %d %d %d %d %d %d %d %d %d",
                          &x1, &y1, &x2, &y2, &x3, &y3, &x4, &y4, &duration) == 9) {
            fprintf(stderr, "pinch %d %d %d %d %d %d %d %d %d\n",
                    x1, y1, x2, y2, x3, y3, x4, y4, duration);
            fflush(stderr);
            pinch(touch_fd, x1, y1, x2, y2, x3, y3, x4, y4, duration, tracking_id);
            tracking_id += 2;
        } else if (!strncmp(line, "quit", 4)) {
            break;
        }
    }
    ioctl(touch_fd, UI_DEV_DESTROY);
    fclose(fifo);
    close(touch_fd);
    unlink(FIFO_PATH);
    unlink(READY_PATH);
    return 0;
}
