//
//  PACEHandler.swift
//  NFCPassportReader
//
//  Created by Andy Qua on 03/03/2021.
//

import Foundation
import OSLog
import OpenSSL
import CryptoTokenKit

#if !os(macOS)
import CoreNFC
import CryptoKit

@available(iOS 15, *)
private enum PACEHandlerError {
    case DHKeyAgreementError(String)
    case ECDHKeyAgreementError(String)
    
    var value: String {
        switch self {
            case .DHKeyAgreementError(let errMsg): return errMsg
            case .ECDHKeyAgreementError(let errMsg): return errMsg

        }
    }
}

@available(iOS 15, *)
extension PACEHandlerError: LocalizedError {
    public var errorDescription: String? {
        return NSLocalizedString(value, comment: "PACEHandlerError")
    }
}

@available(iOS 15, *)
public class PACEHandler {
    
    
    private static let MRZ_PACE_KEY_REFERENCE : UInt8 = 0x01
    private static let CAN_PACE_KEY_REFERENCE : UInt8 = 0x02
    private static let PIN_PACE_KEY_REFERENCE : UInt8 = 0x03 // Not currently supported
    private static let CUK_PACE_KEY_REFERENCE : UInt8 = 0x04 // Not currently supported

    // ICAO 9303-11 Section 4.4.3.3.2 PRF constants for Integrated Mapping
    private static let C0_128: [UInt8] = [
        0xA6, 0x68, 0x89, 0x2A, 0x7C, 0x41, 0xE3, 0xCA,
        0x73, 0x9F, 0x40, 0xB0, 0x57, 0xD8, 0x59, 0x04]
    private static let C1_128: [UInt8] = [
        0xA4, 0xE1, 0x36, 0xAC, 0x72, 0x5F, 0x73, 0x8B,
        0x01, 0xC1, 0xF6, 0x02, 0x17, 0xC1, 0x88, 0xAD]
    private static let C0_256: [UInt8] = [
        0xD4, 0x63, 0xD6, 0x52, 0x34, 0x12, 0x4E, 0xF7,
        0x89, 0x70, 0x54, 0x98, 0x6D, 0xCA, 0x0A, 0x17,
        0x4E, 0x28, 0xDF, 0x75, 0x8C, 0xBA, 0xA0, 0x3F,
        0x24, 0x06, 0x16, 0x41, 0x4D, 0x5A, 0x16, 0x76]
    private static let C1_256: [UInt8] = [
        0x54, 0xBD, 0x72, 0x55, 0xF0, 0xAA, 0xF8, 0x31,
        0xBE, 0xC3, 0x42, 0x3F, 0xCF, 0x39, 0xD6, 0x9B,
        0x6C, 0xBF, 0x06, 0x66, 0x77, 0xD0, 0xFA, 0xAE,
        0x5A, 0xAD, 0xD9, 0x9D, 0xF8, 0xE5, 0x35, 0x17]

    var tagReader : TagReader
    var paceInfo : PACEInfo
    
    var isPACESupported : Bool = false
    var paceError : String = ""
    
    // Params used
    private var paceKey : [UInt8] = []
    private var paceKeyType : UInt8 = 0
    private var paceOID : String = ""
    private var parameterSpec : Int32 = -1
    private var mappingType : PACEMappingType!
    private var agreementAlg : String = ""
    private var cipherAlg : String = ""
    private var digestAlg : String = ""
    private var keyLength : Int = -1
    
    public init(cardAccess : CardAccess, tagReader: TagReader) throws {
        self.tagReader = tagReader
        
        guard let pi = cardAccess.paceInfo else {
            throw NFCPassportReaderError.NotYetSupported( "PACE not supported" )
        }

        self.paceInfo = pi
        isPACESupported = true
    }
    
    public func doPACE( mrzKey : String, can : String? = nil ) async throws {
        guard isPACESupported else {
            throw NFCPassportReaderError.NotYetSupported( "PACE not supported" )
        }

        Logger.pace.info( "Performing PACE with \(self.paceInfo.getProtocolOIDString())" )

        paceOID = paceInfo.getObjectIdentifier()
        parameterSpec = try paceInfo.getParameterSpec()

        mappingType = try paceInfo.getMappingType()  // Either GM, CAM, or IM.
        agreementAlg = try paceInfo.getKeyAgreementAlgorithm()  // Either DH or ECDH.
        cipherAlg  = try paceInfo.getCipherAlgorithm()  // Either DESede or AES.
        digestAlg = try paceInfo.getDigestAlgorithm()  // Either SHA-1 or SHA-256.
        keyLength = try paceInfo.getKeyLength()  // Get key length  the enc cipher. Either 128, 192, or 256.

        if let can = can, !can.isEmpty {
            Logger.pace.info( "Using CAN for PACE authentication" )
            paceKeyType = PACEHandler.CAN_PACE_KEY_REFERENCE
            paceKey = try createPaceKey( fromCAN: can )
        } else {
            paceKeyType = PACEHandler.MRZ_PACE_KEY_REFERENCE
            paceKey = try createPaceKey( from: mrzKey )
        }
        
        // Temporary logging
        Logger.pace.debug("doPace - inpit parameters" )
        Logger.pace.debug("paceOID - \(self.paceOID)" )
        Logger.pace.debug("parameterSpec - \(self.parameterSpec)" )
        Logger.pace.debug("mappingType - \(self.mappingType!.description())" )
        Logger.pace.debug("agreementAlg - \(self.agreementAlg)" )
        Logger.pace.debug("cipherAlg - \(self.cipherAlg)" )
        Logger.pace.debug("digestAlg - \(self.digestAlg)" )
        Logger.pace.debug("keyLength - \(self.keyLength)" )
        // Never log the password (mrzKey/CAN) or the derived paceKey — PII / secret material.

        // First start the initial auth call
        _ = try await tagReader.sendMSESetATMutualAuth(oid: paceOID, keyType: paceKeyType)
            
        let decryptedNonce = try await self.doStep1()
        let ephemeralParams = try await self.doStep2(passportNonce: decryptedNonce)
        let (ephemeralKeyPair, passportPublicKey) = try await self.doStep3KeyExchange(ephemeralParams: ephemeralParams)
        let (encKey, macKey) = try await self.doStep4KeyAgreement( pcdKeyPair: ephemeralKeyPair, passportPublicKey: passportPublicKey)
        try self.paceCompleted( ksEnc: encKey, ksMac: macKey )
        Logger.pace.debug("PACE SUCCESSFUL" )
    }
    
