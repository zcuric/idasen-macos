import CoreBluetooth
import Foundation

// MARK: - Shared types

public enum BluetoothAvailability: Equatable, Sendable {
    case unknown
    case ready
    case poweredOff
    case unauthorized
    case unsupported

    public var title: String {
        switch self {
        case .unknown: return "Bluetooth"
        case .ready: return "Bluetooth ready"
        case .poweredOff: return "Bluetooth off"
        case .unauthorized: return "Bluetooth not allowed"
        case .unsupported: return "Bluetooth unsupported"
        }
    }

    public var symbolName: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .poweredOff: return "bolt.slash.fill"
        case .unauthorized: return "lock.fill"
        case .unknown, .unsupported: return "questionmark.circle.fill"
        }
    }
}

public struct DiscoveredDesk: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var rssi: Int
    public var isIdasen: Bool
    public var lastSeen: Date

    public init(id: UUID, name: String, rssi: Int, isIdasen: Bool, lastSeen: Date = Date()) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.isIdasen = isIdasen
        self.lastSeen = lastSeen
    }

    public var signalBars: Int {
        switch rssi {
        case let value where value >= -55: return 4
        case let value where value >= -67: return 3
        case let value where value >= -80: return 2
        default: return 1
        }
    }
}

public enum ConnectionState: Equatable, Sendable {
    case idle
    case scanning
    case connecting(name: String)
    case connected(name: String)
    case reconnecting(attempt: Int)
    case failed(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var isBusy: Bool {
        switch self {
        case .scanning, .connecting, .reconnecting: return true
        default: return false
        }
    }

    public var deskName: String? {
        switch self {
        case .connected(let name), .connecting(let name): return name
        default: return nil
        }
    }
}

// MARK: - Link protocol

@MainActor
public protocol DeskLinkDelegate: AnyObject {
    func linkDidChangeState(_ link: DeskLink, state: ConnectionState)
    func linkDidChangeBluetooth(_ link: DeskLink, availability: BluetoothAvailability)
    func link(_ link: DeskLink, didDiscover desk: DiscoveredDesk)
    func link(_ link: DeskLink, didUpdate sample: DeskHeightSample)
    func linkDidBecomeReady(_ link: DeskLink)
    func link(_ link: DeskLink, didFail error: DeskError)
    func link(_ link: DeskLink, didReceiveStatus bytes: [UInt8])
}

/// Transport abstraction so the app can run against real hardware or the
/// built-in simulator.
@MainActor
public protocol DeskLink: AnyObject {
    var delegate: DeskLinkDelegate? { get set }
    var savedDeskID: UUID? { get }
    var connectedDeskName: String? { get }
    var hasReferenceInput: Bool { get }

    func startScan()
    func stopScan()
    func connect(to id: UUID, name: String)
    /// Reconnects to the previously saved desk if the system still knows it.
    @discardableResult
    func connectSaved() -> Bool
    func disconnect()
    func forgetSaved()

    func write(command: IdasenCommand)
    func writeReference(bytes: [UInt8])
    func requestHeight()
}

extension DeskLink {
    public var hasReferenceInput: Bool { true }
}

// MARK: - CoreBluetooth implementation

@MainActor
public final class BluetoothDeskLink: NSObject, DeskLink {
    public weak var delegate: DeskLinkDelegate?

    public private(set) var state: ConnectionState = .idle {
        didSet {
            guard state != oldValue else { return }
            delegate?.linkDidChangeState(self, state: state)
        }
    }

    public private(set) var availability: BluetoothAvailability = .unknown {
        didSet {
            guard availability != oldValue else { return }
            delegate?.linkDidChangeBluetooth(self, availability: availability)
        }
    }

    public private(set) var savedDeskID: UUID? {
        didSet {
            if let id = savedDeskID {
                UserDefaults.standard.set(id.uuidString, forKey: Self.savedIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.savedIDKey)
            }
        }
    }

    public var connectedDeskName: String? {
        if case .connected(let name) = state { return name }
        return currentName
    }

    public var hasReferenceInput: Bool { referenceCharacteristic != nil }

