using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AntigasLauncher;

internal sealed record NewsItem(string Date, string Title);

// Headlines of the site's changelog (site/project-updates.json).
internal static class NewsService
{
    private const string NewsUrl = "https://tibia74.tech/project-updates.json";

    private sealed class Entry
    {
        [JsonPropertyName("date")] public string? Date { get; init; }
        [JsonPropertyName("title")] public string? Title { get; init; }
    }

    public static async Task<IReadOnlyList<NewsItem>> GetAsync(CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, NewsUrl);
        using var response = await ReleaseService.Http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        var bytes = await BoundedContentReader.ReadAsync(stream, 512 * 1024, cancellationToken);
        return Parse(bytes);
    }

    internal static IReadOnlyList<NewsItem> Parse(byte[] json)
    {
        var entries = JsonSerializer.Deserialize<List<Entry>>(json) ?? [];
        var news = new List<NewsItem>();
        foreach (var entry in entries)
        {
            if (string.IsNullOrWhiteSpace(entry.Title)) continue;
            var date = DateOnly.TryParseExact(entry.Date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed)
                ? parsed.ToString("d MMMM yyyy", CultureInfo.InvariantCulture) : "";
            var title = entry.Title.Trim().TrimEnd('.');
            news.Add(new NewsItem(date, title.Length > 120 ? title[..120] : title));
            if (news.Count == 6) break;
        }
        return news;
    }
}