    /// Handles an error during the PACE process
    /// Logs and stoes the error and returns false to the caller
    /// - Parameters:
    ///   - stage: Where in the PACE process the error occurred
    ///   - error: The error message
    func handleError( _ stage: String, _ error: String, needToTerminateGA: Bool = false ) {
        Logger.pace.error( "PACEHandler: \(stage) - \(error)" )
        Logger.pace.error( "   OpenSSLError: \(OpenSSLUtils.getOpenSSLError())" )
        self.paceError = "\(stage) - \(error)"
        //self.completedHandler?( false )

/*
        if needToTerminateGA {
            // This is to fix some passports that don't automatically terminate command chaining!
            // No idea if this is the correct way to do it but testing.....
            let terminateGA = wrapDO(b:0x83, arr:[0x00])
            tagReader.sendGeneralAuthenticate(data:terminateGA, isLast:true, completed: { [weak self] response, error in
                self?.completedHandler?( false )
            })
        } else {
            self.completedHandler?( false )
        }
*/
    }
    
    /// Performs PACE Step 1- receives an encrypted nonce from the passport and decypts it with the  PACE key - derived from MRZ or CAN
    func doStep1() async throws -> [UInt8] {
        Logger.pace.debug("Doing PACE Step1...")
        let response = try await tagReader.sendGeneralAuthenticate(data: [], isLast: false)
            
        let data = response.data
        let encryptedNonce = try unwrapDO(tag: 0x80, wrappedData: data)
        Logger.pace.debug( "Encrypted nonce - \(binToHexRep(encryptedNonce, asArray:true))" )

        let decryptedNonce: [UInt8]
        if self.cipherAlg == "DESede" {
            let iv = [UInt8](repeating:0, count: 8)
            decryptedNonce = tripleDESDecrypt(key: self.paceKey, message: encryptedNonce, iv: iv)
        } else if self.cipherAlg == "AES" {
            let iv = [UInt8](repeating:0, count: 16)
            decryptedNonce = AESDecrypt(key: self.paceKey, message: encryptedNonce, iv: iv)
        } else {
            throw NFCPassportReaderError.UnsupportedCipherAlgorithm
        }

        Logger.pace.debug( "Decrypted nonce - \(binToHexRep(decryptedNonce, asArray:true) )" )
        return decryptedNonce
    }
    
    
    /// Performs PACE Step 2 - computes ephemeral parameters by mapping the nonce received from the passport
    ///  (and if IM used the nonce generated by us)
    ///
    /// Using the supported
    /// - Parameters:
    ///   - passportNonce: The decrypted nonce received from the passport
    func doStep2( passportNonce: [UInt8]) async throws -> OpaquePointer {
        Logger.pace.debug( "Doing PACE Step2...")
        switch(mappingType) {
            case .CAM, .GM:
                Logger.pace.debug( "   Using General Mapping (GM)...")
                return try await doPACEStep2GM(passportNonce: passportNonce)
            case .IM:
                Logger.pace.debug( "   Using Integrated Mapping (IM)...")
                return try await doPACEStep2IM(passportNonce: passportNonce)
            default:
                throw NFCPassportReaderError.PACEError( "Step2GM", "Unsupported Mapping Type" )
        }

    }
    
    /// Performs PACEStep 2 using Generic Mapping
    ///
    /// Using the supported
    /// - Parameters:
    ///   - passportNonce: The decrypted nonce received from the passport
    func doPACEStep2GM(passportNonce : [UInt8]) async throws -> OpaquePointer {
        
        let mappingKey : OpaquePointer
        mappingKey = try self.paceInfo.createMappingKey( )

        guard let pcdMappingEncodedPublicKey = OpenSSLUtils.getPublicKeyData(from: mappingKey) else {
            throw NFCPassportReaderError.PACEError( "Step2GM", "Unable to get public key from mapping key")
        }
        Logger.pace.debug( "public mapping key - \(binToHexRep(pcdMappingEncodedPublicKey, asArray:true))")

        Logger.pace.debug( "Sending public mapping key to passport..")
        let step2Data = wrapDO(b:0x81, arr:pcdMappingEncodedPublicKey)
        let response = try await tagReader.sendGeneralAuthenticate(data:step2Data, isLast:false)

        let piccMappingEncodedPublicKey = try unwrapDO(tag: 0x82, wrappedData: response.data)
            
        Logger.pace.debug( "Received passports public mapping key")
        Logger.pace.debug( "   public mapping key - \(binToHexRep(piccMappingEncodedPublicKey, asArray: true))")

        // Do mapping agreement

        // First, Convert nonce to BIGNUM
        guard let bn_nonce = BN_bin2bn(passportNonce, Int32(passportNonce.count), nil) else {
            throw NFCPassportReaderError.PACEError( "Step2GM", "Unable to convert picc nonce to bignum" )
        }
        defer { BN_free(bn_nonce) }

        // ephmeralParams are free'd in stage 3
        let ephemeralParams : OpaquePointer
        if self.agreementAlg == "DH" {
            Logger.pace.debug( "Doing DH Mapping agreement")
            ephemeralParams = try self.doDHMappingAgreement(mappingKey: mappingKey, passportPublicKeyData: piccMappingEncodedPublicKey, nonce: bn_nonce )
        } else if self.agreementAlg == "ECDH" {
            Logger.pace.debug( "Doing ECDH Mapping agreement")
            ephemeralParams = try self.doECDHMappingAgreement(mappingKey: mappingKey, passportPublicKeyData: piccMappingEncodedPublicKey, nonce: bn_nonce )
        } else {
            throw NFCPassportReaderError.PACEError( "Step2GM", "Unsupported agreement algorithm" )
        }

        // Need to free the mapping key we created now
        EVP_PKEY_free(mappingKey)
        return ephemeralParams
    }
    
    func doPACEStep2IM( passportNonce: [UInt8] ) async throws -> OpaquePointer {
        // Generate PCD nonce (same length as PICC nonce)
        let pcdNonce = generateRandomUInt8Array(passportNonce.count)
        Logger.pace.debug("IM PCD nonce - \(binToHexRep(pcdNonce, asArray: true))")

        // Send PCD nonce to card (tag 0x81); card responds with empty tag 0x82
        let step2Data = wrapDO(b: 0x81, arr: pcdNonce)
        let _ = try await tagReader.sendGeneralAuthenticate(data: step2Data, isLast: false)
        // Card response with empty 0x82 is ignored per TR-SAC 3.3.2

        // Dispatch to ECDH or DH integrated mapping
        let ephemeralParams: OpaquePointer
        if self.agreementAlg == "ECDH" {
            Logger.pace.debug("Doing ECDH Integrated Mapping")
            ephemeralParams = try self.doECDHIMMapping(piccNonce: passportNonce, pcdNonce: pcdNonce)
        } else if self.agreementAlg == "DH" {
            Logger.pace.debug("Doing DH Integrated Mapping")
            ephemeralParams = try self.doDHIMMapping(piccNonce: passportNonce, pcdNonce: pcdNonce)
        } else {
            throw NFCPassportReaderError.PACEError("Step2IM", "Unsupported agreement algorithm")
        }

        return ephemeralParams
    }
    
