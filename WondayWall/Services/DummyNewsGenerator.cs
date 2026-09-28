using WondayWall.Models;

namespace WondayWall.Services;

#if DEBUG
/// <summary>
/// デバッグ用のダミーニューストピックを生成する。
/// ニュース取得はAIサービスの責務ではないため、IAiServiceの実装から切り出し、
/// ContextServiceが具体クラス(DummyAiService)へ直接依存しなくて済むようにする。
/// </summary>
public class DummyNewsGenerator(AppConfigService configService)
{
    public List<NewsTopicItem> BuildNewsTopics()
    {
        var debugConfig = configService.Current.DebugConfig;
        var templates = new (string Title, string Summary)[]
        {
            ("ダミーニュース{n}: 週末の空模様と街イベントの見どころ", "週末に楽しめる屋外イベントと天気の変化をまとめたダミーニュースです。"),
            ("ダミーニュース{n}: 新しい生成AIツールが公開、制作ワークフローを短縮", "デザインや文章作成を支援する新機能の概要を紹介するダミーニュースです。"),
            ("ダミーニュース{n}: 夜景スポットでライトアップ企画が開始", "季節限定のライトアップと周辺のおすすめルートを扱うダミーニュースです。"),
            ("ダミーニュース{n}: 宇宙観測プロジェクトが新しい画像を公開", "星雲や銀河の観測成果をビジュアル中心に伝えるダミーニュースです。"),
            ("ダミーニュース{n}: 地域マーケットに限定スイーツが登場", "週末の買い物や散歩の参考になる食の話題を想定したダミーニュースです。"),
        };

        var newsCount = debugConfig.DummyNewsCount;
        var now = DateTime.Now;

        return Enumerable.Range(1, newsCount)
            .Select(index =>
            {
                var template = templates[(index - 1) % templates.Length];
                return new NewsTopicItem(
                    Title: template.Title.Replace("{n}", index.ToString()),
                    Summary: template.Summary,
                    Url: $"https://example.com/wondaywall/dummy-news-{index}",
                    PublishedAt: now.AddHours(-index));
            })
            .ToList();
    }
}
#endif
