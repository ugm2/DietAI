import Foundation
import AuthenticationServices
import SwiftData

// MARK: - Authentication State
enum AuthState: Equatable {
    case unknown
    case signedIn
    case signedOut
    case error(String)

    static func == (lhs: AuthState, rhs: AuthState) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown), (.signedIn, .signedIn), (.signedOut, .signedOut):
            return true
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - Authentication Service
@MainActor
@Observable
final class AuthenticationService {
    static let shared = AuthenticationService()

    private(set) var currentUser: UserProfile?
    private(set) var isAuthenticated = false
    private(set) var authState: AuthState = .unknown

    private let keychainService = KeychainService.shared

    private init() {}

    // MARK: - Sign In with Apple
    func signInWithApple(authorization: ASAuthorization, context: ModelContext) async throws {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.invalidCredential
        }

        let userIdentifier = appleIDCredential.user
        let email = appleIDCredential.email
        let fullName = appleIDCredential.fullName

        // Build display name
        var displayName: String?
        if let givenName = fullName?.givenName {
            displayName = givenName
            if let familyName = fullName?.familyName {
                displayName = "\(givenName) \(familyName)"
            }
        }

        // Store in Keychain
        try keychainService.storeUserIdentifier(userIdentifier)
        if let email = email {
            try keychainService.storeEmail(email)
        }
        if let displayName = displayName {
            try keychainService.storeDisplayName(displayName)
        }

        // Create or fetch user profile
        self.currentUser = try await fetchOrCreateUser(
            identifier: userIdentifier,
            email: email,
            displayName: displayName,
            context: context
        )
        self.isAuthenticated = true
        self.authState = .signedIn
    }

    // MARK: - Check Existing Credential
    func checkExistingCredential(context: ModelContext) async {
        guard let userIdentifier = keychainService.retrieveUserIdentifier() else {
            self.authState = .signedOut
            return
        }

        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: userIdentifier)
            switch state {
            case .authorized:
                self.currentUser = try await fetchUser(identifier: userIdentifier, context: context)
                self.isAuthenticated = true
                self.authState = .signedIn
            case .revoked, .notFound, .transferred:
                await signOut()
            @unknown default:
                await signOut()
            }
        } catch {
            self.authState = .error(error.localizedDescription)
        }
    }

    // MARK: - Sign Out
    func signOut() async {
        keychainService.clearCredentials()
        self.currentUser = nil
        self.isAuthenticated = false
        self.authState = .signedOut
    }

    // MARK: - Helper Methods
    private func fetchOrCreateUser(
        identifier: String,
        email: String?,
        displayName: String?,
        context: ModelContext
    ) async throws -> UserProfile {
        // Try to find existing user
        if let existingUser = try await fetchUser(identifier: identifier, context: context) {
            existingUser.lastLoginAt = Date()
            if let email = email, existingUser.email == nil {
                existingUser.email = email
            }
            if let displayName = displayName, existingUser.displayName == nil {
                existingUser.displayName = displayName
            }
            try context.save()
            return existingUser
        }

        // Create new user
        let newUser = UserProfile(
            appleUserIdentifier: identifier,
            email: email ?? keychainService.retrieveEmail(),
            displayName: displayName ?? keychainService.retrieveDisplayName()
        )
        context.insert(newUser)
        try context.save()
        return newUser
    }

    private func fetchUser(identifier: String, context: ModelContext) async throws -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.appleUserIdentifier == identifier }
        )
        return try context.fetch(descriptor).first
    }

    // MARK: - Guest Mode (no authentication)
    func continueAsGuest(context: ModelContext) async throws {
        // Create a local guest profile
        let guestUser = UserProfile(
            appleUserIdentifier: nil,
            email: nil,
            displayName: "Guest"
        )
        context.insert(guestUser)
        try context.save()

        self.currentUser = guestUser
        self.isAuthenticated = false // Guest is not fully authenticated
        self.authState = .signedOut // Remains signed out but has a profile
    }
}

// MARK: - Auth Errors
enum AuthError: LocalizedError {
    case invalidCredential
    case keychainError(String)
    case userNotFound

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid Apple ID credential"
        case .keychainError(let message):
            return "Keychain error: \(message)"
        case .userNotFound:
            return "User not found"
        }
    }
}

// MARK: - Keychain Service
final class KeychainService {
    static let shared = KeychainService()

    private let userIdentifierKey = "com.dietai.userIdentifier"
    private let emailKey = "com.dietai.email"
    private let displayNameKey = "com.dietai.displayName"

    private init() {}

    func storeUserIdentifier(_ identifier: String) throws {
        try store(key: userIdentifierKey, value: identifier)
    }

    func storeEmail(_ email: String) throws {
        try store(key: emailKey, value: email)
    }

    func storeDisplayName(_ name: String) throws {
        try store(key: displayNameKey, value: name)
    }

    func retrieveUserIdentifier() -> String? {
        retrieve(key: userIdentifierKey)
    }

    func retrieveEmail() -> String? {
        retrieve(key: emailKey)
    }

    func retrieveDisplayName() -> String? {
        retrieve(key: displayNameKey)
    }

    func clearCredentials() {
        delete(key: userIdentifierKey)
        delete(key: emailKey)
        delete(key: displayNameKey)
    }

    // MARK: - Private Keychain Operations
    private func store(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw AuthError.keychainError("Could not encode value")
        }

        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthError.keychainError("Failed to store: \(status)")
        }
    }

    private func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
