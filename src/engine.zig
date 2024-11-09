const std = @import("std");
const Allocator = std.mem.Allocator;

const uci = @import("uci.zig");
const Chess = @import("chess.zig");

const Engine = struct {
    const Self = @This();

    game: Chess,

    debug: bool = true,
    calculating: bool = false,
    infinite: bool = false,
    bestmove: ?Chess.Move = null,

    pub fn init(allocator: std.mem.Allocator) Allocator.Error!Self {
        return Self{
            .game = try Chess.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.game.deinit();
    }

    pub fn calculate(self: *Self) void {
        var moves = self.game.legal_moves.keyIterator();

        self.bestmove = moves.next().?.*;
        if (!self.infinite) self.calculating = false;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    // TODO: nonblocking stdin?
    var uci_commands = uci.commandIterator(allocator, stdin);
    defer uci_commands.deinit();

    var engine = try Engine.init(allocator);
    defer engine.deinit();
    
    var running: bool = true;
    while (uci_commands.next() catch .empty) |command| : (if (!running) break) {
        var uci_response: ?uci.ClientCommand = null;

        switch (command) {
            .uci => uci_response = .uciok,
            .debug => |val| engine.debug = val,
            .isready => uci_response = .readyok,
            //.setoption => {},
            //.register => {},
            .ucinewgame => {}, // reset engine state
            .position => |cmd| {
                defer if (cmd.moves) |moves| moves.deinit();
                try engine.game.setFEN(cmd.fen);
                if (cmd.moves) |moves| {
                    engine.game.moves.clearRetainingCapacity();
                    for (moves.items) |move| {
                        engine.game.makeMove(move) catch break;
                    }
                    try stdout.print("info string moves", .{});
                    try engine.game.printMoves(stdout);
                }
                try stdout.print("info string legal", .{});
                try engine.game.printLegalMoves(stdout);
                try engine.game.printBoard(stdout);
                try stdout.print("info string turn {s}\n", .{@tagName(engine.game.turn)});
            },
            .go => |go| {
                defer if (go.searchmoves) |moves| moves.deinit();
                engine.infinite = go.infinite;
                engine.calculating = true;
            },
            .stop => engine.calculating = false,
            //.ponderhit => {},
            .quit => running = false,
            .empty => {}
        }

        if (engine.calculating) engine.calculate();

        if (uci_response == null and engine.bestmove != null and !engine.calculating) {
            uci_response = .{.bestmove = engine.bestmove.?};
            engine.bestmove = null;
        }

        if (uci_response) |response| {
            try response.writeSerialized(stdout);
            uci_response = null;
        }
    }

    if (engine.bestmove) |move| {
        const response = uci.ClientCommand{.bestmove = move};
        try response.writeSerialized(stdout);
    }
}
