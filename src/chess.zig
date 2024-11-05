const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

board: [8][8]?Piece = .{.{null}**8}**8,
turn: Piece.Color = .white,

moves: std.ArrayList(Move),
legal_moves: std.hash_map.AutoHashMap(Move, void),

allocator: Allocator,


pub fn init(allocator: Allocator) Allocator.Error!Self {
    var self: Self = undefined;
    self.moves = std.ArrayList(Move).init(allocator);
    self.legal_moves = std.hash_map.AutoHashMap(Move, void).init(allocator);
    self.allocator = allocator;

    try self.setFEN(startpos);

    return self;
}

pub fn deinit(self: *Self) void {
    self.moves.deinit();
    self.legal_moves.deinit();
}

pub fn newGame(self: *Self) void {
    self.moves.clearRetainingCapacity();
}

pub const Fen = []const u8;
pub const startpos: Fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

pub fn setFEN(self: *Self, fen: Fen) Allocator.Error!void {
    self.board = .{.{null}**8}**8;

    var split = std.mem.splitScalar(u8, fen, ' ');
    const pieces = split.next().?;
    var file: u3 = 0;
    var rank: u3 = 7;
    for (pieces) |ch| {
        switch (ch) {
            '1'...'8' => |f| file += @intCast(f - '1'),
            '/' => { rank -= 1; file = 0; },
            else => |p| {
                self.board[rank][file] = mkPiece(p);
                file = @addWithOverflow(file, 1)[0];
            },
        }
    }
    try self.updateMoveList();
    // TODO: use other fields
}

const Piece = struct {
    const Color = enum { white, black };
    color: Color,
    kind: enum { rook, knight, bishop, queen, king, pawn },

    pub fn toChar(self: Piece) u8 {
        const ch: u8 = switch (self.kind) {
            .rook   => 'r',
            .knight => 'n',
            .bishop => 'b',
            .queen  => 'q',
            .king   => 'k',
            .pawn   => 'p',
        };

        return switch (self.color) {
            .white => std.ascii.toUpper(ch),
            .black => ch,
        };
    }
};

pub fn mkPiece(ch: u8) Piece {
    return Piece{
        .color = if (std.ascii.isLower(ch)) .black else .white,
        .kind = switch (std.ascii.toLower(ch)) {
            'r' => .rook,
            'n' => .knight,
            'b' => .bishop,
            'q' => .queen,
            'k' => .king,
            'p' => .pawn,
            else => unreachable,
        }
    };
}

const Square = struct {
    rank: u3,
    file: u3,
};

pub fn mkSquare(str: []const u8) Square {
    if (str.len != 2) unreachable;
    return Square{
        .rank = @intCast(str[1] - '1'),
        .file = @intCast(str[0] - 'a'),
    };
}

pub const Move = struct { from: Square, to: Square };
const MoveError = error{ DestIsAlly, NoPiece, NotAllowed };

pub fn makeMove(self: *Self, move: Move) (MoveError || Allocator.Error)!void {
    const piece1 = self.getSquare(move.from);
    const piece2 = self.getSquare(move.to);

    if (piece1 == null) return error.NoPiece;
    if (piece2 != null and piece1.?.color == piece2.?.color) {
        return error.DestIsAlly;
    }

    if (!self.legal_moves.contains(move)) return error.NotAllowed;

    self.setSquare(move.from, null);
    self.setSquare(move.to, piece1);
    try self.updateMoveList();
    self.turn = if (self.turn == .white) .black else .white;
}

pub fn updateMoveList(self: *Self) Allocator.Error!void {
    self.legal_moves.clearRetainingCapacity();

    for (self.board, 0..) |rank_pieces, rank| {
        for (rank_pieces, 0..) |piece, file| {
            if (piece) |p| {
                const square = Square{
                    .rank = @intCast(rank),
                    .file = @intCast(file)
                };
                switch (p.kind) {
                    .rook   => try self.addRookMoves(square),
                    .knight => try self.addKnightMoves(square),
                    .bishop => try self.addBishopMoves(square),
                    .queen  => try self.addQueenMoves(square),
                    .king   => try self.addKingMoves(square),
                    .pawn   => try self.addPawnMoves(square)
                }
            }
        }
    }
}

fn addRayMoves(self: *Self, square: Square, rank_dir: i8, file_dir: i8) Allocator.Error!void {
    var rank: i8 = square.rank + rank_dir;
    var file: i8 = square.file + file_dir;
    while (rank >= 0 and rank < 8 and file >= 0 and file < 8) : ({ rank += rank_dir; file += file_dir; }) {
        const move = Move{
            .from = square,
            .to = Square{
                .rank = @intCast(rank),
                .file = @intCast(file)
            }
        };
        if (self.getSquare(move.to) != null) break;

        try self.legal_moves.put(move, {});
    }
}

fn addRookMoves(self: *Self, square: Square) Allocator.Error!void {
    const directions = .{
        .{-1, 0}, .{1, 0}, .{0, -1}, .{0, 1}
    };
    inline for (directions) |dir| {
        try self.addRayMoves(square, dir[0], dir[1]);
    }
}

fn addKnightMoves(self: *Self, square: Square) Allocator.Error!void {
    _ = self; _ = square;
}

fn addBishopMoves(self: *Self, square: Square) Allocator.Error!void {
    const directions = .{
        .{-1, -1}, .{1, -1}, .{-1, 1}, .{1, 1}
    };
    inline for (directions) |dir| {
        try self.addRayMoves(square, dir[0], dir[1]);
    }
}

fn addQueenMoves(self: *Self, square: Square) Allocator.Error!void {
    try self.addRookMoves(square);
    try self.addBishopMoves(square);
}

fn addKingMoves(self: *Self, square: Square) Allocator.Error!void {
    _ = self; _ = square;
}

fn addPawnMoves(self: *Self, square: Square) Allocator.Error!void {
    _ = self; _ = square;
}


pub fn setSquare(self: *Self, square: Square, piece: ?Piece) void {
    self.board[square.rank][square.file] = piece;
}

pub fn getSquare(self: Self, square: Square) ?Piece {
    return self.board[square.rank][square.file];
}

pub fn printBoard(self: Self, writer: anytype) !void {
    for (1..self.board.len + 1) |i| {
        const rank = self.board[self.board.len - i];
        try writer.print("info string ", .{});
        for (rank) |piece| {
            try writer.print("{c} ", .{
                if (piece) |p| p.toChar() else '.'
            });
        }
        try writer.print("\n", .{});
    }
}

pub fn printMoves(self: Self, writer: anytype) !void {
    try writer.print("info string", .{});
    for (self.moves.items) |move| {
        try writer.print(" {c}{c}{c}{c}", .{
            @as(u8, @intCast(move.from.file)) + 'a', @as(u8, @intCast(move.from.rank)) + '1',
            @as(u8, @intCast(move.to.file))   + 'a', @as(u8, @intCast(move.to.rank))   + '1',
        });
    }
    try writer.print("\n", .{});
}

pub fn printLegalMoves(self: Self, writer: anytype) !void {
    var keys = self.legal_moves.keyIterator();
    try writer.print("info string", .{});
    var key_opt = keys.next();
    while (key_opt) |move| : (key_opt = keys.next()) {
        try writer.print(" {c}{c}{c}{c}", .{
            @as(u8, @intCast(move.from.file)) + 'a', @as(u8, @intCast(move.from.rank)) + '1',
            @as(u8, @intCast(move.to.file))   + 'a', @as(u8, @intCast(move.to.rank))   + '1',
        });
    }
    try writer.print("\n", .{});
}