    private var currentName: String? {
        didSet {
            if let currentName {
                UserDefaults.standard.set(currentName, forKey: Self.savedNameKey)
            }
        }
    }

    private static let savedIDKey = "savedDeskIdentifier"
    private static let savedNameKey = "savedDeskName"

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var connectedPeripheral: CBPeripheral? {
        didSet { connectedPeripheral?.delegate = self }
    }

    private var commandCharacteristic: CBCharacteristic?
    private var heightCharacteristic: CBCharacteristic?
    private var referenceCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var dpgCharacteristic: CBCharacteristic?
    private var servicesRemaining: Int = 0
    private var hasReportedReady = false
    private var writes = DeskWriteBuffer()
    private var awaitingWriteResponse = false
    private var heightReadPending = false
    private var lastHeightReceivedAt: TimeInterval = -.infinity

    private var connectTimeoutTimer: Timer?
    private var pendingConnectName: String?
    private var pendingScan = false
    private var wantsConnection = false

    public override init() {
        super.init()
        savedDeskID = UserDefaults.standard.string(forKey: Self.savedIDKey).flatMap(UUID.init(uuidString:))
        currentName = UserDefaults.standard.string(forKey: Self.savedNameKey)
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    // MARK: Scanning

    public func startScan() {
        guard !state.isConnected else { return }
        switch central.state {
        case .poweredOn:
            beginScan()
        case .unknown, .resetting:
            // CoreBluetooth has not reported its state yet; scan as soon as it does.
            pendingScan = true
            state = .scanning
        case .poweredOff:
            delegate?.link(self, didFail: .bluetoothPoweredOff)
        case .unauthorized:
            delegate?.link(self, didFail: .bluetoothUnauthorized)
        case .unsupported:
            delegate?.link(self, didFail: .bluetoothUnavailable("Unsupported"))
        @unknown default:
            delegate?.link(self, didFail: .bluetoothUnavailable(availability.title))
        }
    }

    private func beginScan() {
        pendingScan = false
        state = .scanning
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    public func stopScan() {
        pendingScan = false
        central.stopScan()
        if case .scanning = state {
            state = .idle
        }
    }

    // MARK: Connecting

    public func connect(to id: UUID, name: String) {
        stopScan()
        savedDeskID = id
        currentName = name
        wantsConnection = true

        if let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(peripheral: known, name: name)
        } else if let cached = peripherals[id] {
            connect(peripheral: cached, name: name)
        } else {
            // Peripheral not known to the system yet — scan until it appears.
            state = .connecting(name: name)
            pendingConnectName = name
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }
    }

    @discardableResult
    public func connectSaved() -> Bool {
        guard let id = savedDeskID else { return false }
        let name = currentName ?? "Desk"
        if let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            wantsConnection = true
            connect(peripheral: known, name: name)
            return true
        }
        // Unknown to the system (e.g. never paired here) — scan for it.
        wantsConnection = true
        state = .connecting(name: name)
        pendingConnectName = name
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        return true
    }

    public func disconnect() {
        wantsConnection = false
        pendingConnectName = nil
        stopScan()
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        } else {
            resetCharacteristics()
            state = .idle
        }
    }

    public func forgetSaved() {
        disconnect()
        savedDeskID = nil
        currentName = nil
        peripherals.removeAll()
        state = .idle
    }

    private func connect(peripheral: CBPeripheral, name: String) {
        stopScan()
        self.peripheral = peripheral
        connectedPeripheral = peripheral
        pendingConnectName = nil
        state = .connecting(name: name)
        startConnectTimeout()
        central.connect(peripheral, options: nil)
    }

