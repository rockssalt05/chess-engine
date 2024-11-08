const std = @import("std");
const Allocator = std.mem.Allocator;

const uci = @import("uci.zig");
const Chess = @import("chess.zig");

const Engine = struct {
    const Self = @This();

    game: Chess,

    uci_response: ?uci.ClientCommand = null,
    debug: bool = true,

    pub fn init(allocator: std.mem.Allocator) Allocator.Error!Self {
        return Self{
            .game = try Chess.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.game.deinit();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var uci_commands = uci.commandIterator(allocator, stdin);
    defer uci_commands.deinit();

    var engine = try Engine.init(allocator);
    defer engine.deinit();
    
    while (uci_commands.next() catch .empty) |command| {
        switch (command) {
            .uci => engine.uci_response = .uciok,
            .debug => |val| engine.debug = val,
            .isready => engine.uci_response = .readyok,
            //.setoption => {},
            //.register => {},
            .ucinewgame => engine.game.newGame(),
            .position => |cmd| {
                defer if (cmd.moves) |moves| moves.deinit();
                try engine.game.setFEN(cmd.fen);
                if (cmd.moves) |moves| {
                    engine.game.moves.clearRetainingCapacity();
                    for (moves.items) |move| {
                        engine.game.makeMove(move) catch break;
                    }
                    try engine.game.printMoves(stdout);
                }
                try engine.game.printLegalMoves(stdout);
                try engine.game.printBoard(stdout);
                try stdout.print("info string {s}\n", .{if (engine.game.turn == .white) "white" else "black"});
            },
            //.go => |go| switch (go) {
            //    .searchmoves => ,
            //    .ponder => ,
            //    //...
            //},
            //.stop => {},
            //.ponderhit => {},
            .quit => break,
            .empty => {}
        }

        if (engine.uci_response) |response| {
            try response.writeSerialized(stdout);
            engine.uci_response = null;
        }
    }
}
