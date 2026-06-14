using System.Text.Json;
using WondayWall.Models;

namespace WondayWall.Services;

public class WidgetCardBuilder
{
    public string Build(WidgetDisplaySize size, WidgetHistoryEntry? entry, int currentIndex, int totalCount)
        => JsonSerializer.Serialize(CreateCardObject(size, entry, currentIndex, totalCount));

    private static object CreateCardObject(WidgetDisplaySize size, WidgetHistoryEntry? entry, int currentIndex, int totalCount)
    {
        if (entry is null)
        {
            return new
            {
                type = "AdaptiveCard",
                version = "1.5",
                body = new object[]
                {
                    new
                    {
                        type = "TextBlock",
                        text = "表示できる生成履歴がありません",
                        wrap = true,
                        weight = "Bolder",
                    },
                },
            };
        }

        var actions = new List<object>
        {
            CreateApplyAction(entry.HistoryId),
        };

        if (size == WidgetDisplaySize.Large)
        {
            actions.Add(CreateNavigateAction("前へ", "prev"));
            actions.Add(CreateNavigateAction("次へ", "next"));
        }

        return new
        {
            type = "AdaptiveCard",
            version = "1.5",
            backgroundImage = new
            {
                url = entry.BackgroundImagePath,
                fillMode = "Cover",
                horizontalAlignment = "Center",
                verticalAlignment = "Center",
            },
            body = BuildBody(size, entry, currentIndex, totalCount),
            actions,
        };
    }

    private static object[] BuildBody(WidgetDisplaySize size, WidgetHistoryEntry entry, int currentIndex, int totalCount)
    {
        var body = new List<object>();

        if (size is WidgetDisplaySize.Small or WidgetDisplaySize.Large)
        {
            body.Add(new
            {
                type = "TextBlock",
                text = $"生成日時: {entry.ExecutedAt:yyyy/MM/dd HH:mm}",
                weight = "Bolder",
                wrap = true,
                color = "Light",
            });
        }

        if (size != WidgetDisplaySize.Small)
        {
            foreach (var news in entry.NewsItems.Take(3))
            {
                body.Add(new
                {
                    type = "TextBlock",
                    text = BuildNewsText(news, size),
                    wrap = true,
                    color = "Light",
                    selectAction = string.IsNullOrWhiteSpace(news.Url)
                        ? null
                        : CreateOpenNewsAction(entry.HistoryId, news.Index),
                });
            }
        }

        if (size == WidgetDisplaySize.Large)
        {
            body.Add(new
            {
                type = "TextBlock",
                text = $"{currentIndex + 1} / {Math.Max(totalCount, 1)}",
                color = "Light",
                horizontalAlignment = "Right",
            });
        }

        return body.ToArray();
    }

    private static string BuildNewsText(WidgetNewsEntry news, WidgetDisplaySize size)
    {
        if (size == WidgetDisplaySize.Medium)
            return news.Title;

        return news.PublishedAt is null
            ? news.Title
            : $"{news.Title} ({news.PublishedAt:yyyy/MM/dd HH:mm})";
    }

    private static object CreateApplyAction(string historyId)
        => new
        {
            type = "Action.Execute",
            title = "この画像を壁紙にする",
            verb = "apply",
            data = new
            {
                historyId,
            },
        };

    private static object CreateNavigateAction(string title, string verb)
        => new
        {
            type = "Action.Execute",
            title,
            verb,
        };

    private static object CreateOpenNewsAction(string historyId, int newsIndex)
        => new
        {
            type = "Action.Execute",
            verb = "openNews",
            data = new
            {
                historyId,
                newsIndex,
            },
        };
}
