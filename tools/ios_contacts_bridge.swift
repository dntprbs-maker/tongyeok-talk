import Contacts
import ContactsUI
import Flutter
import UIKit

final class ContactsBridge: NSObject, CNContactPickerDelegate {
  private let channel: FlutterMethodChannel
  private let store = CNContactStore()
  private let queue = DispatchQueue(label: "app.tongyeoktalk.contacts")
  private var pendingPick: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "tongyeok/contacts", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(hasAccess())
    case "enable":
      enable(result)
    case "pick":
      pick(result)
    case "pickPhone":
      pick(result, phoneOnly: true)
    case "lookup":
      lookup(call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func hasAccess() -> Bool {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    if status == .authorized {
      return true
    }
    if #available(iOS 18.0, *), status == .limited {
      return true
    }
    return false
  }

  private func enable(_ result: @escaping FlutterResult) {
    if hasAccess() {
      result(true)
      return
    }
    store.requestAccess(for: .contacts) { [weak self] _, _ in
      let allowed = self?.hasAccess() ?? false
      DispatchQueue.main.async { result(allowed) }
    }
  }

  private func lookup(_ arguments: Any?, result: @escaping FlutterResult) {
    guard hasAccess(),
      let numbers = arguments as? [String: String],
      !numbers.isEmpty,
      numbers.count <= 30
    else {
      result([String: String]())
      return
    }
    var targets = [String: [String]]()
    for (peer, phone) in numbers where Self.canonicalNumber(phone) == phone {
      targets[phone, default: []].append(peer)
    }
    guard !targets.isEmpty else {
      result([String: String]())
      return
    }
    let targetNumbers = Set(targets.keys)
    queue.async { [weak self] in
      let names = self?.matchedNames(numbers: targetNumbers) ?? [:]
      var output = [String: String]()
      for (number, peers) in targets {
        guard let name = names[number] else { continue }
        for peer in peers {
          output[peer] = name
        }
      }
      let matched = output
      DispatchQueue.main.async { [weak self] in
        result(self?.hasAccess() == true ? matched : [:])
      }
    }
  }

  private static func canonicalNumber(_ raw: String) -> String? {
    var number = raw.replacingOccurrences(of: #"[\s().-]"#, with: "", options: .regularExpression)
    if number.hasPrefix("00") {
      number = "+" + number.dropFirst(2)
    }
    if number.range(of: #"^\+?([0-9]+)$"#, options: .regularExpression) == nil {
      return nil
    }
    if number.hasPrefix("+976") {
      let national = String(number.dropFirst(4))
      return national.range(of: #"^[1-9][0-9]{7}$"#, options: .regularExpression) == nil ? nil : number
    }
    if number.range(of: #"^[1-9][0-9]{7}$"#, options: .regularExpression) != nil {
      return "+976" + number
    }
    if number.hasPrefix("+82") {
      number = String(number.dropFirst(3))
    }
    if number.hasPrefix("0") {
      number.removeFirst()
    }
    let korean = #"^(?:10[0-9]{8}|1[16789][0-9]{7,8}|2[0-9]{7,8}|[3-6][1-5][0-9]{7,8}|70[0-9]{8})$"#
    return number.range(of: korean, options: .regularExpression) == nil ? nil : "+82" + number
  }

  private func matchedNames(numbers: Set<String>) -> [String: String] {
    let formatKeys = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
    let request = CNContactFetchRequest(keysToFetch: [
      CNContactPhoneNumbersKey as NSString, formatKeys,
    ])
    var owners = [String: Set<String>]()
    var names = [String: String]()
    do {
      try store.enumerateContacts(with: request) { contact, _ in
        for field in contact.phoneNumbers {
          guard let phone = Self.canonicalNumber(field.value.stringValue),
            numbers.contains(phone)
          else { continue }
          owners[phone, default: []].insert(contact.identifier)
          names[contact.identifier] = Self.displayName(contact)
        }
      }
    } catch {
      return [:]
    }
    return owners.compactMapValues { ids in
      guard ids.count == 1, let id = ids.first else { return nil }
      return names[id]
    }
  }

  private static func displayName(_ contact: CNContact) -> String? {
    let name = CNContactFormatter.string(from: contact, style: .fullName)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let name = name, !name.isEmpty else { return nil }
    return name
  }

  private func pick(_ result: @escaping FlutterResult, phoneOnly: Bool = false) {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard pendingPick == nil,
      let scene = scenes.first(where: { $0.activationState == .foregroundActive }),
      var presenter = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
    else {
      result(nil)
      return
    }
    while let next = presenter.presentedViewController {
      presenter = next
    }
    let picker = CNContactPickerViewController()
    picker.delegate = self
    if phoneOnly {
      picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
      picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
      picker.predicateForSelectionOfContact = NSPredicate(value: false)
      picker.predicateForSelectionOfProperty = NSPredicate(format: "key == %@", CNContactPhoneNumbersKey)
    }
    pendingPick = result
    presenter.present(picker, animated: true)
  }

  func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
    finishPick(with: Self.displayName(contact))
  }

  func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
    finishPick(with: (contactProperty.value as? CNPhoneNumber)?.stringValue)
  }

  func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
    finishPick(with: nil)
  }

  private func finishPick(with name: String?) {
    let result = pendingPick
    pendingPick = nil
    result?(name)
  }
}
