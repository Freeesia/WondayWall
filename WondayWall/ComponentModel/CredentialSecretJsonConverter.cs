using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;
using WondayWall.Utils;

namespace WondayWall.ComponentModel;

internal sealed class CredentialSecretJsonConverter(string jsonPath) : JsonConverter<string>
{
    public override bool HandleNull => true;

    public static void Apply(JsonTypeInfo typeInfo)
    {
        if (typeInfo.Kind != JsonTypeInfoKind.Object)
            return;

        foreach (var property in typeInfo.Properties)
        {
            if (property.AttributeProvider?.IsDefined(typeof(CredentialSecretAttribute), inherit: true) != true)
                continue;

            if (property.PropertyType != typeof(string))
                throw new InvalidOperationException("[CredentialSecret] can only be used on string properties.");

            property.CustomConverter = new CredentialSecretJsonConverter($"$.{property.Name}");
        }
    }

    public override string Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Null)
            return string.Empty;

        var storedId = reader.GetString();
        return storedId == jsonPath
            ? CredentialSecretStore.Read(jsonPath)
            : string.Empty;
    }

    public override void Write(
        Utf8JsonWriter writer,
        string value,
        JsonSerializerOptions options)
    {
        if (string.IsNullOrEmpty(value))
        {
            CredentialSecretStore.Delete(jsonPath);
            writer.WriteStringValue(string.Empty);
            return;
        }

        CredentialSecretStore.Write(jsonPath, value);
        writer.WriteStringValue(jsonPath);
    }
}