    private func startConnectTimeout() {
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.state.isConnected else { return }
                if let peripheral = self.peripheral {
                    self.central.cancelPeripheralConnection(peripheral)
                }
                self.delegate?.link(self, didFail: .deskNotFound)
                self.state = .idle
            }
        }
    }

    private func resetCharacteristics() {
        hasReportedReady = false
        writes.reset()
        awaitingWriteResponse = false
        heightReadPending = false
        lastHeightReceivedAt = -.infinity
        commandCharacteristic = nil
        heightCharacteristic = nil
        referenceCharacteristic = nil
        statusCharacteristic = nil
        dpgCharacteristic = nil
        servicesRemaining = 0
        peripheral = nil
        connectedPeripheral = nil
    }

    // MARK: Writes

    public func write(command: IdasenCommand) {
        guard commandCharacteristic != nil, peripheral != nil else {
            delegate?.link(self, didFail: .notConnected)
            return
        }
        enqueue(.command(command))
    }

    public func writeReference(bytes: [UInt8]) {
        guard referenceCharacteristic != nil else {
            // Some controllers expose only the handset command channel.
            if bytes != referenceInputStopBytes { delegate?.link(self, didFail: .characteristicMissing) }
            return
        }
        enqueue(.reference(bytes))
    }

    private func enqueue(_ operation: DeskWriteBuffer.Operation) {
        writes.enqueue(operation, at: ProcessInfo.processInfo.systemUptime)
        flushWrites()
    }

    private func flushWrites() {
        guard let peripheral, !awaitingWriteResponse else { return }
        while let operation = writes.next(at: ProcessInfo.processInfo.systemUptime) {
            let characteristic: CBCharacteristic?
            let bytes: [UInt8]
            switch operation {
            case .command(let command):
                characteristic = commandCharacteristic
                bytes = command.bytes
            case .reference(let value):
                characteristic = referenceCharacteristic
                bytes = value
            case .dpg(let value):
                characteristic = dpgCharacteristic
                bytes = value
            }
            guard let characteristic else { writes.removeFirst(); continue }
            let type = writeType(for: characteristic)
            if type == .withoutResponse, !peripheral.canSendWriteWithoutResponse { return }
            writes.removeFirst()
            if type == .withResponse { awaitingWriteResponse = true }
            peripheral.writeValue(Data(bytes), for: characteristic, type: type)
            if awaitingWriteResponse { return }
        }
    }

    public func requestHeight() {
        guard let characteristic = heightCharacteristic, let peripheral,
              !heightReadPending, characteristic.properties.contains(.read) else { return }
        // Notifications already supply a fresher position than a redundant read.
        guard ProcessInfo.processInfo.systemUptime - lastHeightReceivedAt >= 0.8 else { return }
        heightReadPending = true
        peripheral.readValue(for: characteristic)
    }

    /// Sends the LINAK DPG handshake used by panels with a hand controller.
    public func wakeDPG() {
        guard dpgCharacteristic != nil else { return }
        enqueue(.dpg([0x7F, 0x86, 0x00]))
        enqueue(.dpg([0x7F, 0x86, 0x80] + Array(0x01...0x11)))
    }

    public func subscribeToStatus() {
        guard let statusCharacteristic, let peripheral else { return }
        if statusCharacteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: statusCharacteristic)
        }
    }

    private func writeType(for characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        if characteristic.properties.contains(.writeWithoutResponse) {
            return .withoutResponse
        }
        return .withResponse
    }

    // MARK: Discovery

    private func discoverCharacteristics() {
        guard let peripheral else { return }
        if let services = peripheral.services, !services.isEmpty {
            servicesRemaining = services.count
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        } else {
            peripheral.discoverServices(nil)
        }
    }

    private func index(_ characteristic: CBCharacteristic) {
        switch characteristic.uuid {
        case IdasenUUID.command: commandCharacteristic = characteristic
        case IdasenUUID.height: heightCharacteristic = characteristic
        case IdasenUUID.referenceInput: referenceCharacteristic = characteristic
        case IdasenUUID.commandStatus: statusCharacteristic = characteristic
        case IdasenUUID.dpgInput: dpgCharacteristic = characteristic
        default: break
        }
    }

    private var isReady: Bool {
        commandCharacteristic != nil && heightCharacteristic != nil
    }

    private func finishDiscoveryIfNeeded() {
        guard isReady, !hasReportedReady else { return }
        guard case .connected = state else { return }
        if let heightCharacteristic, let peripheral {
            if heightCharacteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: heightCharacteristic)
            } else {
                peripheral.readValue(for: heightCharacteristic)
            }
        }
        if let statusCharacteristic, let peripheral, statusCharacteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: statusCharacteristic)
        }
        guard !hasReportedReady else { return }
        hasReportedReady = true
        delegate?.linkDidBecomeReady(self)
    }

    private static let namePattern = try! NSRegularExpression(pattern: "^\\s*(desk|idasen|idåsen)", options: [.caseInsensitive])

    private func looksLikeIdasen(name: String?, serviceUUIDs: [CBUUID]?) -> Bool {
        if serviceUUIDs?.contains(IdasenUUID.advertisedService) == true { return true }
        guard let name, !name.isEmpty else { return false }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return Self.namePattern.firstMatch(in: name, options: [], range: range) != nil
    }

    private func index(discovered peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        let isIdasen = looksLikeIdasen(name: name, serviceUUIDs: serviceUUIDs)
        let desk = DiscoveredDesk(
            id: peripheral.identifier,
            name: name ?? "Unnamed device",
            rssi: RSSI.intValue,
            isIdasen: isIdasen
        )
        peripherals[peripheral.identifier] = peripheral
        delegate?.link(self, didDiscover: desk)
    }

    private var peripherals: [UUID: CBPeripheral] = [:]
}

