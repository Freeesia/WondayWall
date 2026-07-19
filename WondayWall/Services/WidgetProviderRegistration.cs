using System.Runtime.InteropServices;
using Microsoft.Windows.Widgets.Providers;
using WinRT;

namespace WondayWall.Services;

internal sealed class WidgetProviderRegistration : IDisposable
{
    private readonly uint registrationCookie;
    private bool disposed;

    private WidgetProviderRegistration(uint registrationCookie)
    {
        this.registrationCookie = registrationCookie;
    }

    public static WidgetProviderRegistration Register(WondayWallWidgetProvider provider)
    {
        var classId = Guid.Parse(WondayWallWidgetProvider.ClassId);
        var result = CoRegisterClassObject(
            classId,
            new WidgetProviderClassFactory(provider),
            ClassContext.LocalServer,
            RegistrationClass.MultipleUse,
            out var cookie);
        Marshal.ThrowExceptionForHR(result);
        return new WidgetProviderRegistration(cookie);
    }

    public void Dispose()
    {
        if (disposed)
            return;

        _ = CoRevokeClassObject(registrationCookie);
        disposed = true;
    }

    [DllImport("ole32.dll")]
    private static extern int CoRegisterClassObject(
        [MarshalAs(UnmanagedType.LPStruct)] Guid classId,
        [MarshalAs(UnmanagedType.IUnknown)] object classFactory,
        ClassContext context,
        RegistrationClass flags,
        out uint registrationCookie);

    [DllImport("ole32.dll")]
    private static extern int CoRevokeClassObject(uint registrationCookie);

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("00000001-0000-0000-C000-000000000046")]
    private interface IClassFactory
    {
        [PreserveSig]
        int CreateInstance(IntPtr outer, ref Guid interfaceId, out IntPtr instance);

        [PreserveSig]
        int LockServer([MarshalAs(UnmanagedType.Bool)] bool lockServer);
    }

    private sealed class WidgetProviderClassFactory(WondayWallWidgetProvider provider) : IClassFactory
    {
        public int CreateInstance(IntPtr outer, ref Guid interfaceId, out IntPtr instance)
        {
            instance = IntPtr.Zero;
            if (outer != IntPtr.Zero)
                return ClassNoAggregation;

            if (interfaceId != typeof(WondayWallWidgetProvider).GUID
                && interfaceId != typeof(IWidgetProvider).GUID
                && interfaceId != IUnknownId)
                return NoInterface;

            instance = MarshalInspectable<IWidgetProvider>.FromManaged(provider);
            return 0;
        }

        public int LockServer(bool lockServer) => 0;
    }

    private enum ClassContext : uint
    {
        LocalServer = 0x4,
    }

    private enum RegistrationClass : uint
    {
        MultipleUse = 0x1,
    }

    private static readonly Guid IUnknownId = Guid.Parse("00000000-0000-0000-C000-000000000046");
    private const int ClassNoAggregation = unchecked((int)0x80040110);
    private const int NoInterface = unchecked((int)0x80004002);
}
