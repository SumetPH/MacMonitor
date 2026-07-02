# Mac Monitor

Mac Monitor คือแอปเมนูบาร์สำหรับ macOS ที่ช่วยจัดการจอภาพแบบละเอียด เช่น ความละเอียดหน้าจอ, HiDPI scaled resolutions, refresh rate, rotation, preset, brightness/contrast ผ่าน DDC/CI และการสร้าง display override สำหรับจอที่ต้องการโหมด HiDPI เพิ่มเติม

โปรเจกต์นี้เป็น native Swift/SwiftUI app สำหรับ macOS 14+ และตั้งใจให้ใช้งานกับเครื่อง Mac จริง เพราะหลายฟีเจอร์ต้องคุยกับ CoreGraphics, IOKit, DisplayServices และไฟล์ override ของระบบ

## ความสามารถหลัก

- แสดงข้อมูลจอภาพที่ต่ออยู่: display ID, UUID, vendor/product ID, serial number, สถานะ active/online/asleep, built-in/external, scale factor, rotation และโหมดที่รองรับ
- เปลี่ยน resolution และ HiDPI mode พร้อมหน้าต่างยืนยัน 15 วินาที ถ้าไม่ยืนยันจะ rollback กลับโหมดเดิม
- เปลี่ยน refresh rate ตามโหมดที่ macOS รายงาน รวมถึงจอ high-refresh/ProMotion ที่รองรับ
- หมุนจอ 0, 90, 180, 270 องศา เมื่อฮาร์ดแวร์และ macOS รองรับ
- disable/enable จอภายนอกแบบ best effort ด้วยการจัดการ display layout และ DDC/CI standby fallback
- ปรับ brightness/contrast ของจอภายนอกผ่าน DDC/CI และใช้ native brightness path สำหรับจอ built-in/Apple-branded เมื่อรองรับ
- บันทึก preset ต่อจอ และ auto-apply เมื่อจอนั้นถูกต่อกลับมา
- Clear Config และ Uninstall แบบอิง manifest เพื่อลบเฉพาะไฟล์ที่แอปสร้างหรือ restore backup ที่แอปเก็บไว้
- Export diagnostics สำหรับดูสถานะจอ โหมดที่รองรับ และ operation log ล่าสุด

## ข้อควรระวัง

Mac Monitor ใช้ทั้ง public API และ private/undocumented API ของ macOS เพื่อทำงานที่ Apple ไม่มี public API ให้ครบทุกกรณี ฟีเจอร์บางอย่างจึงอาจใช้ไม่ได้ใน macOS รุ่นใหม่ หรือใช้ไม่ได้กับจอ/adapter บางรุ่น

ฟีเจอร์ที่มีความเสี่ยงเป็นพิเศษ:

- `CGConfigureDisplayRotation` สำหรับ rotation เป็น private CoreGraphics symbol
- `DisplayServices.framework` สำหรับ brightness ของจอ Apple/built-in เป็น private framework
- IOKit I2C สำหรับ DDC/CI ขึ้นกับจอ สาย และ hub/adapter
- HiDPI override เขียนไฟล์ใต้ `/Library/Displays/Contents/Resources/Overrides/` และอาจต้องขอสิทธิ์ผู้ดูแลระบบ

แอปพยายาม fail gracefully เมื่อฟีเจอร์ไม่รองรับ แต่ควรใช้งานบนเครื่องที่สามารถกู้คืนจอได้ง่าย เช่น ถอด/เสียบสายจอกลับ หรือเข้า Safe Mode ได้หากตั้งค่าผิดพลาด

## Requirements

- macOS 14.0 ขึ้นไป
- Xcode หรือ Xcode Command Line Tools ที่รองรับ Swift 6
- เครื่อง Mac จริงพร้อมจอที่ต้องการทดสอบ

## การ Build และ Run

Build executable:

```bash
swift build
```

Run จาก Swift Package:

```bash
swift run MacMonitor
```

Build เป็น `.app` bundle:

```bash
./Scripts/build-app.sh release
```

ผลลัพธ์จะอยู่ที่:

```text
dist/Mac Monitor.app
```

สำหรับ development แบบเร็ว:

```bash
./Scripts/dev-app.sh
```

เมื่อเปิดแอปแล้วจะไม่มี Dock icon ตามปกติ ให้มองหาไอคอนจอคู่บน macOS menu bar

## การใช้งาน

1. เปิดแอป แล้วคลิกไอคอน Mac Monitor บน menu bar
2. เลือกจอที่ต้องการจัดการจากเมนู
3. ใช้เมนูย่อยสำหรับ resolution, refresh rate, rotation หรือ enable/disable display
4. เปิด `Settings...` เพื่อจัดการ preset, HiDPI override, brightness, diagnostics, clear config และ uninstall
5. ถ้าเปลี่ยน resolution แล้วมีหน้าต่างยืนยัน ให้กดยืนยันภายใน 15 วินาทีเพื่อเก็บค่าใหม่

## Recovery

ถ้าตั้งค่าจอแล้วภาพหายหรือจอกลับมาไม่ถูกต้อง:

1. ถอดสายจอภายนอกแล้วเสียบใหม่ เพื่อให้ macOS renegotiate display mode
2. ถ้าเป็นจอหลัก ให้ boot เข้า Safe Mode
3. ล้าง preferences:

```bash
defaults delete dev.sumetph.MacMonitor
```

4. ถ้าเคยเปิด HiDPI override ให้ใช้ Clear Config ในแอป หรือกู้คืนไฟล์ override จาก backup ที่ manifest เก็บไว้

## Project Structure

```text
MacMonitor/
├── Assets/
│   └── AppIcon.png
├── Docs/
│   └── init-prompt.md
├── Scripts/
│   ├── build-app.sh
│   └── dev-app.sh
├── Sources/MacMonitor/
│   ├── App/
│   │   └── MenuBarController.swift
│   ├── Models/
│   ├── Services/
│   ├── Views/
│   └── MacMonitor.swift
├── Tests/
├── Package.swift
└── README.md
```

## Security Notes ก่อนอัป GitHub

เช็กแล้วใน repository ปัจจุบันไม่พบ secret pattern เช่น API key, token, private key หรือ password ที่ hard-code ไว้ใน source code แต่โปรเจกต์มีจุดที่ควรระวังเมื่อเผยแพร่:

- แอปมี privileged AppleScript flow สำหรับเขียน/ลบไฟล์ display override ใต้ `/Library/Displays/...`
- diagnostics report อาจมีข้อมูล hardware identifier ของจอ เช่น UUID, vendor/product ID และ serial number
- manifest ใน `~/Library/Application Support/MacMonitor/manifest.json` ใช้ติดตามไฟล์ที่แอปสร้างและ backup ที่แอปกู้คืน
- `.vscode/launch.json` ยังเป็น untracked local file และไม่มี secret จากการตรวจรอบนี้
- `dist/`, `.build/`, `.env*`, private keys, provisioning profiles และ signing artifacts ไม่ควรถูก commit

ก่อน push ขึ้น GitHub แนะนำให้รัน:

```bash
git status --short
git diff --cached
git log --all --oneline --decorate
```

ถ้าพบว่าเคย commit secret ไปแล้ว ให้ rotate secret นั้นก่อน แล้วค่อยล้างประวัติ เพราะการลบไฟล์ออกจาก commit ล่าสุดอย่างเดียวไม่ทำให้ secret ปลอดภัย

## License

ยังไม่ได้ระบุ license ใน repository นี้ หากต้องการให้ผู้อื่นใช้งานหรือ fork ได้อย่างชัดเจน ควรเพิ่มไฟล์ `LICENSE` ก่อนเผยแพร่แบบ public
