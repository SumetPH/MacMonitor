# MacMonitor

<!-- macos-app:project:start -->
## เกี่ยวกับแอพ

แอพ menu bar จัดการจอภาพแบบละเอียด: resolution, HiDPI scaled mode, refresh rate, rotation, brightness/contrast ผ่าน DDC/CI, enable/disable จอภายนอก, HiDPI display override, Clear Config/Uninstall แบบอิง manifest และ export diagnostics

## สิทธิ์ macOS ที่ใช้

- สิทธิ์ผู้ดูแลระบบ (privileged AppleScript) ตอนเขียน/ลบไฟล์ override ใต้ `/Library/Displays/Contents/Resources/Overrides/`
- Launch at Login ผ่าน `SMAppService`

## ข้อควรระวังเฉพาะแอพ

- ใช้ private API: `CGConfigureDisplayRotation` (CoreGraphics), `DisplayServices.framework` (brightness จอ Apple/built-in) และ IOKit I2C สำหรับ DDC/CI ทุกจุดต้อง fail แบบปลอดภัยเมื่อไม่รองรับ
- การเปลี่ยน resolution ต้องมีหน้าต่างยืนยัน 15 วินาทีและ rollback ถ้าไม่ยืนยัน ห้ามตัดขั้นตอนนี้
- ไฟล์ที่แอพสร้างหรือ backup ต้องบันทึกใน `~/Library/Application Support/MacMonitor/manifest.json` เพื่อให้ Clear Config/Uninstall ลบได้ครบ
- diagnostics มี hardware identifier ของจอ (UUID, serial) ห้ามส่งออกนอกเครื่องอัตโนมัติ
- ทดสอบตอน start ด้วย `Scripts/check-startup.sh <executable>` ซึ่ง grep stdout หาบรรทัด `[AppDelegate] Mac Monitor started successfully.` จึงเป็น `print` จุดเดียวที่ตั้งใจเก็บไว้ใน `App/AppDelegate.swift` ห้ามลบหรือเปลี่ยนข้อความถ้าไม่แก้สคริปต์ไปพร้อมกัน
<!-- macos-app:project:end -->

<!-- macos-app:standard:start v2 -->
## Stack

- Swift 6 + SwiftPM เท่านั้น ห้ามสร้าง `.xcodeproj` หรือ `.xcworkspace`
- ใช้ Swift 6 language mode (ค่าเริ่มต้นของ tools 6.x) ห้ามใส่ `swiftLanguageModes: [.v5]`
- AppKit สำหรับ app lifecycle, menu bar, window และ event tap; SwiftUI สำหรับ view ข้างใน
- เป็นแอพ menu bar (`LSUIElement = true`) เว้นแต่ส่วน "เกี่ยวกับแอพ" ระบุไว้เป็นอย่างอื่น
- ห้ามเพิ่ม dependency ภายนอกก่อนถามผู้ใช้ ถ้าต้องใช้โค้ดจากที่อื่นให้ vendor ไว้ใน `Vendor/` พร้อม license

## โครงสร้าง repo

```
MacMonitor/
├── AGENTS.md              # ไฟล์นี้ (CLAUDE.md มีแค่ @AGENTS.md)
├── README.md
├── Package.swift
├── Sources/
│   ├── MacMonitor/      # executable target: AppKit/SwiftUI
│   │   ├── App/           # entry point (main.swift หรือ type ที่มี @main), AppDelegate, MenuBarController, controller ระดับแอพ
│   │   ├── Views/         # SwiftUI view, NSWindow/NSPanel
│   │   └── Services/      # ส่วนที่แตะระบบ: permission, event tap, login item, private API, settings, file I/O
│   ├── MacMonitorCore/  # library target: logic ล้วน ไม่ import AppKit/SwiftUI ไม่มี side effect
│   └── MacMonitorBridge/ # (ถ้าจำเป็น) C/ObjC bridge สำหรับ private API
├── Tests/
│   ├── MacMonitorCoreTests/
│   └── MacMonitorTests/ # (ถ้าจำเป็น) test พฤติกรรม AppKit ของ target แอพ
├── Scripts/
│   ├── dev-app.sh         # build + run แบบ debug
│   └── build-app.sh       # สร้าง dist/<Display Name>.app
├── Assets/AppIcon.png     # 1024x1024
├── Docs/                  # spec, idea, init prompt
├── Vendor/                # (ถ้ามี) โค้ดภายนอกที่ vendor มา ห้ามเก็บโฟลเดอร์ว่าง
└── dist/                  # output (gitignored)
```

- ไฟล์ที่ห้ามอยู่ที่ root: `Info.plist`, `*.icns`, `build-app.sh` หรือสคริปต์อื่น (สคริปต์ทั้งหมดอยู่ใน `Scripts/`)
- ชื่อโฟลเดอร์ใช้ตามนี้ตรงตัว (`Docs` ไม่ใช่ `docs`, `Scripts` ไม่ใช่ `scripts`)
- ไฟล์ `.swift` ใน target แอพต้องอยู่ใน `App/`, `Views/` หรือ `Services/` ห้ามวางที่ root ของ target type ข้อมูลที่ต้องใช้ AppKit ให้วางไว้ข้าง service ที่ใช้มัน
- ไม่ใช้ `resources:` ใน `Package.swift` รูปและไฟล์ที่ต้องอยู่ใน bundle ให้วางใน `Assets/` แล้วให้ `build-app.sh` copy เข้า `Contents/Resources`