    /// Generates an ephemeral public/private key pair based on mapping parameters from step 2, and then sends
    /// the public key to the passport and receives its ephmeral public key in exchange
    /// - Parameters:
    ///     - ephemeralParams: The ehpemeral mapping keys generated by step2
    /// - Returns:
///         - Tuple of Generated Ephemeral KeyPair and the Passport's public key
    func doStep3KeyExchange(ephemeralParams: OpaquePointer) async throws -> (OpaquePointer, OpaquePointer) {
        Logger.pace.debug( "Doing PACE Step3 - Key Exchange")

        // Generate ephemeral keypair from ephemeralParams
        var ephKeyPair : OpaquePointer? = nil
        let pctx = EVP_PKEY_CTX_new(ephemeralParams, nil)
        EVP_PKEY_keygen_init(pctx)
        EVP_PKEY_keygen(pctx, &ephKeyPair)
        EVP_PKEY_CTX_free(pctx)
                
        guard let ephemeralKeyPair = ephKeyPair else {
            throw NFCPassportReaderError.PACEError( "Step3 KeyEx", "Unable to get create ephermeral key pair" )
        }
        
        Logger.pace.debug( "Generated Ephemeral key pair")

        // We've finished with the ephemeralParams now - we can now free it
        EVP_PKEY_free( ephemeralParams )

        guard let publicKey = OpenSSLUtils.getPublicKeyData( from: ephemeralKeyPair ) else {
            throw NFCPassportReaderError.PACEError( "Step3 KeyEx", "Unable to get public key from ephermeral key pair" )
        }
        Logger.pace.debug( "Ephemeral public key - \(binToHexRep(publicKey, asArray: true))")

        // exchange public keys
        Logger.pace.debug( "Sending ephemeral public key to passport")
        let step3Data = wrapDO(b:0x83, arr:publicKey)
        let response = try await tagReader.sendGeneralAuthenticate(data:step3Data, isLast:false)
        let passportEncodedPublicKey = try? unwrapDO(tag: 0x84, wrappedData: response.data)
        guard let passportPublicKey = OpenSSLUtils.decodePublicKeyFromBytes(pubKeyData: passportEncodedPublicKey!, params: ephemeralKeyPair) else {
            throw NFCPassportReaderError.PACEError( "Step3 KeyEx", "Unable to decode passports ephemeral key" )
        }

        Logger.pace.debug( "Received passports ephemeral public key - \(binToHexRep(passportEncodedPublicKey!, asArray: true))" )
        return (ephemeralKeyPair, passportPublicKey)
    }
    
    /// This performs PACE Step 4 - Key Agreement.
    /// Here the shared secret is computed from our ephemeral private key and the passports ephemeral public key
    /// The new secure messaging (ksEnc and ksMac) keys are computed from the shared secret
    /// An authentication token is generated from the passports public key and the computed ksMac key
    /// Then, the authetication token is send to the passport, it returns its own computed authentication token
    /// We then compute an expected authentication token from the ksMac key and our ephemeral public key
    /// Finally we compare the recieved auth token to the expected token and if they are the same then PACE has succeeded!
    /// - Parameters:
    ///     - pcdKeyPair: our ephemeral key pair
    ///     - passportPublicKey: passports ephemeral public key
    /// - Returns:
    ///         - Tuple of KSEnc KSMac
    func doStep4KeyAgreement( pcdKeyPair: OpaquePointer, passportPublicKey: OpaquePointer) async throws -> ([UInt8], [UInt8]) {
        Logger.pace.debug( "Doing PACE Step4 Key Agreement...")

        Logger.pace.debug( "Computing shared secret...")
        let sharedSecret = OpenSSLUtils.computeSharedSecret(privateKeyPair: pcdKeyPair, publicKey: passportPublicKey)
        Logger.pace.debug( "Shared secret - \(binToHexRep(sharedSecret, asArray:true))")

        Logger.pace.debug( "Deriving ksEnc and ksMac keys from shared secret")
        let gen = SecureMessagingSessionKeyGenerator()
        let encKey = try! gen.deriveKey(keySeed: sharedSecret, cipherAlgName: cipherAlg, keyLength: keyLength, mode: .ENC_MODE)
        let macKey = try! gen.deriveKey(keySeed: sharedSecret, cipherAlgName: cipherAlg, keyLength: keyLength, mode: .MAC_MODE)
        Logger.pace.debug( "encKey - \(binToHexRep(encKey, asArray:true))")
        Logger.pace.debug( "macKey - \(binToHexRep(macKey, asArray:true))")

        // Step 4 - generate authentication token
        Logger.pace.debug( "Generating authentication token")
        guard let pcdAuthToken = try? generateAuthenticationToken( publicKey: passportPublicKey, macKey: macKey) else {
            throw NFCPassportReaderError.PACEError( "Step3 KeyAgreement", "Unable to generate authentication token using passports public key" )
        }
        Logger.pace.debug( "authentication token - \(pcdAuthToken)")

        Logger.pace.debug( "Sending auth token to passport")
        let step4Data = wrapDO(b:0x85, arr:pcdAuthToken)
        let response = try await tagReader.sendGeneralAuthenticate(data:step4Data, isLast:true)
            
        let tvlResp = TKBERTLVRecord.sequenceOfRecords(from: Data(response.data))!
        if tvlResp[0].tag != 0x86 {
            Logger.pace.warning("Was expecting tag 0x86, found: \(binToHex(UInt8(tvlResp[0].tag)))")
        }
        // Calculate expected authentication token
        let expectedPICCToken = try self.generateAuthenticationToken( publicKey: pcdKeyPair, macKey: macKey)
        
        Logger.pace.debug( "Expecting authentication token from passport - \(expectedPICCToken)")

        let piccToken = [UInt8](tvlResp[0].value)
        Logger.pace.debug( "Received authentication token from passport - \(piccToken)")

        guard piccToken == expectedPICCToken else {
            Logger.pace.error( "Error PICC Token mismatch!\npicToken - \(piccToken)\nexpectedPICCToken - \(expectedPICCToken)" )
            throw NFCPassportReaderError.PACEError( "Step3 KeyAgreement", "Error PICC Token mismatch!\npicToken - \(piccToken)\nexpectedPICCToken - \(expectedPICCToken)" )
        }
        
        Logger.pace.debug( "Auth token from passport matches expected token!" )
        
        // This will be added for CAM when supported
        // var encryptedChipAuthenticationData : [UInt8]? = nil
        // if (sself.mappingType == PACEMappingType.CAM) {
        //    if tvlResp[1].tag != 0x8A {
        //        Logger.pace.warning("CAM: Was expecting tag 0x86, found: \(binToHex(UInt8(tvlResp[1].tag)))")
        //    }
        //    encryptedChipAuthenticationData = [UInt8](tvlResp[1].value)
        // }
        
        // We're done!
        return (encKey, macKey)
    }
    
