//
//  WWNModuleStore.swift
//  Wawona — StoreKit 2 backend for the wwn-apt module manager.
//
//  Products are App Store Connect in-app purchases whose identifiers come
//  from the wwn-apt catalog (`platforms.<os>.storekit.product_id`). This is
//  the only acquisition path for optional modules: no code is ever
//  downloaded from third-party servers (payloads ship as ODR / bundled
//  assets reviewed by Apple).
//

import Foundation
#if canImport(StoreKit)
import StoreKit

@objc(WWNModuleStore)
public final class WWNModuleStore: NSObject {

    private static let errorDomain = "io.wawona.modulestore"

    private static func error(_ code: Int, _ message: String) -> NSError {
        NSError(domain: errorDomain, code: code,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// Purchase (or verify existing entitlement for) a module product.
    /// Called from WWNModuleManager via NSClassFromString.
    @objc public static func purchaseProductId(
        _ productId: String,
        completion: @escaping (NSError?) -> Void
    ) {
        guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) else {
            completion(error(1, "StoreKit 2 requires a newer OS version"))
            return
        }
        Task {
            do {
                // Already entitled (restore / family sharing / re-install)?
                if await isEntitled(productId: productId) {
                    completion(nil)
                    return
                }
                let products = try await Product.products(for: [productId])
                guard let product = products.first else {
                    completion(error(2, "Product '\(productId)' not found in App Store Connect"))
                    return
                }
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified(let transaction):
                        await transaction.finish()
                        completion(nil)
                    case .unverified(_, let verificationError):
                        completion(error(3, "Purchase could not be verified: \(verificationError)"))
                    }
                case .userCancelled:
                    completion(error(4, "Purchase cancelled"))
                case .pending:
                    completion(error(5, "Purchase is pending approval"))
                @unknown default:
                    completion(error(6, "Unknown purchase result"))
                }
            } catch {
                completion(Self.error(7, error.localizedDescription))
            }
        }
    }

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    private static func isEntitled(productId: String) async -> Bool {
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == productId {
                return true
            }
        }
        return false
    }
}

#endif // canImport(StoreKit)