// MARK: - CBCentralManagerDelegate

extension BluetoothDeskLink: @MainActor CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            availability = .ready
            if pendingScan {
                beginScan()
            }
            if wantsConnection, savedDeskID != nil {
                connectSaved()
            }
        case .poweredOff:
            availability = .poweredOff
            resetCharacteristics()
            state = .idle
        case .unauthorized:
            availability = .unauthorized
        case .unsupported:
            availability = .unsupported
        case .resetting:
            availability = .unknown
        case .unknown:
            availability = .unknown
        @unknown default:
            availability = .unknown
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        index(discovered: peripheral, advertisementData: advertisementData, rssi: RSSI)

        guard let pendingName = pendingConnectName else { return }
        if peripheral.identifier == savedDeskID {
            connect(peripheral: peripheral, name: pendingName)
            return
        }
        // Fall back to name matching when the identifier changed (rare).
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        if looksLikeIdasen(name: name, serviceUUIDs: advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) {
            connect(peripheral: peripheral, name: name.isEmpty ? pendingName : name)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectTimeoutTimer?.invalidate()
        connectedPeripheral = peripheral
        self.peripheral = peripheral
        state = .connected(name: peripheral.name ?? currentName ?? "Desk")
        discoverCharacteristics()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        connectTimeoutTimer?.invalidate()
        resetCharacteristics()
        delegate?.link(self, didFail: .connectionFailed(error?.localizedDescription ?? "Unknown error."))
        state = .failed("Could not connect")
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        let wasExpected = wantsConnection
        resetCharacteristics()
        if wasExpected {
            // The controller dropped out; the owner decides how to retry.
            delegate?.link(self, didFail: .connectionLost)
        }
        state = .idle
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothDeskLink: @MainActor CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            delegate?.link(self, didFail: .characteristicMissing)
            return
        }
        servicesRemaining = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                index(characteristic)
            }
        }
        servicesRemaining = max(0, servicesRemaining - 1)
        if servicesRemaining == 0 {
            finishDiscoveryIfNeeded()
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral === self.peripheral else { return }
        if characteristic.uuid == IdasenUUID.height { heightReadPending = false }
        guard error == nil, let data = characteristic.value else { return }
        switch characteristic.uuid {
        case IdasenUUID.height:
            if let sample = DeskHeightSample(data: data) {
                lastHeightReceivedAt = ProcessInfo.processInfo.systemUptime
                delegate?.link(self, didUpdate: sample)
            }
        case IdasenUUID.commandStatus:
            delegate?.link(self, didReceiveStatus: [UInt8](data))
        default:
            break
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil else { return }
        if characteristic.uuid == IdasenUUID.height, characteristic.isNotifying {
            requestHeight()
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral === self.peripheral else { return }
        awaitingWriteResponse = false
        if let error {
            writes.reset()
            delegate?.link(self, didFail: .connectionFailed(error.localizedDescription))
        } else {
            flushWrites()
        }
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        flushWrites()
    }
}
