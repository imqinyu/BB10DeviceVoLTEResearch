/* Use Navigator's original BB dots as an IMS/LTE registration indicator.
 * Does not modify IMS, RCP, radio or BBM service state. QNX/BB10 ARMv7.
 */
#include <sys/pps.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define IMS "/pps/services/ims/status_public"
#define ICON "/pps/system/navigator/status/bb_service"
#define BBIO "/pps/services/bbio/status"
#define LOCK "/var/tmp/bb10-volte/volte-berry.lock"
static volatile sig_atomic_t stopping;

static void stop_signal(int sig) { (void)sig; stopping = 1; }

static void message(const char *s) {
    fprintf(stderr, "%ld %s\n", (long)time(NULL), s);
    fflush(stderr);
}

static int snapshot(const char *path, char *buf, size_t size) {
    int fd = open(path, O_RDONLY | O_NONBLOCK);
    ssize_t n;
    if (fd < 0) return -1;
    n = read(fd, buf, size - 1);
    close(fd);
    if (n <= 0 || (size_t)n == size - 1) return -1;
    buf[n] = 0;
    return 0;
}

/* Decoder strings point into the supplied mutable buffer. */
static int decode(pps_decoder_t *d, char *buf) {
    return pps_decoder_initialize(d, buf) == PPS_DECODER_OK &&
           pps_decoder_push(d, NULL) == PPS_DECODER_OK;
}

static int same(pps_decoder_t *d, const char *key, const char *expected) {
    const char *value = NULL;
    return pps_decoder_get_string(d, key, &value) == PPS_DECODER_OK &&
           value && !strcmp(value, expected);
}

static int ims_connected(char *buf) {
    pps_decoder_t d;
    int active = 0, i, length;
    if (decode(&d, buf) && same(&d, "status", "connected") &&
        same(&d, "default_ran", "LTE") &&
        pps_decoder_push_array(&d, "deviceConfig") == PPS_DECODER_OK) {
        length = pps_decoder_length(&d);
        for (i = 0; i < length; ++i) {
            if (pps_decoder_goto_index(&d, i) == PPS_DECODER_OK &&
                same(&d, NULL, "VoLTE")) { active = 1; break; }
        }
    }
    pps_decoder_cleanup(&d);
    return active;
}

static int icon_state(char *buf) {
    pps_decoder_t d;
    int state = -1;
    if (decode(&d, buf) &&
        pps_decoder_push_object(&d, "dat") == PPS_DECODER_OK &&
        pps_decoder_push_object(&d, "bb_service") == PPS_DECODER_OK) {
        if (same(&d, "state", "on")) state = 1;
        else if (same(&d, "state", "off")) state = 0;
    }
    pps_decoder_cleanup(&d);
    return state;
}

static int set_icon(int on) {
    static const char yes[] = "[n]dat:json:{\"bb_service\":{\"state\":\"on\"}}\n";
    static const char no[] = "[n]dat:json:{\"bb_service\":{\"state\":\"off\"}}\n";
    const char *s = on ? yes : no;
    size_t n = strlen(s);
    int fd = open(ICON, O_WRONLY);
    ssize_t result;
    if (fd < 0) return -1;
    result = write(fd, s, n);
    close(fd);
    return result == (ssize_t)n ? 0 : -1;
}

/* On an intentional stop, hand presentation back to actual RCP state. */
static void restore_bbio(void) {
    char buf[16384];
    pps_decoder_t d;
    int on = 0;
    if (snapshot(BBIO, buf, sizeof(buf)) == 0) {
        if (decode(&d, buf)) {
            on = same(&d, "rcp_status", "0x03 connected");
            /* io-bb itself preserves dots while RCP is reconnecting. */
            if (!on && same(&d, "rcp_status", "0x04 reconnecting")) {
                char icon[4096];
                on = snapshot(ICON, icon, sizeof(icon)) == 0 && icon_state(icon) == 1;
            }
        }
        pps_decoder_cleanup(&d);
    }
    if (set_icon(on) != 0) message("failed to restore BBM indicator");
}

static int self_test(void) {
    const struct { const char *pps; int want; } cases[] = {
        {"@status_public\n[n]status::connected\n[n]default_ran::LTE\ndeviceConfig:json:[\"VoLTE\"]\n", 1},
        {"@status_public\nstatus::disconnected\ndefault_ran::LTE\ndeviceConfig:json:[\"VoLTE\"]\n", 0},
        {"@status_public\nstatus::connected\ndefault_ran::WLAN\ndeviceConfig:json:[\"VoLTE\"]\n", 0},
        {"@status_public\nstatus::connected\ndefault_ran::LTE\ndeviceConfig:json:[\"SMS\",\"VoLTE\"]\n", 1},
        {"@status_public\nstatus::connected\ndefault_ran::LTE\ndeviceConfig:json:[\"SMS\"]\n", 0},
        {"@status_public\nstatus::connected\ndefault_ran::LTE\ndeviceConfig:json:[\"VoLTE\"\n", 0},
        {"@status_public\n", 0}
    };
    unsigned i;
    for (i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i) {
        char buf[1024];
        strcpy(buf, cases[i].pps);
        if (ims_connected(buf) != cases[i].want) {
            fprintf(stderr, "PPS decoder self-test %u failed\n", i);
            return 1;
        }
    }
    puts("PPS decoder: 7 cases passed");
    return 0;
}

int main(int argc, char **argv) {
    char ims[16384], icon[4096];
    int desired, actual, previous = -1, lockfd, warned = 0;
    struct flock lock;
    struct sigaction sa;
    if (argc == 2 && !strcmp(argv[1], "--self-test")) return self_test();
    if (argc == 2 && !strcmp(argv[1], "--check")) {
        desired = snapshot(IMS, ims, sizeof(ims)) == 0 && ims_connected(ims);
        actual = snapshot(ICON, icon, sizeof(icon)) == 0 ? icon_state(icon) : -1;
        printf("VoLTE_connected=%d berry_state=%d\n", desired, actual);
        return desired == actual ? 0 : 1;
    }
    if (argc != 1) {
        fprintf(stderr, "Usage: volte-berry [--check|--self-test]\n");
        return 2;
    }
    lockfd = open(LOCK, O_RDWR | O_CREAT, 0600);
    if (lockfd < 0) { perror("indicator lock"); return 1; }
    memset(&lock, 0, sizeof(lock));
    lock.l_type = F_WRLCK;
    lock.l_whence = SEEK_SET;
    if (fcntl(lockfd, F_SETLK, &lock) < 0) {
        message("indicator already running (lock busy)");
        close(lockfd);
        return 1;
    }
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = stop_signal;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
    message("VoLTE berry monitor started; update interval 2 seconds");
    while (!stopping) {
        desired = snapshot(IMS, ims, sizeof(ims)) == 0 && ims_connected(ims);
        actual = snapshot(ICON, icon, sizeof(icon)) == 0 ? icon_state(icon) : -1;
        if (actual != desired) {
            if (set_icon(desired) != 0) {
                if (!warned) message("could not update Navigator indicator; retrying");
                warned = 1;
                sleep(2);
                continue;
            }
            warned = 0;
        }
        if (previous != desired) {
            message(desired ? "IMS VoLTE connected: berry on" : "IMS VoLTE disconnected: berry off");
            previous = desired;
        }
        sleep(2);
    }
    restore_bbio();
    message("monitor stopped; indicator returned to BBM/RCP state");
    close(lockfd);
    return 0;
}
