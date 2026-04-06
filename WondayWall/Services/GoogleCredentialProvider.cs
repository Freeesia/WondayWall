using System.IO;
using System.Reflection;
using System.Text.Json;

namespace WondayWall.Services;

internal static class GoogleCredentialProvider
{
    private static readonly Lazy<(string ClientId, string ClientSecret)> Credentials =
        new(LoadCredentials);

    public static string ClientId => Credentials.Value.ClientId;
    public static string ClientSecret => Credentials.Value.ClientSecret;

    private static (string ClientId, string ClientSecret) LoadCredentials()
    {
        var assembly = Assembly.GetExecutingAssembly();
        const string resourceName = "WondayWall.Resources.google_client_secret.json";

        using var stream = assembly.GetManifestResourceStream(resourceName);
        if (stream == null)
            return (string.Empty, string.Empty);

        using var reader = new StreamReader(stream);
        var json = reader.ReadToEnd();

        try
        {
            var doc = JsonDocument.Parse(json);
            var installed = doc.RootElement.GetProperty("installed");
            var clientId = installed.GetProperty("client_id").GetString() ?? string.Empty;
            var clientSecret = installed.GetProperty("client_secret").GetString() ?? string.Empty;
            return (clientId, clientSecret);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Failed to load Google credentials from embedded resource: {ex.Message}");
            return (string.Empty, string.Empty);
        }
    }
}
