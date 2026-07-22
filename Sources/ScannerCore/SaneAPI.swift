import Foundation
import CSane

// The fujitsu backend module (libsane-fujitsu.so, an MH_BUNDLE) exports the
// complete standard sane_* API. It can only be loaded with dlopen, so the
// entry points are resolved here once and exposed as typed C function pointers.
final class SaneAPI {
    typealias FnInit = @convention(c) (UnsafeMutablePointer<SANE_Int>?, SANE_Auth_Callback?) -> SANE_Status
    typealias FnExit = @convention(c) () -> Void
    typealias FnGetDevices = @convention(c) (UnsafeMutablePointer<UnsafeMutablePointer<UnsafePointer<SANE_Device>?>?>?, SANE_Bool) -> SANE_Status
    typealias FnOpen = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> SANE_Status
    typealias FnClose = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias FnGetOptDesc = @convention(c) (UnsafeMutableRawPointer?, SANE_Int) -> UnsafePointer<SANE_Option_Descriptor>?
    typealias FnControlOption = @convention(c) (UnsafeMutableRawPointer?, SANE_Int, SANE_Action, UnsafeMutableRawPointer?, UnsafeMutablePointer<SANE_Int>?) -> SANE_Status
    typealias FnGetParameters = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<SANE_Parameters>?) -> SANE_Status
    typealias FnStart = @convention(c) (UnsafeMutableRawPointer?) -> SANE_Status
    typealias FnRead = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, SANE_Int, UnsafeMutablePointer<SANE_Int>?) -> SANE_Status
    typealias FnCancel = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias FnStrStatus = @convention(c) (SANE_Status) -> UnsafePointer<CChar>?

    let saneInit: FnInit
    let saneExit: FnExit
    let getDevices: FnGetDevices
    let open: FnOpen
    let close: FnClose
    let getOptionDescriptor: FnGetOptDesc
    let controlOption: FnControlOption
    let getParameters: FnGetParameters
    let start: FnStart
    let read: FnRead
    let cancel: FnCancel
    let strStatus: FnStrStatus

    private let module: UnsafeMutableRawPointer

    init(modulePath: String) throws {
        guard let handle = dlopen(modulePath, RTLD_NOW | RTLD_LOCAL) else {
            let message = dlerror().map { String(cString: $0) } ?? "dlopen failed"
            throw ScanError.saneFailure(operation: "dlopen(\(modulePath))", status: message, code: -1)
        }
        module = handle

        func symbol<T>(_ name: String, _ type: T.Type) throws -> T {
            guard let pointer = dlsym(handle, name) else {
                throw ScanError.saneFailure(operation: "dlsym(\(name))", status: "symbol not found", code: -1)
            }
            return unsafeBitCast(pointer, to: T.self)
        }

        saneInit = try symbol("sane_init", FnInit.self)
        saneExit = try symbol("sane_exit", FnExit.self)
        getDevices = try symbol("sane_get_devices", FnGetDevices.self)
        open = try symbol("sane_open", FnOpen.self)
        close = try symbol("sane_close", FnClose.self)
        getOptionDescriptor = try symbol("sane_get_option_descriptor", FnGetOptDesc.self)
        controlOption = try symbol("sane_control_option", FnControlOption.self)
        getParameters = try symbol("sane_get_parameters", FnGetParameters.self)
        start = try symbol("sane_start", FnStart.self)
        read = try symbol("sane_read", FnRead.self)
        cancel = try symbol("sane_cancel", FnCancel.self)
        strStatus = try symbol("sane_strstatus", FnStrStatus.self)
    }

    func statusText(_ status: SANE_Status) -> String {
        strStatus(status).map { String(cString: $0) } ?? "unknown status"
    }
}
