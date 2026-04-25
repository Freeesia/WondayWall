using Windows.Security.Credentials;

namespace WondayWall.Utils;

internal static class CredentialSecretStore
{
    public const string ResourceName = "StudioFreesia.WondayWall.AppConfig";

    private const uint ElementNotFound = 0x80070490;
    private static readonly PasswordVault Vault = new();
    private static readonly object SyncRoot = new();

    public static string Read(string jsonPath)
    {
        try
        {
            lock (SyncRoot)
            {
                var credential = Vault.Retrieve(ResourceName, jsonPath);
                credential.RetrievePassword();
                return credential.Password ?? string.Empty;
            }
        }
        catch (Exception ex) when (IsElementNotFound(ex))
        {
            return string.Empty;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Failed to read credential secret '{jsonPath}': {ex.Message}");
            return string.Empty;
        }
    }

    public static void Write(string jsonPath, string value)
    {
        lock (SyncRoot)
        {
            DeleteCore(jsonPath);

            if (string.IsNullOrEmpty(value))
                return;

            Vault.Add(new PasswordCredential(ResourceName, jsonPath, value));
        }
    }

    public static void Delete(string jsonPath)
    {
        lock (SyncRoot)
        {
            DeleteCore(jsonPath);
        }
    }

    private static void DeleteCore(string jsonPath)
    {
        try
        {
            var credential = Vault.Retrieve(ResourceName, jsonPath);
            Vault.Remove(credential);
        }
        catch (Exception ex) when (IsElementNotFound(ex))
        {
        }
    }

    private static bool IsElementNotFound(Exception ex)
        => unchecked((uint)ex.HResult) == ElementNotFound;
}
