import CoreFoundation
import Darwin
import Foundation

typealias IOReportSubscriptionRef = UnsafeRawPointer

enum IOReport {
    typealias CopyChannelsInGroup = @convention(c) (
        CFString?, CFString?, UInt64, UInt64, UInt64
    ) -> CFMutableDictionary?
    typealias CopyAllChannels = @convention(c) (UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    typealias MergeChannels = @convention(c) (CFMutableDictionary?, CFMutableDictionary?, CFTypeRef?) -> Void
    typealias CreateSubscription = @convention(c) (
        UnsafeRawPointer?, CFMutableDictionary?, UnsafeMutablePointer<CFMutableDictionary?>?, UInt64, CFTypeRef?
    ) -> Unmanaged<CFTypeRef>?
    typealias CreateSamples = @convention(c) (
        IOReportSubscriptionRef?, CFMutableDictionary?, CFTypeRef?
    ) -> Unmanaged<CFDictionary>?
    typealias CreateSamplesDelta = @convention(c) (
        CFDictionary?, CFDictionary?, CFTypeRef?
    ) -> Unmanaged<CFDictionary>?
    typealias ChannelString = @convention(c) (CFDictionary?) -> Unmanaged<CFString>?
    typealias StateCount = @convention(c) (CFDictionary?) -> Int32
    typealias StateResidency = @convention(c) (CFDictionary?, Int32) -> Int64
    typealias StateName = @convention(c) (CFDictionary?, Int32) -> Unmanaged<CFString>?
    typealias SimpleInteger = @convention(c) (CFDictionary?, Int32) -> Int64

    private static let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW | RTLD_LOCAL)

    static let copyChannelsInGroup: CopyChannelsInGroup? = symbol("IOReportCopyChannelsInGroup")
    static let copyAllChannels: CopyAllChannels? = symbol("IOReportCopyAllChannels")
    static let mergeChannels: MergeChannels? = symbol("IOReportMergeChannels")
    static let createSubscription: CreateSubscription? = symbol("IOReportCreateSubscription")
    static let createSamples: CreateSamples? = symbol("IOReportCreateSamples")
    static let createSamplesDelta: CreateSamplesDelta? = symbol("IOReportCreateSamplesDelta")
    static let channelGroup: ChannelString? = symbol("IOReportChannelGetGroup")
    static let channelSubGroup: ChannelString? = symbol("IOReportChannelGetSubGroup")
    static let channelName: ChannelString? = symbol("IOReportChannelGetChannelName")
    static let channelUnit: ChannelString? = symbol("IOReportChannelGetUnitLabel")
    static let stateCount: StateCount? = symbol("IOReportStateGetCount")
    static let stateResidency: StateResidency? = symbol("IOReportStateGetResidency")
    static let stateName: StateName? = symbol("IOReportStateGetNameForIndex")
    static let simpleInteger: SimpleInteger? = symbol("IOReportSimpleGetIntegerValue")

    static var isAvailable: Bool {
        handle != nil && copyAllChannels != nil && createSubscription != nil
            && createSamples != nil && createSamplesDelta != nil
    }

    static func string(_ getter: ChannelString?, _ item: CFDictionary) -> String {
        guard let unmanaged = getter?(item) else { return "" }
        return (unmanaged.takeUnretainedValue() as String).trimmingCharacters(in: .whitespaces)
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }
}
