# MediaStorm for Apple TV

A native SwiftUI tvOS client for the [MediaStorm](https://github.com/godver3/mediastorm)
server. Playback uses [AetherEngine](https://github.com/superuser404notfound/AetherEngine).

## Building

Requires a current Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open StrmrTV.xcodeproj
```

Set your own development team in Xcode to run on a device. The app links the iroh
remote-access library at `Vendor/IrohBridge.xcframework`, which is not included in this
repository.

## License

MIT. See [LICENSE](LICENSE). AetherEngine is licensed separately under the LGPL v3.
