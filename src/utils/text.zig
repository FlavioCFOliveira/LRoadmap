const std = @import("std");

/// Normalizes text for case-insensitive and accent-insensitive comparison.
/// Converts to lowercase and removes diacritical marks (accents).
/// Returns an allocator-owned string that must be freed by the caller.
pub fn normalizeForComparison(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    // Allocate result buffer (same size as input)
    var result = try allocator.alloc(u8, text.len);
    errdefer allocator.free(result);

    // Convert to lowercase and remove diacritics in one pass
    for (text, 0..) |c, i| {
        const lower = std.ascii.toLower(c);
        const normalized = removeDiacritic(lower);
        result[i] = normalized[0];
    }

    return result;
}

/// ASCII-aware to lowercase conversion
/// Handles only ASCII characters (0-127), leaves others unchanged
pub fn toLowerAscii(text: []u8) void {
    for (text) |*c| {
        c.* = std.ascii.toLower(c.*);
    }
}

/// Removes diacritical marks from a single character.
/// Returns a string slice (usually 1 byte, sometimes more for special cases).
fn removeDiacritic(c: u8) []const u8 {
    // ASCII characters (0-127) don't have diacritics
    if (c < 128) return &[1]u8{c};

    // Extended ASCII Latin-1 (ISO-8859-1) accents
    // This covers the most common accented characters
    return switch (c) {
        // ÀÁÂÃÄÅàáâãäå -> a
        0xC0...0xC5, 0xE0...0xE5 => "a",
        // Çç -> c
        0xC7, 0xE7 => "c",
        // ÈÉÊËèéêë -> e
        0xC8...0xCB, 0xE8...0xEB => "e",
        // ÌÍÎÏìíîï -> i
        0xCC...0xCF, 0xEC...0xEF => "i",
        // Ññ -> n
        0xD1, 0xF1 => "n",
        // ÒÓÔÕÖØòóôõöø -> o
        0xD2...0xD6, 0xD8, 0xF2...0xF6, 0xF8 => "o",
        // ÙÚÛÜùúûü -> u
        0xD9...0xDC, 0xF9...0xFC => "u",
        // Ýýÿ -> y
        0xDD, 0xFD, 0xFF => "y",
        // Default: return the character as-is
        else => &[1]u8{c},
    };
}

/// UTF-8 aware normalization for comparison.
/// Handles multi-byte UTF-8 sequences for common accented characters.
/// Returns an allocator-owned string.
pub fn normalizeUtf8(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    // Estimate result size (usually same or smaller than input)
    var result = try allocator.alloc(u8, text.len * 2);
    errdefer allocator.free(result);

    var result_idx: usize = 0;
    var i: usize = 0;

    while (i < text.len) {
        const remaining = text[i..];
        const len = remaining.len;

        // Check for UTF-8 sequences
        if (len >= 2 and remaining[0] == 0xC3) {
            // Latin-1 Supplement (U+00C0 to U+00FF)
            const normalized = normalizeLatin1Supplement(remaining[1]);
            for (normalized) |b| {
                result[result_idx] = b;
                result_idx += 1;
            }
            i += 2;
        } else if (len >= 3 and remaining[0] == 0xC4) {
            // Latin Extended-A part 1 (U+0100 to U+013F)
            const normalized = normalizeLatinExtendedA1(remaining[1]);
            for (normalized) |b| {
                result[result_idx] = b;
                result_idx += 1;
            }
            i += if (normalized.len > 0) 2 else 1;
        } else if (len >= 3 and remaining[0] == 0xC5) {
            // Latin Extended-A part 2 (U+0140 to U+017F)
            const normalized = normalizeLatinExtendedA2(remaining[1]);
            for (normalized) |b| {
                result[result_idx] = b;
                result_idx += 1;
            }
            i += if (normalized.len > 0) 2 else 1;
        } else if (len >= 3 and remaining[0] == 0xC6) {
            // Latin Extended-A part 3 (U+0180 to U+01BF)
            const normalized = normalizeLatinExtendedA3(remaining[1]);
            for (normalized) |b| {
                result[result_idx] = b;
                result_idx += 1;
            }
            i += if (normalized.len > 0) 2 else 1;
        } else if (remaining[0] < 0x80) {
            // ASCII - convert to lowercase
            result[result_idx] = std.ascii.toLower(remaining[0]);
            result_idx += 1;
            i += 1;
        } else {
            // Other UTF-8 sequences - copy as-is
            const seq_len = utf8SequenceLength(remaining[0]);
            const copy_len = @min(seq_len, len);
            for (0..copy_len) |j| {
                result[result_idx] = remaining[j];
                result_idx += 1;
            }
            i += copy_len;
        }
    }

    // Resize result to actual size
    if (result_idx < result.len) {
        result = try allocator.realloc(result, result_idx);
    }

    return result;
}

