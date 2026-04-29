using System.Text.Json.Serialization;

namespace WondayWall.Models;

[JsonConverter(typeof(JsonStringEnumConverter<GoogleAiServiceTier>))]
public enum GoogleAiServiceTier
{
    Standard,
    Flex,
}
