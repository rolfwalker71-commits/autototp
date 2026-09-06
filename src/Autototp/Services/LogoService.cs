using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Autototp.Services;

public sealed class LogoService
{
    private const int MaxEdgePixels = 256;
    private static readonly Uri DefaultLogoUri = new("pack://application:,,,/Assets/default-logo.png");
    private static ImageSource? _defaultLogo;

    public LogoService(string dataDirectory)
    {
        LogosDirectory = Path.Combine(dataDirectory, "logos");
        Directory.CreateDirectory(LogosDirectory);
    }

    public string LogosDirectory { get; }

    public string SaveFromFile(Guid accountId, string sourcePath)
    {
        if (string.IsNullOrWhiteSpace(sourcePath) || !File.Exists(sourcePath))
        {
            throw new FileNotFoundException("Die Logo-Datei wurde nicht gefunden.", sourcePath);
        }

        Directory.CreateDirectory(LogosDirectory);

        var frame = DecodeLargestFrame(sourcePath);
        var scaled = ScaleToMax(frame, MaxEdgePixels);
        var destName = $"{accountId:N}.png";
        var destPath = Path.Combine(LogosDirectory, destName);
        var tempPath = destPath + ".tmp";

        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(scaled));

        using (var output = File.Create(tempPath))
        {
            encoder.Save(output);
        }

        File.Copy(tempPath, destPath, overwrite: true);
        File.Delete(tempPath);
        return destName;
    }

    public void Delete(string? logoFileName)
    {
        var path = ResolvePath(logoFileName);
        if (path is null || !IsManagedPath(path))
        {
            return;
        }

        try
        {
            File.Delete(path);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    public bool IsManagedPath(string path)
    {
        var logosFull = Path.GetFullPath(LogosDirectory)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var fileFull = Path.GetFullPath(path);
        return fileFull.StartsWith(logosFull + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    }

    public string? ResolvePath(string? logoFileName)
    {
        if (string.IsNullOrWhiteSpace(logoFileName))
        {
            return null;
        }

        if (Path.IsPathRooted(logoFileName) && File.Exists(logoFileName))
        {
            return logoFileName;
        }

        var combined = Path.Combine(LogosDirectory, logoFileName);
        return File.Exists(combined) ? combined : null;
    }

    public ImageSource LoadImage(string? logoFileName)
    {
        var path = ResolvePath(logoFileName);
        return path is null ? LoadDefault() : LoadImageFromPath(path);
    }

    public static ImageSource LoadDefault()
    {
        if (_defaultLogo is not null)
        {
            return _defaultLogo;
        }

        var image = new BitmapImage();
        image.BeginInit();
        image.UriSource = DefaultLogoUri;
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.EndInit();
        image.Freeze();
        _defaultLogo = image;
        return image;
    }

    public static ImageSource LoadImageFromPath(string path)
    {
        using var stream = File.OpenRead(path);
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.StreamSource = stream;
        image.EndInit();
        image.Freeze();
        return image;
    }

    public static bool TryCreatePreview(string path, out ImageSource? image, out string error)
    {
        image = null;
        error = string.Empty;
        try
        {
            DecodeLargestFrame(path);
            image = LoadImageFromPath(path);
            return true;
        }
        catch (Exception ex)
        {
            error = $"Das Bild konnte nicht geladen werden: {ex.Message}";
            return false;
        }
    }

    private static BitmapSource DecodeLargestFrame(string path)
    {
        using var stream = File.OpenRead(path);
        BitmapDecoder decoder;
        try
        {
            decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        }
        catch (NotSupportedException)
        {
            throw new InvalidOperationException("Dieses Bildformat wird nicht unterstützt. Bitte PNG, JPEG, ICO, BMP oder GIF wählen.");
        }
        catch (FileFormatException)
        {
            throw new InvalidOperationException("Die Datei ist kein gültiges Bild. Bitte PNG, JPEG, ICO, BMP oder GIF wählen.");
        }

        if (decoder.Frames.Count == 0)
        {
            throw new InvalidOperationException("Die Datei enthält kein Bild.");
        }

        return decoder.Frames
            .OrderByDescending(f => f.PixelWidth * (long)f.PixelHeight)
            .First();
    }

    private static BitmapSource ScaleToMax(BitmapSource source, int maxSize)
    {
        if (source.PixelWidth <= maxSize && source.PixelHeight <= maxSize)
        {
            return source;
        }

        var scale = Math.Min((double)maxSize / source.PixelWidth, (double)maxSize / source.PixelHeight);
        var scaled = new TransformedBitmap(source, new ScaleTransform(scale, scale));
        scaled.Freeze();
        return scaled;
    }
}