## คำสั่ง

| งาน | คำสั่ง |
|---|---|
| รันระหว่างพัฒนา | `Scripts/dev-app.sh` |
| test | `swift test` |
| build `.app` | `Scripts/build-app.sh [debug\|release]` → `dist/Mac Monitor.app` |

- `Info.plist` สร้างใน `Scripts/build-app.sh` ที่เดียว ถ้าจะแก้ version, bundle id หรือ usage description ให้แก้ที่ตัวแปรด้านบนของสคริปต์
- Bundle id ของแอพใหม่: `dev.sumetph.MacMonitor` แอพเก่าที่ใช้ id อื่นอยู่แล้วห้ามเปลี่ยน (สิทธิ์ macOS ผูกกับ bundle id) และให้ระบุ id จริงไว้ในส่วน project
- Sign ด้วย `Apple Development` เพื่อให้สิทธิ์ Accessibility/Input Monitoring ไม่หายหลัง rebuild (override ด้วย `CODE_SIGN_IDENTITY=-`)

## แนวทางเขียนโค้ด

- logic ที่ test ได้ (parser, state machine, การคำนวณ layout, model) อยู่ใน `MacMonitorCore` ส่วน side effect ทั้งหมด (UserDefaults, file I/O, คำสั่งระบบ, private API) อยู่ใน `Services/` ของ target แอพ
- โค้ดที่แตะ UI ใส่ `@MainActor`
- ถ้าแอพต้องใช้สิทธิ์ ให้รวมการเช็กและขอสิทธิ์ไว้ที่ `Services/PermissionManager.swift` ที่เดียว
- ค่า settings เก็บใน `UserDefaults` ผ่าน type เดียว (`AppSettings`) ห้ามเรียก `UserDefaults` กระจายหลายที่ (`@AppStorage` ใช้ได้ถ้า key มาจาก `AppSettings`)
- log ด้วย `os.Logger` ห้ามใช้ `print` และ `NSLog` ให้ hardcode subsystem เป็น bundle id (เพราะ `Bundle.main.bundleIdentifier` เป็น nil ตอน `swift run`) และใช้ category ตามส่วนของโค้ด ดู log ด้วย `log stream --level info --predicate 'subsystem == "<bundle id>"'`
- ข้อยกเว้นเดียวของ `print`/`fputs` คือข้อความตอน start ที่สคริปต์หรือ terminal ต้องอ่าน ให้ใส่ comment `// macos-app:allow-print <เหตุผล>` ไว้บรรทัดเดียวกัน
- ถ้าใช้ private API ให้รวมไว้ในไฟล์ `PrivateApis.swift` หรือ Bridge target พร้อม comment ว่ามาจากไหน และ fail แบบปลอดภัยถ้า symbol ไม่มี (ใช้ `dlsym` แทน `@_silgen_name` ซึ่งทำให้แอพเปิดไม่ขึ้นถ้า symbol หาย)
- ห้าม hardcode path ของเครื่อง ให้ใช้ `FileManager` หา Application Support ของแอพ
- `nonisolated(unsafe)` และ `@unchecked Sendable` ใช้ได้เมื่อมี comment อธิบายว่าทำไมปลอดภัยเท่านั้น
- ถ้าเปลี่ยนชื่อ target ห้ามเปลี่ยนชื่อโฟลเดอร์ใน Application Support, UserDefaults key และ Keychain item เดิม เพื่อไม่ให้ข้อมูลของผู้ใช้หาย

## Tests

- ใช้ Swift Testing (`import Testing`, `@Test`, `#expect`) ห้ามใช้ XCTest และทดสอบ target `MacMonitorCore` เป็นหลัก
- test พฤติกรรม AppKit ที่แยกเป็น Core ไม่ได้ (hit testing, focus ของ panel) ให้วางใน `Tests/MacMonitorTests` ส่วนโค้ดที่ต้องใช้สิทธิ์จริงไม่ต้องเขียน test
- Swift Testing รัน test แบบ parallel ถ้า test ใช้ state กลางร่วมกัน (เช่น URLProtocol stub) ให้ใช้ `@Suite(.serialized)`
- test ห้ามแตะข้อมูลจริงของผู้ใช้ (Application Support, UserDefaults domain ของแอพ, Keychain) ให้ใช้ temp dir หรือ suite แยก
- เมื่อย้าย logic เข้า Core ให้เขียน test ให้ส่วนที่ย้ายด้วย ส่วนจำนวน test เดิมห้ามลดลง

## ก่อนบอกว่างานเสร็จ

1. `swift build` และ `swift test` ผ่าน
2. ถ้าแก้ `Scripts/` หรือ `Package.swift` ต้องรัน `Scripts/build-app.sh` ผ่านด้วย
3. ไม่ต้องเปิดแอพเพื่อทดสอบ ถ้าแอพดัก input (event tap) หรือเปลี่ยนค่าระบบ ถ้าเปิดไว้ทดสอบต้องปิดด้วย PID หรือ `pkill -f "dist/Mac Monitor.app"` ห้ามใช้ `pkill -x` เพราะจะปิดตัวที่ผู้ใช้ติดตั้งไว้ใน `/Applications` ด้วย
4. ถ้ามีการเปลี่ยนสิทธิ์ ฟีเจอร์ หรือคำสั่ง ให้อัปเดต README และส่วน project ด้านบนของไฟล์นี้
<!-- macos-app:standard:end -->
