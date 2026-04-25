using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization.Metadata;
using System.IO;
using WondayWall.ComponentModel;

namespace WondayWall.Utils;

public static class JsonFileHelper
{
    private static readonly DefaultJsonTypeInfoResolver TypeInfoResolver = CreateTypeInfoResolver();

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        TypeInfoResolver = TypeInfoResolver,
    };

    private static DefaultJsonTypeInfoResolver CreateTypeInfoResolver()
    {
        var resolver = new DefaultJsonTypeInfoResolver();
        resolver.Modifiers.Add(CredentialSecretJsonConverter.Apply);
        return resolver;
    }

    public static T? Load<T>(string filePath) where T : class
    {
        if (!File.Exists(filePath))
            return null;

        try
        {
            var json = File.ReadAllText(filePath);
            return JsonSerializer.Deserialize<T>(json, Options);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Failed to load JSON from '{filePath}': {ex.Message}");
            return null;
        }
    }

    public static void Save<T>(string filePath, T value)
    {
        var dir = Path.GetDirectoryName(filePath);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);

        var json = JsonSerializer.Serialize(value, Options);
        File.WriteAllText(filePath, json);
    }
}
