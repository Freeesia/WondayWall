namespace WondayWall.Models;

public record UpdateInfo(
    string Version,
    string Url,
    string? Path,
    DateTime CheckedAt,
    bool Skip);
