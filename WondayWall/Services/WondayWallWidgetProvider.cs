using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Windows.Widgets;
using Microsoft.Windows.Widgets.Providers;
using WondayWall.Models;

namespace WondayWall.Services;

[ComVisible(true)]
[ComDefaultInterface(typeof(IWidgetProvider))]
[Guid(ClassId)]
public sealed class WondayWallWidgetProvider(
    WidgetHistoryService widgetHistoryService,
    WidgetActionService widgetActionService,
    WidgetCardBuilder widgetCardBuilder,
    ILogger<WondayWallWidgetProvider> logger) : IWidgetProvider
{
    public const string ClassId = "E2C0C47E-6B2A-49D0-AE88-01EA06D5C856";
    public const string DefinitionId = "WondayWall.History";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly Lock stateLock = new();
    private readonly Dictionary<string, WidgetProviderState> states = [];
    private readonly ManualResetEvent shutdownEvent = new(false);
    private bool recovered;

    public WaitHandle ShutdownWaitHandle => shutdownEvent;

    public void RecoverRunningWidgets()
    {
        lock (stateLock)
        {
            if (recovered)
                return;

            try
            {
                foreach (var widgetInfo in WidgetManager.GetDefault().GetWidgetInfos())
                {
                    var context = widgetInfo.WidgetContext;
                    if (!string.Equals(context.DefinitionId, DefinitionId, StringComparison.Ordinal))
                        continue;

                    states[context.Id] = ParseState(widgetInfo.CustomState);
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "既存ウィジェットの状態復元に失敗しました");
            }
            finally
            {
                recovered = true;
            }
        }
    }

    public void CreateWidget(WidgetContext widgetContext)
    {
        ValidateDefinition(widgetContext);
        lock (stateLock)
            states[widgetContext.Id] = new WidgetProviderState(0);

        UpdateWidget(widgetContext);
    }

    public void DeleteWidget(string widgetId, string customState)
    {
        lock (stateLock)
            states.Remove(widgetId);

        try
        {
            if (WidgetManager.GetDefault().GetWidgetIds() is not { Length: > 0 })
                shutdownEvent.Set();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "ウィジェット削除後の状態確認に失敗しました: {WidgetId}", widgetId);
        }
    }

    public void OnActionInvoked(WidgetActionInvokedArgs actionInvokedArgs)
    {
        var context = actionInvokedArgs.WidgetContext;
        ValidateDefinition(context);

        var size = MapSize(context.Size);
        var entries = widgetHistoryService.GetDisplayItems(size);
        var state = GetState(context.Id, actionInvokedArgs.CustomState);
        var currentIndex = ClampIndex(state.CurrentIndex, entries.Count);

        try
        {
            switch (actionInvokedArgs.Verb)
            {
                case "prev":
                    currentIndex = entries.Count == 0
                        ? 0
                        : (currentIndex - 1 + entries.Count) % entries.Count;
                    break;
                case "next":
                    currentIndex = entries.Count == 0
                        ? 0
                        : (currentIndex + 1) % entries.Count;
                    break;
                case "apply":
                    if (TryReadActionData(actionInvokedArgs.Data, out var applyData)
                        && !string.IsNullOrWhiteSpace(applyData.HistoryId))
                    {
                        widgetActionService.ApplyHistoryAsync(applyData.HistoryId).GetAwaiter().GetResult();
                    }
                    break;
                case "openNews":
                    if (TryReadActionData(actionInvokedArgs.Data, out var newsData)
                        && !string.IsNullOrWhiteSpace(newsData.HistoryId)
                        && newsData.NewsIndex is not null)
                    {
                        widgetActionService.OpenNews(newsData.HistoryId, newsData.NewsIndex.Value);
                    }
                    break;
                default:
                    logger.LogWarning("未対応のウィジェット操作です: {Action}", actionInvokedArgs.Verb);
                    break;
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "ウィジェット操作に失敗しました: {Action}", actionInvokedArgs.Verb);
        }

        SetState(context.Id, new WidgetProviderState(currentIndex));
        UpdateWidget(context);
    }

    public void OnWidgetContextChanged(WidgetContextChangedArgs contextChangedArgs)
    {
        ValidateDefinition(contextChangedArgs.WidgetContext);
        UpdateWidget(contextChangedArgs.WidgetContext);
    }

    public void Activate(WidgetContext widgetContext)
    {
        ValidateDefinition(widgetContext);
        _ = GetState(widgetContext.Id, null);
        UpdateWidget(widgetContext);
    }

    public void Deactivate(string widgetId)
    {
        // 非表示中は定期更新を行わないため、停止対象の処理はない。
    }

    private void UpdateWidget(WidgetContext context)
    {
        var size = MapSize(context.Size);
        var entries = widgetHistoryService.GetDisplayItems(size);
        var state = GetState(context.Id, null);
        var currentIndex = ClampIndex(state.CurrentIndex, entries.Count);
        var normalizedState = new WidgetProviderState(currentIndex);
        SetState(context.Id, normalizedState);

        var entry = entries.Count == 0 ? null : entries[currentIndex];
        var options = new WidgetUpdateRequestOptions(context.Id)
        {
            Template = widgetCardBuilder.Build(size, entry, currentIndex, entries.Count),
            Data = "{}",
            CustomState = JsonSerializer.Serialize(normalizedState, JsonOptions),
        };

        WidgetManager.GetDefault().UpdateWidget(options);
    }

    private WidgetProviderState GetState(string widgetId, string? customState)
    {
        lock (stateLock)
        {
            if (states.TryGetValue(widgetId, out var state))
                return state;

            state = ParseState(customState);
            states[widgetId] = state;
            return state;
        }
    }

    private void SetState(string widgetId, WidgetProviderState state)
    {
        lock (stateLock)
            states[widgetId] = state;
    }

    private static WidgetProviderState ParseState(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return new WidgetProviderState(0);

        try
        {
            return JsonSerializer.Deserialize<WidgetProviderState>(value, JsonOptions)
                ?? new WidgetProviderState(0);
        }
        catch (JsonException)
        {
            return new WidgetProviderState(0);
        }
    }

    private static bool TryReadActionData(string? value, out WidgetActionData data)
    {
        try
        {
            data = JsonSerializer.Deserialize<WidgetActionData>(value ?? "{}", JsonOptions)
                ?? new WidgetActionData();
            return true;
        }
        catch (JsonException)
        {
            data = new WidgetActionData();
            return false;
        }
    }

    private static int ClampIndex(int index, int totalCount)
    {
        if (totalCount <= 0)
            return 0;

        return Math.Clamp(index, 0, totalCount - 1);
    }

    private static WidgetDisplaySize MapSize(WidgetSize size)
        => size switch
        {
            WidgetSize.Small => WidgetDisplaySize.Small,
            WidgetSize.Medium => WidgetDisplaySize.Medium,
            _ => WidgetDisplaySize.Large,
        };

    private static void ValidateDefinition(WidgetContext context)
    {
        if (!string.Equals(context.DefinitionId, DefinitionId, StringComparison.Ordinal))
            throw new InvalidOperationException($"未対応のウィジェット定義です: {context.DefinitionId}");
    }

    private sealed record WidgetProviderState(int CurrentIndex);

    private sealed record WidgetActionData(string? HistoryId = null, int? NewsIndex = null);
}