/// Returns the expected length of a UTF-8 sequence based on first byte
fn utf8SequenceLength(first_byte: u8) usize {
    if (first_byte < 0x80) return 1;
    if ((first_byte & 0xE0) == 0xC0) return 2;
    if ((first_byte & 0xF0) == 0xE0) return 3;
    if ((first_byte & 0xF8) == 0xF0) return 4;
    return 1; // Invalid, treat as single byte
}

/// Normalize Latin-1 Supplement characters (C3 XX)
fn normalizeLatin1Supplement(second_byte: u8) []const u8 {
    return switch (second_byte) {
        // 0x80-0x9F: Control characters and special chars
        0x80 => "a", // À
        0x81 => "a", // Á
        0x82 => "a", // Â
        0x83 => "a", // Ã
        0x84 => "a", // Ä
        0x85 => "a", // Å
        0x87 => "c", // Ç
        0x88 => "e", // È
        0x89 => "e", // É
        0x8A => "e", // Ê
        0x8B => "e", // Ë
        0x8C => "i", // Ì
        0x8D => "i", // Í
        0x8E => "i", // Î
        0x8F => "i", // Ï
        0x91 => "n", // Ñ
        0x92 => "o", // Ò
        0x93 => "o", // Ó
        0x94 => "o", // Ô
        0x95 => "o", // Õ
        0x96 => "o", // Ö
        0x98 => "o", // Ø
        0x99 => "u", // Ù
        0x9A => "u", // Ú
        0x9B => "u", // Û
        0x9C => "u", // Ü
        0x9D => "y", // Ý
        0x9F => "b", // ß -> ss (use first letter)
        // 0xA0-0xBF: Lowercase versions
        0xA0 => "a", // à
        0xA1 => "a", // á
        0xA2 => "a", // â
        0xA3 => "a", // ã
        0xA4 => "a", // ä
        0xA5 => "a", // å
        0xA7 => "c", // ç
        0xA8 => "e", // è
        0xA9 => "e", // é
        0xAA => "e", // ê
        0xAB => "e", // ë
        0xAC => "i", // ì
        0xAD => "i", // í
        0xAE => "i", // î
        0xAF => "i", // ï
        0xB1 => "n", // ñ
        0xB2 => "o", // ò
        0xB3 => "o", // ó
        0xB4 => "o", // ô
        0xB5 => "o", // õ
        0xB6 => "o", // ö
        0xB8 => "o", // ø
        0xB9 => "u", // ù
        0xBA => "u", // ú
        0xBB => "u", // û
        0xBC => "u", // ü
        0xBD => "y", // ý
        0xBF => "y", // ÿ
        else => &[2]u8{ 0xC3, second_byte }, // Keep original
    };
}

/// Normalize Latin Extended-A part 1 (C4 XX)
fn normalizeLatinExtendedA1(second_byte: u8) []const u8 {
    return switch (second_byte) {
        // Ā-ą -> a
        0x80...0x85 => "a",
        // Ć-č -> c
        0x86...0x8D => "c",
        // Ď-đ -> d
        0x8E...0x91 => "d",
        // Ē-ě -> e
        0x92...0x9B => "e",
        // Ĝ-ğ -> g
        0x9C...0x9F => "g",
        // Ġ-ģ -> g
        0xA0...0xA3 => "g",
        // Ĥ-ħ -> h
        0xA4...0xA7 => "h",
        // Ĩ-į -> i
        0xA8...0xAF => "i",
        // Ĵ-ĵ -> j
        0xB4...0xB5 => "j",
        // Ķ-ķ -> k
        0xB6...0xB7 => "k",
        // Ĺ-ľ -> l
        0xB9...0xBE => "l",
        else => &[2]u8{ 0xC4, second_byte },
    };
}

/// Normalize Latin Extended-A part 2 (C5 XX)
fn normalizeLatinExtendedA2(second_byte: u8) []const u8 {
    return switch (second_byte) {
        // Ł-ł -> l
        0x81...0x82 => "l",
        // Ń-ň -> n
        0x83...0x88 => "n",
        // Ō-ő -> o
        0x8C...0x91 => "o",
        // Ŕ-ř -> r
        0x94...0x99 => "r",
        // Ś-š -> s
        0x9A...0xA1 => "s",
        // Ţ-ť -> t
        0xA2...0xA7 => "t",
        // Ũ-ų -> u
        0xA8...0xB3 => "u",
        // Ŵ-ŵ -> w
        0xB4...0xB5 => "w",
        // Ŷ-ŷ -> y
        0xB6...0xB7 => "y",
        // Ź-ž -> z
        0xB9...0xBE => "z",
        else => &[2]u8{ 0xC5, second_byte },
    };
}

