const std = @import("std");
const Allocator = std.mem.Allocator;

const Chess = @import("chess.zig");

pub fn commandIterator(allocator: Allocator, reader: anytype) CommandIterator(@TypeOf(reader)) {
    return CommandIterator(@TypeOf(reader)).init(allocator, reader);
}

fn CommandIterator(Reader: type) type {
    return struct {
        const Self = @This();
        reader: Reader,
        allocator: Allocator,
        line: std.ArrayList(u8),
        eof: bool,

        pub fn init(allocator: Allocator, reader: Reader) Self {
            var self: Self = undefined;
            self.reader = reader;
            self.allocator = allocator;
            self.line = std.ArrayList(u8).init(allocator);
            self.eof = false;
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.line.deinit();
        }

        pub fn next(self: *Self) !?ServerCommand {
            if (self.eof) return null;
            self.line.clearRetainingCapacity();
            self.reader.streamUntilDelimiter(self.line.writer(), '\n', null) catch |e| {
                if (e == error.EndOfStream) self.eof = true
                else return e; 
            };

            var str = self.line.items;
            removeExtraWhitespace(&str);

            return try ServerCommand.parse(str, self.allocator);
        }

        fn removeExtraWhitespace(str: *[]u8) void {
            var it = std.mem.splitAny(u8, str.*, &std.ascii.whitespace);
            var i: usize = 0;
            var field = it.next();
            while (field) |f| : (field = it.next()) {
                if (f.len == 0) continue;
                std.mem.copyForwards(u8, str.*[i..], f);
                i += f.len;
                if (i < str.*.len) {
                    str.*[i] = ' ';
                    i += 1;
                }
            }
            if (i > 0 and i <= str.*.len and str.*[i - 1] == ' ') i -= 1;
            str.* = str.*[0..i];
        }
    };
}

pub const ClientCommand = union(enum) {
    const Self = @This();

    uciok,
    readyok,

    pub fn writeSerialized(self: Self, writer: anytype) !void {
        switch (self) {
            .uciok   => try writer.print("uciok\n", .{}),
            .readyok => try writer.print("readyok\n", .{}),
        }
    }
};

pub const ServerCommand = union(enum) {
    const Self = @This();

    empty,
    uci,
    debug: bool,
    isready,
    //setoption,
    //register,
    ucinewgame,
    position: struct {
        fen: Chess.Fen,
        moves: ?std.ArrayList(Chess.Move)
    },
    //go: union(enum) {
    //    searchmoves,
    //    ponder,
    //    //...
    //},
    //stop,
    //ponderhit,
    quit,

    const ParseError = error{
        InvalidCommand, InvalidValue, InvalidArg, InvalidMove,
        ExpectedValue, ExpectedFEN, ExpectedMoves
    };

    pub fn parse(str: []const u8, allocator: Allocator) (ParseError || Allocator.Error)!Self {
        if (str.len == 0) return .empty;

        var split = std.mem.splitScalar(u8, str, ' ');
        const arg_0 = split.next().?;

        const basic = .{
            .{"uci",        .uci},
            .{"isready",    .isready},
            .{"ucinewgame", .ucinewgame},
            .{"quit", .quit}
        };
        inline for (basic) |cmd| {
            if (std.mem.eql(u8, arg_0, cmd[0])) {
                return cmd[1];
            }
        }

        const arg_1_opt = split.next();

        if (std.mem.eql(u8, arg_0, "debug")) {
            const arg_1 = arg_1_opt orelse return error.ExpectedValue;
            const val = if (std.mem.eql(u8, arg_1, "on"))
                true
            else if (std.mem.eql(u8, arg_1, "off"))
                false
            else return error.InvalidArg;
            return ServerCommand{ .debug = val };
        }

        if (std.mem.eql(u8, arg_0, "position")) {
            const arg_1 = arg_1_opt orelse return error.ExpectedFEN;
            const fen = if (std.mem.eql(u8, arg_1, "startpos"))
                Chess.startpos
            else
                try Self.parseFEN(arg_1);

            var moves: ?std.ArrayList(Chess.Move) = null;

            if (split.next()) |arg_2| {
                if (!std.mem.eql(u8, arg_2, "moves")) return error.InvalidArg;
                moves = std.ArrayList(Chess.Move).init(allocator);
                errdefer moves.?.deinit();

                if (split.next()) |move| {
                    try moves.?.append(try parseMove(move));
                } else return error.ExpectedMoves;

                while (split.next()) |move| {
                    try moves.?.append(try parseMove(move));
                }
            }

            return ServerCommand{ .position = .{ .fen = fen, .moves = moves }};
        }

        return error.InvalidCommand;
    }

    pub fn parseFEN(str: []const u8) ParseError!Chess.Fen {
        // TODO
        return str;
    }

    pub fn parseMove(str: []const u8) ParseError!Chess.Move {
        if (str.len != 4) return error.InvalidMove;
        if (str[0] < 'a' or str[0] > 'h') return error.InvalidMove;
        if (str[2] < 'a' or str[2] > 'h') return error.InvalidMove;
        if (str[1] < '1' or str[1] > '8') return error.InvalidMove;
        if (str[3] < '1' or str[3] > '8') return error.InvalidMove;
        return Chess.Move{
            .from = Chess.mkSquare(str[0..2]),
            .to   = Chess.mkSquare(str[2..4]),
        };
    }
};

