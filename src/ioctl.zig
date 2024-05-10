const posix = @import("std").posix;
const linux = @import("std").os.linux;

pub fn getWindowSize(fd: posix.fd_t) !linux.winsize {
    var ws: linux.winsize = undefined;
    switch (posix.errno(linux.ioctl(fd, linux.T.IOCGWINSZ, @intFromPtr(&ws)))) {
        .SUCCESS => return ws,
        .BADF => return error.BadFd,
        .FAULT => unreachable,
        .INVAL => unreachable,
        .NOTTY => return error.NotTerminal,
        else => |err| return posix.unexpectedErrno(err),
    }
}