    /// Called once PACE has completed with the newly generated ksEnc and ksMac keys for restarting secure messaging
    /// - Parameters:
    ///   - ksEnc: the computed encryption key derived from the key agreement
    ///   - ksMac: the computed mac key derived from the key agreement
    func paceCompleted( ksEnc: [UInt8], ksMac: [UInt8] ) throws {
        // Restart secure messaging
        let ssc = withUnsafeBytes(of: 0.bigEndian, Array.init)
        if (cipherAlg.hasPrefix("DESede")) {
            Logger.pace.info( "Restarting secure messaging using DESede encryption")
            let sm = SecureMessaging(encryptionAlgorithm: .DES, ksenc: ksEnc, ksmac: ksMac, ssc: ssc)
            tagReader.secureMessaging = sm
        } else if (cipherAlg.hasPrefix("AES")) {
            Logger.pace.info( "Restarting secure messaging using AES encryption")
            let sm = SecureMessaging(encryptionAlgorithm: .AES, ksenc: ksEnc, ksmac: ksMac, ssc: ssc)
            tagReader.secureMessaging = sm
        } else {
            throw NFCPassportReaderError.PACEError( "PACECompleted", "Not restarting secure messaging as unsupported cipher algorithm requested - \(cipherAlg)" )
        }
    }
}

// MARK - PACEHandler Utility functions
@available(iOS 15, *)
extension PACEHandler {
    
    /// Does the DH key Mapping agreement
    /// - Parameter mappingKey - Pointer to an EVP_PKEY structure containing the mapping key
    /// - Parameter passportPublicKeyData - byte array containing the publick key read from the passport
    /// - Parameter nonce - Pointer to an BIGNUM structure containing the unencrypted nonce
    /// - Returns the EVP_PKEY containing the mapped ephemeral parameters
    func doDHMappingAgreement( mappingKey : OpaquePointer, passportPublicKeyData: [UInt8], nonce: OpaquePointer ) throws -> OpaquePointer {
        guard let dh_mapping_key = EVP_PKEY_get1_DH(mappingKey) else {
            // Error
            throw PACEHandlerError.DHKeyAgreementError( "Unable to get DH mapping key" )
        }
        
        // Compute the shared secret using the mapping key and the passports public mapping key
        let bn = BN_bin2bn(passportPublicKeyData, Int32(passportPublicKeyData.count), nil)
        defer { BN_free( bn ) }
        
        var secret = [UInt8](repeating: 0, count: Int(DH_size(dh_mapping_key)))
        DH_compute_key( &secret, bn, dh_mapping_key)
        
        // Convert the secret to a bignum
        let bn_h = BN_bin2bn(secret, Int32(secret.count), nil)
        defer { BN_clear_free(bn_h) }
        
        // Initialize ephemeral parameters with parameters from the mapping key
        guard let ephemeral_key = DHparams_dup(dh_mapping_key) else {
            // Error
            throw PACEHandlerError.DHKeyAgreementError("Unable to get initialise ephemeral parameters from DH mapping key")
        }
        defer{ DH_free(ephemeral_key) }
        
        var p : OpaquePointer? = nil
        var q : OpaquePointer? = nil
        var g : OpaquePointer? = nil
        DH_get0_pqg(dh_mapping_key, &p, &q, &g)
        
        // map to new generator
        guard let bn_g = BN_new() else {
            throw PACEHandlerError.DHKeyAgreementError( "Unable to create bn_g" )
        }
        defer{ BN_free(bn_g) }
        guard let new_g = BN_new() else {
            throw PACEHandlerError.DHKeyAgreementError( "Unable to create new_g" )
        }
        defer{ BN_free(new_g) }
        
        // bn_g = g^nonce mod p
        // ephemeral_key->g = bn_g mod p * h  => (g^nonce mod p) * h mod p
        let bn_ctx = BN_CTX_new()
        guard BN_mod_exp(bn_g, g, nonce, p, bn_ctx) == 1,
              BN_mod_mul(new_g, bn_g, bn_h, p, bn_ctx) == 1 else {
            // Error
            throw PACEHandlerError.DHKeyAgreementError( "Failed to generate new parameters" )
        }
        
        guard DH_set0_pqg(ephemeral_key, BN_dup(p), BN_dup(q), BN_dup(new_g)) == 1 else {
            // Error
            throw PACEHandlerError.DHKeyAgreementError( "Unable to set DH pqg paramerters" )
        }
        
        // Set the ephemeral params
        guard let ephemeralParams = EVP_PKEY_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError( "Unable to create ephemeral params" )
        }

