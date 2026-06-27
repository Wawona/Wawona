#include <wayland-mac.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    int efd, evfd, ret;
    struct epoll_event ev, out;

    printf("[test_epoll] epoll_create1(EPOLL_CLOEXEC)\n");
    efd = epoll_create1(EPOLL_CLOEXEC);
    if (efd < 0) {
        perror("[test_epoll]   FAILED");
        return 1;
    }
    printf("[test_epoll]   efd=%d\n", efd);

    printf("[test_epoll] eventfd(0, EFD_NONBLOCK)\n");
    evfd = eventfd(0, EFD_NONBLOCK);
    if (evfd < 0) {
        perror("[test_epoll]   FAILED");
        return 1;
    }
    printf("[test_epoll]   evfd=%d\n", evfd);

    printf("[test_epoll] epoll_ctl(EPOLL_CTL_ADD, evfd, EPOLLIN)\n");
    memset(&ev, 0, sizeof(ev));
    ev.events = EPOLLIN;
    ev.data.fd = evfd;
    ret = epoll_ctl(efd, EPOLL_CTL_ADD, evfd, &ev);
    if (ret < 0) {
        perror("[test_epoll]   FAILED");
        return 1;
    }

    /* write to eventfd to make it readable */
    printf("[test_epoll] eventfd write(1)\n");
    uint64_t val = 1;
    ret = (int)write(evfd, &val, sizeof(val));
    if (ret < 0) {
        perror("[test_epoll]   write FAILED");
        return 1;
    }

    printf("[test_epoll] epoll_wait(timeout=5s)\n");
    ret = epoll_wait(efd, &out, 1, 5000);
    if (ret < 0) {
        perror("[test_epoll]   FAILED");
        return 1;
    }
    if (ret == 0) {
        printf("[test_epoll]   TIMEOUT — no events\n");
        return 1;
    }
    printf("[test_epoll]   got event on fd=%d events=0x%x\n",
           out.data.fd, out.events);

    close(evfd);
    close(efd);

    printf("[test_epoll] PASSED\n");
    return 0;
}
