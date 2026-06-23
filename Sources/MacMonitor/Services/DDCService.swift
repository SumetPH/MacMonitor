import Foundation
import CoreGraphics
import IOKit

// Private DisplayServices functions loaded dynamically at runtime to prevent linker errors
private func DisplayServicesGetLinearBrightness(_ displayID: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32 {
    typealias GetLinearBrightnessType = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    if let sym = dlsym(handle, "DisplayServicesGetLinearBrightness") {
        let function = unsafeBitCast(sym, to: GetLinearBrightnessType.self)
        return function(displayID, brightness)
    }
    return -1
}

private func DisplayServicesSetLinearBrightness(_ displayID: CGDirectDisplayID, _ brightness: Float) -> Int32 {
    typealias SetLinearBrightnessType = @convention(c) (CGDirectDisplayID, Float) -> Int32
    let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    if let sym = dlsym(handle, "DisplayServicesSetLinearBrightness") {
        let function = unsafeBitCast(sym, to: SetLinearBrightnessType.self)
        return function(displayID, brightness)
    }
    return -1
}


// Custom definition of IOI2CRequest to compile cleanly without IOKit/i2c subheaders
public struct IOI2CRequest {
    public var commFlags: UInt32
    public var sendAddress: UInt32
    public var sendTransactionType: UInt32
    public var sendBytes: UnsafeMutableRawPointer?
    public var sendLength: UInt32
    public var replyAddress: UInt32
    public var replyTransactionType: UInt32
    public var replyBytes: UnsafeMutableRawPointer?
    public var replyLength: UInt32
    public var minDelay: UInt32
    public var result: Int32
    
    public init(
        commFlags: UInt32 = 0,
        sendAddress: UInt32 = 0,
        sendTransactionType: UInt32 = 0,
        sendBytes: UnsafeMutableRawPointer? = nil,
        sendLength: UInt32 = 0,
        replyAddress: UInt32 = 0,
        replyTransactionType: UInt32 = 0,
        replyBytes: UnsafeMutableRawPointer? = nil,
        replyLength: UInt32 = 0,
        minDelay: UInt32 = 0,
        result: Int32 = 0
    ) {
        self.commFlags = commFlags
        self.sendAddress = sendAddress
        self.sendTransactionType = sendTransactionType
        self.sendBytes = sendBytes
        self.sendLength = sendLength
        self.replyAddress = replyAddress
        self.replyTransactionType = replyTransactionType
        self.replyBytes = replyBytes
        self.replyLength = replyLength
        self.minDelay = minDelay
        self.result = result
    }
}

// I2C transaction types
private let kIOI2CSimpleTransactionType: UInt32 = 1
private let kIOI2CDDCciReplyTransactionType: UInt32 = 2
private let kIOI2CNoTransactionType: UInt32 = 0

// IOKit Framebuffer I2C APIs
@_silgen_name("IOFBGetI2CInterfaceCount")
private func IOFBGetI2CInterfaceCount(_ framebuffer: io_service_t, _ count: UnsafeMutablePointer<IOItemCount>) -> kern_return_t

@_silgen_name("IOFBCopyI2CInterfaceForBus")
private func IOFBCopyI2CInterfaceForBus(_ framebuffer: io_service_t, _ bus: IOOptionBits, _ interface: UnsafeMutablePointer<io_object_t>) -> kern_return_t

@_silgen_name("IOI2CSendRequest")
private func IOI2CSendRequest(_ interface: io_object_t, _ options: IOOptionBits, _ request: UnsafeMutablePointer<IOI2CRequest>) -> kern_return_t

@MainActor
public final class DDCService {
    public static let shared = DDCService()
    
    // Virtual control registers (VCP codes)
    private let VCP_BRIGHTNESS: UInt8 = 0x10
    private let VCP_CONTRAST: UInt8 = 0x12
    private let VCP_POWER: UInt8 = 0xD6
    private let VCP_INPUT: UInt8 = 0x60
    
    private init() {}
    
    private func getDisplayIOServicePort(displayID: CGDirectDisplayID) -> io_service_t {
        // Dynamically resolve CGDisplayIOServicePort at runtime to bypass compile-time unavailability
        typealias CGDisplayIOServicePortType = @convention(c) (CGDirectDisplayID) -> io_service_t
        let handle = dlopen(nil, RTLD_LAZY)
        if let sym = dlsym(handle, "CGDisplayIOServicePort") {
            let function = unsafeBitCast(sym, to: CGDisplayIOServicePortType.self)
            return function(displayID)
        }
        return io_service_t(MACH_PORT_NULL)
    }
    
    public func isAppleOrBuiltIn(displayID: CGDirectDisplayID) -> Bool {
        return CGDisplayIsBuiltin(displayID) != 0 || 
               CGDisplayVendorNumber(displayID) == 0x05AC // Apple Vendor ID
    }
    
    public func supportsDDC(displayID: CGDirectDisplayID) -> Bool {
        if isAppleOrBuiltIn(displayID: displayID) {
            return true // Supported via DisplayServices private API
        }
        
        let service = getDisplayIOServicePort(displayID: displayID)
        if service == io_service_t(MACH_PORT_NULL) {
            return false
        }
        
        var busCount: IOItemCount = 0
        let result = IOFBGetI2CInterfaceCount(service, &busCount)
        return result == kIOReturnSuccess && busCount > 0
    }
    
    public func readBrightness(displayID: CGDirectDisplayID) -> Double? {
        if isAppleOrBuiltIn(displayID: displayID) {
            var brightness: Float = 0.0
            let result = DisplayServicesGetLinearBrightness(displayID, &brightness)
            if result == 0 {
                return Double(brightness)
            }
            return nil
        }
        
        return readVCPFeature(displayID: displayID, vcpCode: VCP_BRIGHTNESS)
    }
    
    @discardableResult
    public func writeBrightness(displayID: CGDirectDisplayID, value: Double) -> Bool {
        let clampedValue = max(0.0, min(1.0, value))
        
        if isAppleOrBuiltIn(displayID: displayID) {
            let result = DisplayServicesSetLinearBrightness(displayID, Float(clampedValue))
            let success = result == 0
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "setBrightnessNative",
                success: success,
                details: "Set native brightness to \(Int(clampedValue * 100))%"
            )
            return success
        }
        
        let ddcValue = UInt8(clampedValue * 100)
        let success = writeVCPFeature(displayID: displayID, vcpCode: VCP_BRIGHTNESS, value: ddcValue)
        DiagnosticsService.shared.log(
            displayID: displayID,
            operation: "setBrightnessDDC",
            success: success,
            details: "Set DDC/CI brightness to \(ddcValue)%"
        )
        return success
    }
    
    public func readContrast(displayID: CGDirectDisplayID) -> Double? {
        if isAppleOrBuiltIn(displayID: displayID) {
            return nil
        }
        return readVCPFeature(displayID: displayID, vcpCode: VCP_CONTRAST)
    }
    
    @discardableResult
    public func writeContrast(displayID: CGDirectDisplayID, value: Double) -> Bool {
        let clampedValue = max(0.0, min(1.0, value))
        let ddcValue = UInt8(clampedValue * 100)
        let success = writeVCPFeature(displayID: displayID, vcpCode: VCP_CONTRAST, value: ddcValue)
        DiagnosticsService.shared.log(
            displayID: displayID,
            operation: "setContrastDDC",
            success: success,
            details: "Set DDC/CI contrast to \(ddcValue)%"
        )
        return success
    }
    
    @discardableResult
    public func setPower(displayID: CGDirectDisplayID, on: Bool) -> Bool {
        if isAppleOrBuiltIn(displayID: displayID) {
            return false
        }
        let value: UInt8 = on ? 1 : 4
        let success = writeVCPFeature(displayID: displayID, vcpCode: VCP_POWER, value: value)
        DiagnosticsService.shared.log(
            displayID: displayID,
            operation: "setPowerDDC",
            success: success,
            details: "Set display DDC/CI power state to \(on ? "ON" : "STANDBY")"
        )
        return success
    }
    
    // MARK: - Internal I2C DDC/CI Protocol Implementation
    
    private func writeVCPFeature(displayID: CGDirectDisplayID, vcpCode: UInt8, value: UInt8) -> Bool {
        let service = getDisplayIOServicePort(displayID: displayID)
        guard service != io_service_t(MACH_PORT_NULL) else { return false }
        
        var interface: io_object_t = io_object_t(MACH_PORT_NULL)
        let res = IOFBCopyI2CInterfaceForBus(service, 0, &interface)
        guard res == kIOReturnSuccess, interface != io_object_t(MACH_PORT_NULL) else { return false }
        
        defer { IOObjectRelease(interface) }
        
        var payload = [UInt8](repeating: 0, count: 7)
        payload[0] = 0x51
        payload[1] = 0x84
        payload[2] = 0x03
        payload[3] = vcpCode
        payload[4] = 0x00
        payload[5] = value
        
        var checksum: UInt8 = 0x6E
        for byte in payload[0...5] {
            checksum ^= byte
        }
        payload[6] = checksum
        
        var request = IOI2CRequest()
        request.commFlags = 0
        request.sendAddress = 0x6E
        request.sendTransactionType = kIOI2CSimpleTransactionType
        
        let sendLen = UInt32(payload.count)
        return payload.withUnsafeMutableBufferPointer { sendPtr -> Bool in
            request.sendBytes = UnsafeMutableRawPointer(sendPtr.baseAddress)
            request.sendLength = sendLen
            request.replyAddress = 0x6F
            request.replyTransactionType = kIOI2CNoTransactionType
            request.replyBytes = nil
            request.replyLength = 0
            request.minDelay = 40
            
            let status = IOI2CSendRequest(interface, 0, &request)
            return status == kIOReturnSuccess && request.result == kIOReturnSuccess
        }
    }
    
    private func readVCPFeature(displayID: CGDirectDisplayID, vcpCode: UInt8) -> Double? {
        let service = getDisplayIOServicePort(displayID: displayID)
        guard service != io_service_t(MACH_PORT_NULL) else { return nil }
        
        var interface: io_object_t = io_object_t(MACH_PORT_NULL)
        let res = IOFBCopyI2CInterfaceForBus(service, 0, &interface)
        guard res == kIOReturnSuccess, interface != io_object_t(MACH_PORT_NULL) else { return nil }
        
        defer { IOObjectRelease(interface) }
        
        var writePayload = [UInt8](repeating: 0, count: 5)
        writePayload[0] = 0x51
        writePayload[1] = 0x82
        writePayload[2] = 0x01
        writePayload[3] = vcpCode
        
        var checksum: UInt8 = 0x6E
        for byte in writePayload[0...3] {
            checksum ^= byte
        }
        writePayload[4] = checksum
        
        var request = IOI2CRequest()
        request.commFlags = 0
        request.sendAddress = 0x6E
        request.sendTransactionType = kIOI2CSimpleTransactionType
        
        let sendLen = UInt32(writePayload.count)
        let writeSuccess = writePayload.withUnsafeMutableBufferPointer { sendPtr -> Bool in
            request.sendBytes = UnsafeMutableRawPointer(sendPtr.baseAddress)
            request.sendLength = sendLen
            request.replyAddress = 0
            request.replyTransactionType = kIOI2CNoTransactionType
            request.replyBytes = nil
            request.replyLength = 0
            request.minDelay = 40
            
            let status = IOI2CSendRequest(interface, 0, &request)
            return status == kIOReturnSuccess && request.result == kIOReturnSuccess
        }
        
        guard writeSuccess else { return nil }
        
        Thread.sleep(forTimeInterval: 0.04)
        
        var readPayload = [UInt8](repeating: 0, count: 12)
        var readRequest = IOI2CRequest()
        readRequest.commFlags = 0
        readRequest.sendAddress = 0
        readRequest.sendTransactionType = kIOI2CNoTransactionType
        readRequest.sendBytes = nil
        readRequest.sendLength = 0
        
        readRequest.replyAddress = 0x6F
        readRequest.replyTransactionType = kIOI2CDDCciReplyTransactionType
        
        let replyLen = UInt32(readPayload.count)
        let readSuccess = readPayload.withUnsafeMutableBufferPointer { replyPtr -> Bool in
            readRequest.replyBytes = UnsafeMutableRawPointer(replyPtr.baseAddress)
            readRequest.replyLength = replyLen
            readRequest.minDelay = 40
            
            let status = IOI2CSendRequest(interface, 0, &readRequest)
            return status == kIOReturnSuccess && readRequest.result == kIOReturnSuccess
        }
        
        guard readSuccess else { return nil }
        
        guard readPayload[2] == 0x02 && readPayload[4] == vcpCode else { return nil }
        
        let currentValue = (UInt16(readPayload[7]) << 8) | UInt16(readPayload[8])
        let maxValue = (UInt16(readPayload[5]) << 8) | UInt16(readPayload[6])
        
        guard maxValue > 0 else { return nil }
        return Double(currentValue) / Double(maxValue)
    }
}