        guard EVP_PKEY_set1_DH(ephemeralParams, ephemeral_key) == 1 else {
            // Error
            EVP_PKEY_free( ephemeralParams )
            throw PACEHandlerError.DHKeyAgreementError( "Unable to set ephemeral parameters" )
        }
        return ephemeralParams
    }
    
    /// Does the ECDH key Mapping agreement
    /// - Parameter mappingKey - Pointer to an EVP_PKEY structure containing the mapping key
    /// - Parameter passportPublicKeyData - byte array containing the publick key read from the passport
    /// - Parameter nonce - Pointer to an BIGNUM structure containing the unencrypted nonce
    /// - Returns the EVP_PKEY containing the mapped ephemeral parameters
    func doECDHMappingAgreement( mappingKey : OpaquePointer, passportPublicKeyData: [UInt8], nonce: OpaquePointer ) throws -> OpaquePointer {

        let ec_mapping_key = EVP_PKEY_get1_EC_KEY(mappingKey)
        
        guard let group = EC_GROUP_dup(EC_KEY_get0_group(ec_mapping_key)) else {
            // Error
            throw PACEHandlerError.ECDHKeyAgreementError( "Unable to get EC group" )
        }
        defer { EC_GROUP_free(group) }
        
        guard let order = BN_new() else {
            // Error
            throw PACEHandlerError.ECDHKeyAgreementError( "Unable to create order bignum" )
        }
        defer { BN_free( order ) }
        
        guard let cofactor = BN_new() else {
            // error
            throw PACEHandlerError.ECDHKeyAgreementError( "Unable to create cofactor bignum" )
        }
        defer { BN_free( cofactor ) }
        
        guard EC_GROUP_get_order(group, order, nil) == 1 ||
                EC_GROUP_get_cofactor(group, cofactor, nil) == 1 else {
            // Handle error
            throw PACEHandlerError.ECDHKeyAgreementError( "Unable to get order or cofactor from group" )
        }
        
        // Create the shared secret in the form of a ECPoint

        // Ideally I'd use OpenSSLUtls.computeSharedSecret for this but for reasons as yet unknown, it only returns the first 32 bytes
        // NOT the full 64 bytes (would then convert to 65 with e header of 4 for uncompressed)
        guard let sharedSecretMappingPoint = self.computeECDHMappingKeyPoint(privateKey: mappingKey, inputKey: passportPublicKeyData) else {
            // Error
            throw PACEHandlerError.ECDHKeyAgreementError( "Failed to compute new shared secret mapping point from mapping key and passport public mapping key" )
        }
        defer { EC_POINT_free( sharedSecretMappingPoint ) }

        // Map the nonce using Generic mapping to get the new parameters (inc a new generator)
        guard let newGenerater = EC_POINT_new(group) else {
            throw PACEHandlerError.ECDHKeyAgreementError( "Unable to create new mapping generator point" )
        }
        defer{ EC_POINT_free(newGenerater) }
        
        // g = (generator * nonce) + (sharedSecretMappingPoint * 1)
        guard EC_POINT_mul(group, newGenerater, nonce, sharedSecretMappingPoint, BN_value_one(), nil) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError( "Failed to map nonce to get new generator params" )
        }
        
        // Initialize ephemeral parameters with parameters from the mapping key
        guard let ephemeralParams = EVP_PKEY_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError( "Unable to create ephemeral params" )
        }

        let ephemeral_key = EC_KEY_dup(ec_mapping_key)
        defer{ EC_KEY_free(ephemeral_key) }
        
        // configure the new EC_KEY
        guard EVP_PKEY_set1_EC_KEY(ephemeralParams, ephemeral_key) == 1,
              EC_GROUP_set_generator(group, newGenerater, order, cofactor) == 1,
              EC_GROUP_check(group, nil) == 1,
              EC_KEY_set_group(ephemeral_key, group) == 1 else {
            // Error

            EVP_PKEY_free( ephemeralParams )
            throw PACEHandlerError.ECDHKeyAgreementError( "Unable to configure new ephemeral params" )
        }
        return ephemeralParams
    }
    
    /// Generate Authentication token from a publicKey and and a mac key
    /// - Parameters:
    ///   - publicKey: An EVP_PKEY structure containing a public key data which will be used to generate the auth code
    ///   - macKey: The mac key derived from the key agreement
    /// - Throws: An error if we are unable to encode the public key data
    /// - Returns: The authentication token (8 bytes)
    func generateAuthenticationToken( publicKey: OpaquePointer, macKey: [UInt8] ) throws -> [UInt8] {
        var encodedPublicKeyData = try encodePublicKey(oid:self.paceOID, key:publicKey)
        
        if cipherAlg == "DESede" {
            // If DESede (3DES), we need to pad the data
            encodedPublicKeyData = pad(encodedPublicKeyData, blockSize: 8)
        }
        
        Logger.pace.debug( "Generating Authentication Token" )
        Logger.pace.debug( "EncodedPubKey = \(binToHexRep(encodedPublicKeyData, asArray: true))" )
        Logger.pace.debug( "macKey = \(binToHexRep(macKey, asArray: true))" )

        let maccedPublicKeyDataObject = mac(algoName: cipherAlg == "DESede" ? .DES : .AES, key: macKey, msg: encodedPublicKeyData)

        // Take 8 bytes for auth token
        let authToken = [UInt8](maccedPublicKeyDataObject[0..<8])
        Logger.pace.debug( "Generated authToken = \(binToHexRep(authToken, asArray: true))" )
        return authToken
    }
    
    /// Encodes a PublicKey as an TLV strucuture based on TR-SAC 1.01 4.5.1 and 4.5.2
    /// - Parameters:
    ///   - oid: The object identifier specifying the key type
    ///   - key: The ECP_PKEY public key to encode
    /// - Throws: Error if unable to encode
    /// - Returns: the encoded public key in tlv format
    func encodePublicKey( oid : String, key : OpaquePointer ) throws -> [UInt8] {
        let encodedOid = oidToBytes(oid:oid, replaceTag: false)
        guard let pubKeyData = OpenSSLUtils.getPublicKeyData(from: key) else {
            Logger.pace.error( "PACEHandler: encodePublicKey() - Unable to get public key data" )
            throw NFCPassportReaderError.InvalidDataPassed("Unable to get public key data")
        }

        let keyType = EVP_PKEY_base_id( key )
        let tag : TKTLVTag
        if keyType == EVP_PKEY_DH || keyType == EVP_PKEY_DHX {
            tag = 0x84
        } else {
            tag = 0x86
        }

        guard let encOid = TKBERTLVRecord(from: Data(encodedOid)) else {
            throw NFCPassportReaderError.InvalidASN1Value
        }
        let encPub = TKBERTLVRecord(tag:tag, value: Data(pubKeyData))
        let record = TKBERTLVRecord(tag: 0x7F49, records:[encOid, encPub])
        let data = record.data

        return [UInt8](data)
    }

    /// Computes a key seed based on an MRZ key
    /// - Parameter the mrz key
    /// - Returns a encoded key based on the mrz key that can be used for PACE
    func createPaceKey( from mrzKey: String ) throws -> [UInt8] {
        let buf: [UInt8] = Array(mrzKey.utf8)
        let hash = calcSHA1Hash(buf)

        let smskg = SecureMessagingSessionKeyGenerator()
        let key = try smskg.deriveKey(keySeed: hash, cipherAlgName: cipherAlg, keyLength: keyLength, nonce: nil, mode: .PACE_MODE, paceKeyReference: paceKeyType)
        return key
    }

    /// Computes the PACE key from a CAN (Card Access Number)
    /// ICAO 9303-11 §9.7.3: unlike the MRZ password, the CAN key seed is the
    /// CAN's encoded bytes used directly — it is NOT SHA-1 hashed first.
    /// - Parameter can: the card access number (printed on the document)
    /// - Returns an encoded key based on the CAN that can be used for PACE
    func createPaceKey( fromCAN can: String ) throws -> [UInt8] {
        let keySeed: [UInt8] = Array(can.utf8)

        let smskg = SecureMessagingSessionKeyGenerator()
        let key = try smskg.deriveKey(keySeed: keySeed, cipherAlgName: cipherAlg, keyLength: keyLength, nonce: nil, mode: .PACE_MODE, paceKeyReference: paceKeyType)
        return key
    }
    
    /// Performs the ECDH PACE GM key agreement protocol by multiplying a private key with a public key
    /// - Parameters:
    ///   - key: an EVP_PKEY structure containng a ECDH private key
    ///   - inputKey: a public key
    /// - Returns: a new EC_POINT
    func computeECDHMappingKeyPoint( privateKey : OpaquePointer, inputKey : [UInt8] ) -> OpaquePointer? {
        
        let ecdh = EVP_PKEY_get1_EC_KEY(privateKey)
        defer { EC_KEY_free(ecdh) }

        let privateECKey = EC_KEY_get0_private_key(ecdh) // BIGNUM

        // decode public key
        guard let group = EC_KEY_get0_group(ecdh) else{ return nil }
        guard let ecp = EC_POINT_new(group) else { return nil }
        defer { EC_POINT_free(ecp) }
        guard EC_POINT_oct2point(group, ecp, inputKey, inputKey.count,nil) != 0 else { return nil }
                
        // create our output point
        let output = EC_POINT_new(group)

        // Multiply our private key with the passports public key to get a new point
        EC_POINT_mul(group, output, nil, ecp, privateECKey, nil)
        
        return output
    }

    // MARK: - PACE Integrated Mapping (IM) helpers

    /// ICAO 9303-11 Section 4.4.3.3.2 cipher-based pseudo-random function.
    /// Computes PRF(s, t) mod p using AES-CBC chaining.
    func pseudoRandomFunction(s: [UInt8], t: [UInt8], p: OpaquePointer) throws -> [UInt8] {
        let nonceBitLen = s.count * 8
        let c0: [UInt8]
        let c1: [UInt8]

        switch nonceBitLen {
        case 128:
            c0 = PACEHandler.C0_128
            c1 = PACEHandler.C1_128
        case 192, 256:
            c0 = PACEHandler.C0_256
            c1 = PACEHandler.C1_256
        default:
            throw NFCPassportReaderError.PACEError("PRF", "Unsupported nonce bit length: \(nonceBitLen)")
        }

        let iv = [UInt8](repeating: 0, count: 16)
        let l = 128 // AES block size in bits
        let k = nonceBitLen // cipher key length in bits
        let pBitLen = Int(BN_num_bits(p))
        let targetBits = pBitLen + 64

        // Initial key derivation: key = AESEncrypt(key: t, message: s, iv: zeros)
        var key = AESEncrypt(key: t, message: s, iv: iv)

        var output: [UInt8] = []
        var n = 0
        while n * l < targetBits {
            let currentKey = Array(key.prefix(k / 8))
            // Key update: encrypt C0 with currentKey
            let newKey = AESEncrypt(key: currentKey, message: c0, iv: iv)
            // Output block: encrypt C1 with currentKey (before key update)
            let x_n = AESEncrypt(key: currentKey, message: c1, iv: iv)
            key = newKey
            output.append(contentsOf: x_n)
            n += 1
        }

        // Convert output to BIGNUM, compute mod p
        guard let bn_output = BN_bin2bn(output, Int32(output.count), nil) else {
            throw NFCPassportReaderError.PACEError("PRF", "Failed to convert PRF output to BIGNUM")
        }
        defer { BN_free(bn_output) }

        guard let bn_result = BN_new() else {
            throw NFCPassportReaderError.PACEError("PRF", "Failed to allocate result BIGNUM")
        }
        defer { BN_free(bn_result) }

        let bn_ctx = BN_CTX_new()
        defer { BN_CTX_free(bn_ctx) }

        guard BN_nnmod(bn_result, bn_output, p, bn_ctx) == 1 else {
            throw NFCPassportReaderError.PACEError("PRF", "Failed to compute PRF output mod p")
        }

        // Convert result back to byte array
        let resultLen = Int((BN_num_bits(bn_result) + 7) / 8)
        var resultBytes = [UInt8](repeating: 0, count: resultLen)
        BN_bn2bin(bn_result, &resultBytes)

        Logger.pace.debug("IM PRF output t = \(binToHexRep(resultBytes, asArray: true))")
        return resultBytes
    }

    /// Icart's deterministic hash-to-curve encoding.
    /// Maps a field element t to a point on the elliptic curve.
    /// Requires curve prime p ≡ 2 mod 3 (satisfied by Brainpool P-256-r1).
    func icartPointEncode(t: OpaquePointer, group: OpaquePointer) throws -> OpaquePointer {
        let bn_ctx = BN_CTX_new()
        defer { BN_CTX_free(bn_ctx) }

        // Get curve parameters p, a, b
        guard let bn_p = BN_new(), let bn_a = BN_new(), let bn_b = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to allocate curve param BIGNUMs")
        }
        defer { BN_free(bn_p); BN_free(bn_a); BN_free(bn_b) }

        guard EC_GROUP_get_curve(group, bn_p, bn_a, bn_b, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to get curve parameters")
        }

        // Verify p ≡ 2 mod 3 (required for Icart's cube root)
        guard let bn_three = BN_new(), let bn_rem = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: alloc failed")
        }
        defer { BN_free(bn_three); BN_free(bn_rem) }
        BN_set_word(bn_three, 3)
        guard BN_nnmod(bn_rem, bn_p, bn_three, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to check p mod 3")
        }
        guard BN_is_word(bn_rem, 2) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: curve prime p ≢ 2 mod 3, Icart encoding unsupported")
        }

        // alpha = -t^2 mod p
        guard let alpha = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: alloc failed")
        }
        defer { BN_free(alpha) }
        guard BN_mod_sqr(alpha, t, bn_p, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute t^2")
        }
        guard BN_sub(alpha, bn_p, alpha) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to negate")
        }

        // alpha^2
        guard let alpha2 = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: alloc failed")
        }
        defer { BN_free(alpha2) }
        guard BN_mod_sqr(alpha2, alpha, bn_p, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute alpha^2")
        }

        // numerator = -b * (1 + alpha + alpha^2) mod p
        guard let one_plus_alpha = BN_new(), let num_factor = BN_new(),
              let neg_b = BN_new(), let numerator = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: alloc failed")
        }
        defer { BN_free(one_plus_alpha); BN_free(num_factor); BN_free(neg_b); BN_free(numerator) }

        guard BN_mod_add(one_plus_alpha, BN_value_one(), alpha, bn_p, bn_ctx) == 1,
              BN_mod_add(num_factor, one_plus_alpha, alpha2, bn_p, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute 1 + alpha + alpha^2")
        }
        guard BN_sub(neg_b, bn_p, bn_b) == 1,
              BN_mod_mul(numerator, neg_b, num_factor, bn_p, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute numerator")
        }

        // denominator = a * (alpha + alpha^2) mod p
        guard let alpha_sum = BN_new(), let denominator = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: alloc failed")
        }
        defer { BN_free(alpha_sum); BN_free(denominator) }

        guard BN_mod_add(alpha_sum, alpha, alpha2, bn_p, bn_ctx) == 1,
              BN_mod_mul(denominator, bn_a, alpha_sum, bn_p, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute denominator")
        }

        // x2 = numerator * inverse(denominator) mod p
        guard let inv_denom = BN_mod_inverse(nil, denominator, bn_p, bn_ctx) else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute modular inverse (t may map to singular point)")
        }
        defer { BN_free(inv_denom) }

        guard let x2 = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: alloc failed")
        }
        defer { BN_free(x2) }
        guard BN_mod_mul(x2, numerator, inv_denom, bn_p, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute x2")
        }

        // x3 = alpha * x2 mod p
        guard let x3 = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: alloc failed")
        }
        defer { BN_free(x3) }
        guard BN_mod_mul(x3, alpha, x2, bn_p, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute x3")
        }

        // h2 = x2^3 + a*x2 + b mod p
        guard let h2 = BN_new(), let tmp = BN_new(), let tmp2 = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: alloc failed")
        }
        defer { BN_free(h2); BN_free(tmp); BN_free(tmp2) }

        guard BN_mod_sqr(tmp, x2, bn_p, bn_ctx) == 1,
              BN_mod_mul(h2, tmp, x2, bn_p, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute x2^3")
        }
        guard BN_mod_mul(tmp, bn_a, x2, bn_p, bn_ctx) == 1,
              BN_mod_add(h2, h2, tmp, bn_p, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to add a*x2")
        }
        guard BN_mod_add(h2, h2, bn_b, bn_p, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to add b")
        }

        // u = t^3 * h2 mod p
        guard let t_cubed = BN_new(), let u = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: alloc failed")
        }
        defer { BN_free(t_cubed); BN_free(u) }

        guard BN_mod_sqr(tmp, t, bn_p, bn_ctx) == 1,
              BN_mod_mul(t_cubed, tmp, t, bn_p, bn_ctx) == 1,
              BN_mod_mul(u, t_cubed, h2, bn_p, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute u = t^3 * h2")
        }

        // Euler criterion: aa = h2^(p - 1 - (p+1)/4) mod p
        // exponent = (3p - 5) / 4
        guard let exponent = BN_new(), let p_plus_1 = BN_new(),
              let p_plus_1_div_4 = BN_new(), let p_minus_1 = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: alloc failed")
        }
        defer { BN_free(exponent); BN_free(p_plus_1); BN_free(p_plus_1_div_4); BN_free(p_minus_1) }

        guard BN_add(p_plus_1, bn_p, BN_value_one()) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute p+1")
        }
        guard BN_rshift(p_plus_1_div_4, p_plus_1, 2) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute (p+1)/4")
        }
        guard BN_sub(p_minus_1, bn_p, BN_value_one()) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute p-1")
        }
        guard BN_sub(exponent, p_minus_1, p_plus_1_div_4) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute exponent")
        }

        guard let aa = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: alloc failed")
        }
        defer { BN_free(aa) }
        guard BN_mod_exp(aa, h2, exponent, bn_p, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute aa = h2^exp")
        }

        // Check if h2 is a quadratic residue: aa^2 * h2 == 1 mod p
        guard BN_mod_sqr(tmp, aa, bn_p, bn_ctx) == 1,
              BN_mod_mul(tmp2, tmp, h2, bn_p, bn_ctx) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed Euler criterion check")
        }

        let x_coord: OpaquePointer
        guard let y_coord = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: alloc failed")
        }
        defer { BN_free(y_coord) }

        if BN_is_one(tmp2) == 1 {
            // QR case: point is (x2, aa * h2 mod p)
            x_coord = x2
            guard BN_mod_mul(y_coord, aa, h2, bn_p, bn_ctx) == 1 else {
                throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute y for QR case")
            }
        } else {
            // Non-QR case: point is (x3, aa * u mod p)
            x_coord = x3
            guard BN_mod_mul(y_coord, aa, u, bn_p, bn_ctx) == 1 else {
                throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to compute y for non-QR case")
            }
        }

        // Create EC_POINT and set affine coordinates
        guard let point = EC_POINT_new(group) else {
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to create EC_POINT")
        }

        guard EC_POINT_set_affine_coordinates(group, point, x_coord, y_coord, bn_ctx) == 1 else {
            EC_POINT_free(point)
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to set affine coordinates")
        }

        guard EC_POINT_is_on_curve(group, point, bn_ctx) == 1 else {
            EC_POINT_free(point)
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Mapped point is not on curve")
        }

        // Multiply by cofactor if cofactor > 1
        guard let cof = BN_new() else {
            EC_POINT_free(point)
            throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: alloc failed")
        }
        defer { BN_free(cof) }
        EC_GROUP_get_cofactor(group, cof, nil)

        if BN_is_one(cof) != 1 {
            guard let cofactorPoint = EC_POINT_new(group) else {
                EC_POINT_free(point)
                throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed to create cofactor point")
            }
            guard EC_POINT_mul(group, cofactorPoint, nil, point, cof, bn_ctx) == 1 else {
                EC_POINT_free(cofactorPoint)
                EC_POINT_free(point)
                throw PACEHandlerError.ECDHKeyAgreementError("IcartEncode: Failed cofactor multiplication")
            }
            EC_POINT_copy(point, cofactorPoint)
            EC_POINT_free(cofactorPoint)
        }

        return point
    }

    /// Performs ECDH Integrated Mapping to compute new ephemeral domain parameters.
    func doECDHIMMapping(piccNonce: [UInt8], pcdNonce: [UInt8]) throws -> OpaquePointer {
        guard let ec_key = EC_KEY_new_by_curve_name(self.parameterSpec) else {
            throw PACEHandlerError.ECDHKeyAgreementError("IM: Unable to create EC key from parameterSpec")
        }
        defer { EC_KEY_free(ec_key) }

        guard let group = EC_GROUP_dup(EC_KEY_get0_group(ec_key)) else {
            throw PACEHandlerError.ECDHKeyAgreementError("IM: Unable to get EC group")
        }
        defer { EC_GROUP_free(group) }

        guard let order = BN_new(), let cofactor = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IM: Unable to create order/cofactor BIGNUMs")
        }
        defer { BN_free(order); BN_free(cofactor) }

        guard EC_GROUP_get_order(group, order, nil) == 1,
              EC_GROUP_get_cofactor(group, cofactor, nil) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IM: Unable to get order or cofactor")
        }

        // Get curve prime p for PRF
        guard let bn_p = BN_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IM: Unable to create prime BIGNUM")
        }
        defer { BN_free(bn_p) }

        guard EC_GROUP_get_curve(group, bn_p, nil, nil, nil) == 1 else {
            throw PACEHandlerError.ECDHKeyAgreementError("IM: Unable to get curve prime")
        }

        // Compute PRF(piccNonce, pcdNonce) mod p
        let tBytes = try pseudoRandomFunction(s: piccNonce, t: pcdNonce, p: bn_p)

        guard let bn_t = BN_bin2bn(tBytes, Int32(tBytes.count), nil) else {
            throw PACEHandlerError.ECDHKeyAgreementError("IM: Unable to convert PRF output to BIGNUM")
        }
        defer { BN_free(bn_t) }

        // Map t to new generator via Icart's point encoding
        let newGenerator = try icartPointEncode(t: bn_t, group: group)
        defer { EC_POINT_free(newGenerator) }

        // Build EVP_PKEY with new generator (same pattern as doECDHMappingAgreement)
        guard let ephemeralParams = EVP_PKEY_new() else {
            throw PACEHandlerError.ECDHKeyAgreementError("IM: Unable to create ephemeral params")
        }

        let ephemeral_key = EC_KEY_dup(ec_key)
        defer { EC_KEY_free(ephemeral_key) }

        guard EVP_PKEY_set1_EC_KEY(ephemeralParams, ephemeral_key) == 1,
              EC_GROUP_set_generator(group, newGenerator, order, cofactor) == 1,
              EC_GROUP_check(group, nil) == 1,
              EC_KEY_set_group(ephemeral_key, group) == 1 else {
            EVP_PKEY_free(ephemeralParams)
            throw PACEHandlerError.ECDHKeyAgreementError("IM: Unable to configure ephemeral params")
        }

        return ephemeralParams
    }

    /// Performs DH Integrated Mapping to compute new ephemeral domain parameters.
    func doDHIMMapping(piccNonce: [UInt8], pcdNonce: [UInt8]) throws -> OpaquePointer {
        let dhKey: OpaquePointer?
        switch self.parameterSpec {
        case 0:
            dhKey = DH_get_1024_160()
        case 1:
            dhKey = DH_get_2048_224()
        case 2:
            dhKey = DH_get_2048_256()
        default:
            throw PACEHandlerError.DHKeyAgreementError("IM: Unsupported DH parameter spec: \(self.parameterSpec)")
        }

        guard let dh = dhKey else {
            throw PACEHandlerError.DHKeyAgreementError("IM: Unable to create DH params")
        }
        defer { DH_free(dh) }

        var p: OpaquePointer? = nil
        var q: OpaquePointer? = nil
        var g: OpaquePointer? = nil
        DH_get0_pqg(dh, &p, &q, &g)

        guard let bn_p = p, let bn_q = q else {
            throw PACEHandlerError.DHKeyAgreementError("IM: Unable to get DH params p, q")
        }

        // Compute PRF(piccNonce, pcdNonce) mod p
        let xBytes = try pseudoRandomFunction(s: piccNonce, t: pcdNonce, p: bn_p)

        guard let bn_x = BN_bin2bn(xBytes, Int32(xBytes.count), nil) else {
            throw PACEHandlerError.DHKeyAgreementError("IM: Unable to convert PRF output to BIGNUM")
        }
        defer { BN_free(bn_x) }

        // cofactorA = (p-1) / q
        guard let cofactorA = BN_new(), let p_minus_1 = BN_new() else {
            throw PACEHandlerError.DHKeyAgreementError("IM: alloc failed")
        }
        defer { BN_free(cofactorA); BN_free(p_minus_1) }

        let bn_ctx = BN_CTX_new()
        defer { BN_CTX_free(bn_ctx) }

        guard BN_sub(p_minus_1, bn_p, BN_value_one()) == 1,
              BN_div(cofactorA, nil, p_minus_1, bn_q, bn_ctx) == 1 else {
            throw PACEHandlerError.DHKeyAgreementError("IM: Failed to compute (p-1)/q")
        }

        // newG = x^cofactorA mod p
        guard let newG = BN_new() else {
            throw PACEHandlerError.DHKeyAgreementError("IM: alloc failed")
        }
        defer { BN_free(newG) }

        guard BN_mod_exp(newG, bn_x, cofactorA, bn_p, bn_ctx) == 1 else {
            throw PACEHandlerError.DHKeyAgreementError("IM: Failed to compute new generator")
        }

        // Build EVP_PKEY with new DH params (same pattern as doDHMappingAgreement)
        guard let ephemeral_key = DHparams_dup(dh) else {
            throw PACEHandlerError.DHKeyAgreementError("IM: Unable to duplicate DH params")
        }
        defer { DH_free(ephemeral_key) }

        guard DH_set0_pqg(ephemeral_key, BN_dup(bn_p), BN_dup(bn_q), BN_dup(newG)) == 1 else {
            throw PACEHandlerError.DHKeyAgreementError("IM: Unable to set DH pqg parameters")
        }

        guard let ephemeralParams = EVP_PKEY_new() else {
            throw PACEHandlerError.DHKeyAgreementError("IM: Unable to create ephemeral params")
        }

        guard EVP_PKEY_set1_DH(ephemeralParams, ephemeral_key) == 1 else {
            EVP_PKEY_free(ephemeralParams)
            throw PACEHandlerError.DHKeyAgreementError("IM: Unable to set ephemeral parameters")
        }

        return ephemeralParams
    }
}

#endif
