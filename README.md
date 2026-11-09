# MediaStorm for Apple TV

A native SwiftUI tvOS client for the [MediaStorm](https://github.com/godver3/mediastorm)
server. Playback uses [AetherEngine](https://github.com/superuser404notfound/AetherEngine).

## Building

Requires a current Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open StrmrTV.xcodeproj
```

Set your own development team in Xcode to run on a device.

`Vendor/IrohBridge.xcframework` is the prebuilt iroh remote-access library; the open-source
crates it links are listed in `Vendor/THIRD_PARTY_LICENSES.txt`.

The iPhone / iPad app (`StrmrMobile`) casts to Chromecasts with Google's Cast SDK, which Xcode
fetches through Google's Swift package (`github.com/googlecast/google-cast-ios-sdk`) at build
time; nothing of it is kept in this repository. DLNA casting is plain SSDP and UPnP.

## License

MIT. See [LICENSE](LICENSE). AetherEngine is licensed separately under the LGPL v3, and the
crates in the iroh library under their own licences. The Google Cast SDK is Google's, under
the Google APIs Terms of Service.