/// Normalize Latin Extended-A part 3 (C6 XX) - Simplified
fn normalizeLatinExtendedA3(second_byte: u8) []const u8 {
    return switch (second_byte) {
        // Latin Extended-A characters
        // Simplified: map common accented chars to base letters
        0x80...0x85 => "b",     // ƀ, Ɓ, Ƃ, ƃ, Ƅ, ƅ
        0x86...0x8D => "c",     // Ɔ, Ƈ, ƈ, Ɖ, Ɗ, Ƌ, ƌ, ƍ
        0x8E...0x92 => "e",     // Ǝ, Ə, Ɛ, Ƒ, ƒ
        0x93...0x97 => "g",     // Ɠ, Ɣ, ƕ, Ɩ, Ɨ
        0x98 => "i",            // Ƙ
        0x99...0x9B => "i",     // (range)
        0x9C...0x9F => "j",     // (range)
        0xA0...0xA5 => "o",     // Ō, ō, Ŏ, ŏ, Ő, ő
        0xA6...0xAB => "t",     // Ŧ, ŧ, etc
        0xAC...0xB3 => "u",     // Ŭ, ŭ, Ů, ů, Ű, ű, Ų, ų
        0xB4...0xB5 => "w",     // Ŵ, ŵ
        0xB6...0xB8 => "y",     // Ŷ, ŷ, Ÿ
        0xB9...0xBE => "z",     // Ź, ź, Ż, ż, Ž, ž
        else => &[2]u8{ 0xC6, second_byte },
    };
}

/// Compares two strings in a case-insensitive and accent-insensitive manner.
/// Returns true if they are equal after normalization.
pub fn equalNormalized(allocator: std.mem.Allocator, a: []const u8, b: []const u8) !bool {
    const norm_a = try normalizeUtf8(allocator, a);
    defer allocator.free(norm_a);

    const norm_b = try normalizeUtf8(allocator, b);
    defer allocator.free(norm_b);

    return std.mem.eql(u8, norm_a, norm_b);
}

/// Compares two strings for sorting (case-insensitive, accent-insensitive).
/// Returns:
///   -1 if a < b
///    0 if a == b
///    1 if a > b
pub fn compareNormalized(allocator: std.mem.Allocator, a: []const u8, b: []const u8) !i8 {
    const norm_a = try normalizeUtf8(allocator, a);
    defer allocator.free(norm_a);

    const norm_b = try normalizeUtf8(allocator, b);
    defer allocator.free(norm_b);

    if (std.mem.eql(u8, norm_a, norm_b)) return 0;

    // Simple lexicographic comparison
    const min_len = @min(norm_a.len, norm_b.len);
    for (0..min_len) |i| {
        if (norm_a[i] < norm_b[i]) return -1;
        if (norm_a[i] > norm_b[i]) return 1;
    }

    // If all compared bytes are equal, shorter string comes first
    if (norm_a.len < norm_b.len) return -1;
    if (norm_a.len > norm_b.len) return 1;

    return 0;
}

// ============== TESTS ==============

test "normalizeUtf8 - basic ASCII" {
    const allocator = std.testing.allocator;

    const result = try normalizeUtf8(allocator, "Hello World");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello world", result);
}

test "normalizeUtf8 - accented characters" {
    const allocator = std.testing.allocator;

    // Test various accented characters
    const result = try normalizeUtf8(allocator, "ÀÁÂÃÄÅàáâãäå");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("aaaaaaaaaaaa", result);
}

test "normalizeUtf8 - mixed text" {
    const allocator = std.testing.allocator;

    // "Café São Paulo" should become "cafe sao paulo"
    const result = try normalizeUtf8(allocator, "Café São Paulo");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("cafe sao paulo", result);
}

test "equalNormalized" {
    const allocator = std.testing.allocator;

    // Test case insensitivity
    try std.testing.expect(try equalNormalized(allocator, "Hello", "hello"));
    try std.testing.expect(try equalNormalized(allocator, "HELLO", "hello"));

    // Test accent insensitivity
    try std.testing.expect(try equalNormalized(allocator, "café", "cafe"));
    try std.testing.expect(try equalNormalized(allocator, "São", "sao"));
    try std.testing.expect(try equalNormalized(allocator, "naïve", "naive"));
    try std.testing.expect(try equalNormalized(allocator, "résumé", "resume"));
}

test "compareNormalized" {
    const allocator = std.testing.allocator;

    // Test basic ordering
    try std.testing.expectEqual(@as(i8, -1), try compareNormalized(allocator, "apple", "banana"));
    try std.testing.expectEqual(@as(i8, 1), try compareNormalized(allocator, "banana", "apple"));
    try std.testing.expectEqual(@as(i8, 0), try compareNormalized(allocator, "apple", "apple"));

    // Test with accents
    try std.testing.expectEqual(@as(i8, 0), try compareNormalized(allocator, "café", "cafe"));
}
