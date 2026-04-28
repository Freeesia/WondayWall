using System;
using System.Diagnostics;
using WixSharp;
using Path = System.IO.Path;

const string Manufacturer = "StudioFreesia";
const string App = "WondayWall";
const string ArtifactsDir = @"..\artifacts";
const string Executable = $"{App}.exe";

var exePath = Path.Combine(Environment.CurrentDirectory, ArtifactsDir, Executable);
var info = FileVersionInfo.GetVersionInfo(exePath);
var version = info.FileVersion;

var project = new ManagedProject(App,
    new Dir(@$"%LocalAppData%\{Manufacturer}\{App}",
        new File(exePath) { AddCloseAction = true },
        new Files(Path.Combine(ArtifactsDir, "*.*"), p => !p.EndsWith(Executable))),
    // スタートメニューにショートカットを追加
    new Dir(@$"%ProgramMenu%\{Manufacturer}\{App}",
        new ExeFileShortcut(App, $"[INSTALLDIR]{App}", "")));

project.RebootSupressing = RebootSupressing.Suppress;
project.GUID = new("A1B2C3D4-E5F6-7890-ABCD-EF1234567890");
project.Platform = Platform.x64;
project.Language = "ja-JP";
project.Version = new(version);

// コントロールパネルの情報を設定
project.ControlPanelInfo = new()
{
    Manufacturer = Manufacturer,
    ProductIcon = @"..\WondayWall\Assets\AppIcon.ico",
    InstallLocation = "[INSTALLDIR]",
    UrlInfoAbout = "https://github.com/Freeesia/WondayWall",
    UrlUpdateInfo = "https://github.com/Freeesia/WondayWall/releases",
};

project.MajorUpgrade = MajorUpgrade.Default;

project.BackgroundImage = @"installer_back.png";
project.ValidateBackgroundImage = false;
project.BannerImage = @"installer_banner.png";

// ユーザーレベルのインストールを強制する
project.Scope = InstallScope.perUser;

// ライセンスファイルの設定
project.LicenceFile = @"..\Terms_of_Use.rtf";

// インストール後にアプリを起動するオプション
project.AfterInstall += static e =>
{
    // アンインストール時には起動しない
    if (!e.IsUninstalling)
    {
        Process.Start(e.InstallDir.PathCombine(Executable));
    }
};

// WXS ファイルを generated/ フォルダに生成する（MSI のビルドは WondayWall.Installer.wixproj で行う）
// generated/ は .gitignore で除外されているため、生成物がリポジトリに混入しない
project.OutDir = "generated";
Compiler.BuildWxs(project);
