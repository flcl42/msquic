# MsQuic.Edge

This package supplies the edge fork's MsQuic binaries to .NET applications using
`System.Net.Quic` or HTTP/3. The builds statically link the fork's bundled OpenSSL.

Download the `MsQuic.Edge` artifact from a successful **Build MsQuic Edge** run.
Extract the `.nupkg` into a local NuGet source and add an explicit package reference
to the executable project. Replace the version below with the one in the artifact.

```xml
<PackageReference Include="MsQuic.Edge" Version="2.7.0-edge.1.1" />
```

```sh
dotnet nuget add source /path/to/packages --name msquic-edge
dotnet build
dotnet publish -r linux-x64 --self-contained
dotnet publish -r linux-x64 -p:PublishAot=true
```

Windows supports `win-x86`, `win-x64`, and `win-arm64` on .NET 10 and newer.
The package enables app-local MsQuic and copies `msquic.dll` beside the app.
For a Windows single-file publish, ship `msquic.dll` alongside the executable.
Set an explicit RID when deploying to a different Windows architecture.
[Microsoft's app-local MsQuic setting](https://learn.microsoft.com/dotnet/core/runtime-config/networking#app-local-msquic-windows)

Linux uses the package's native assets for glibc (x86, x64, Arm, and Arm64) and
musl (x64 and Arm64). The macOS assets are for x64 and Arm64. For a Linux or macOS
single-file publish, set `IncludeNativeLibrariesForSelfExtract=true` to bundle
the MsQuic library and extract it when the app starts.

The workflow also uploads native Android (Arm, Arm64 and x64) and iOS builds for
direct integration. The iOS libraries are static archives for Arm64 devices and
Arm64 and x64 simulators. The .NET package supplies the desktop RIDs listed above.
