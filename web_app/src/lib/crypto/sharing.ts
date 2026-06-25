// sharing.ts
// Enterprise asymmetric key sharing using ECDH P-384 key agreement and JWE wrapping

import { Buffer } from "buffer";

export interface JweHeader {
  alg: string;
  enc: string;
  epk: JsonWebKey;
}

// Convert ArrayBuffer to URL-safe Base64
function base64UrlEncode(buffer: ArrayBuffer | Uint8Array): string {
  const buf = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  return Buffer.from(buf.buffer, buf.byteOffset, buf.byteLength)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

// Convert URL-safe Base64 to ArrayBuffer
function base64UrlDecode(str: string): ArrayBuffer {
  const base64 = str.replace(/-/g, "+").replace(/_/g, "/");
  return Buffer.from(base64, "base64").buffer as ArrayBuffer;
}

export class AsymmetricSharing {
  /**
   * Generate a unique ECDH key pair on the P-384 curve.
   */
  static async generateKeyPair(): Promise<CryptoKeyPair> {
    return await self.crypto.subtle.generateKey(
      {
        name: "ECDH",
        namedCurve: "P-384",
      },
      true,
      ["deriveKey", "deriveBits"]
    );
  }

  /**
   * Wrap an AES-256 Vault Key inside a compact JSON Web Encryption (JWE) token.
   * @param vaultKey Symmetric AES-GCM Vault Key (AES-256)
   * @param recipientPubKey Recipient's public ECDH key
   */
  static async wrapVaultKey(vaultKey: CryptoKey, recipientPubKey: CryptoKey): Promise<string> {
    // 1. Generate Ephemeral P-384 key pair
    const ephemeralKeyPair = await self.crypto.subtle.generateKey(
      {
        name: "ECDH",
        namedCurve: "P-384",
      },
      true,
      ["deriveKey", "deriveBits"]
    );

    // 2. Perform ECDH key agreement to derive shared secret bits
    const sharedSecretBits = await self.crypto.subtle.deriveBits(
      {
        name: "ECDH",
        public: recipientPubKey,
      },
      ephemeralKeyPair.privateKey,
      384
    );

    // 3. Derive 256-bit Key Wrapping Key (KWK) via HKDF-SHA384
    const hkdfMasterKey = await self.crypto.subtle.importKey(
      "raw",
      sharedSecretBits,
      { name: "HKDF" },
      false,
      ["deriveKey"]
    );

    const kwk = await self.crypto.subtle.deriveKey(
      {
        name: "HKDF",
        hash: "SHA-384",
        salt: new Uint8Array(), // Empty salt as per RFC 7518
        info: new TextEncoder().encode("AMPCRYPT-JWE-KEY-WRAP"),
      },
      hkdfMasterKey,
      { name: "AES-GCM", length: 256 },
      false,
      ["wrapKey", "unwrapKey"]
    );

    // 4. Wrap the Vault Key using AES-GCM
    const iv = self.crypto.getRandomValues(new Uint8Array(12));
    const wrappedBuffer = await self.crypto.subtle.wrapKey(
      "raw",
      vaultKey,
      kwk,
      {
        name: "AES-GCM",
        iv: iv,
        tagLength: 128,
      }
    );

    // 5. Extract ciphertext and authentication tag (last 16 bytes)
    const wrappedArray = new Uint8Array(wrappedBuffer);
    const ciphertext = wrappedArray.slice(0, wrappedArray.byteLength - 16);
    const tag = wrappedArray.slice(wrappedArray.byteLength - 16);

    // 6. Export Ephemeral Public Key in JWK format
    const epkJwk = await self.crypto.subtle.exportKey("jwk", ephemeralKeyPair.publicKey);

    // 7. Assemble JWE Header
    const header: JweHeader = {
      alg: "ECDH-ES+A256GCM",
      enc: "A256GCM",
      epk: epkJwk,
    };

    // Serialize and base64url encode Header
    const headerB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(header)));
    const ivB64 = base64UrlEncode(iv.buffer as ArrayBuffer);
    const ciphertextB64 = base64UrlEncode(ciphertext.buffer as ArrayBuffer);
    const tagB64 = base64UrlEncode(tag.buffer as ArrayBuffer);

    // Assemble compact JWE token: Header . EncryptedKey (empty) . IV . Ciphertext . Tag
    return `${headerB64}..${ivB64}.${ciphertextB64}.${tagB64}`;
  }

  /**
   * Decrypt and unwrap a JWE compact token back into the Vault Key (AES-256).
   * @param jweCompact Compact JWE token string
   * @param recipientPrivKey Recipient's private ECDH key
   */
  static async unwrapVaultKey(jweCompact: string, recipientPrivKey: CryptoKey): Promise<CryptoKey> {
    const parts = jweCompact.split(".");
    if (parts.length !== 5) {
      throw new Error("Invalid compact JWE format.");
    }

    const [headerB64, , ivB64, ciphertextB64, tagB64] = parts;
    const headerBytes = new TextDecoder().decode(base64UrlDecode(headerB64));
    const header = JSON.parse(headerBytes) as JweHeader;

    if (!header.epk) {
      throw new Error("Missing Ephemeral Public Key (epk) in JWE header.");
    }

    // 1. Import Ephemeral Public Key
    const ephemeralPubKey = await self.crypto.subtle.importKey(
      "jwk",
      header.epk,
      {
        name: "ECDH",
        namedCurve: "P-384",
      },
      true,
      []
    );

    // 2. Perform ECDH key agreement to derive shared secret bits
    const sharedSecretBits = await self.crypto.subtle.deriveBits(
      {
        name: "ECDH",
        public: ephemeralPubKey,
      },
      recipientPrivKey,
      384
    );

    // 3. Derive 256-bit Key Wrapping Key (KWK) via HKDF-SHA384
    const hkdfMasterKey = await self.crypto.subtle.importKey(
      "raw",
      sharedSecretBits,
      { name: "HKDF" },
      false,
      ["deriveKey"]
    );

    const kwk = await self.crypto.subtle.deriveKey(
      {
        name: "HKDF",
        hash: "SHA-384",
        salt: new Uint8Array(),
        info: new TextEncoder().encode("AMPCRYPT-JWE-KEY-WRAP"),
      },
      hkdfMasterKey,
      { name: "AES-GCM", length: 256 },
      false,
      ["wrapKey", "unwrapKey"]
    );

    // 4. Reconstruct the wrapped key buffer (ciphertext + tag)
    const iv = new Uint8Array(base64UrlDecode(ivB64));
    const ciphertextBytes = new Uint8Array(base64UrlDecode(ciphertextB64));
    const tagBytes = new Uint8Array(base64UrlDecode(tagB64));

    const wrappedBuffer = new Uint8Array(ciphertextBytes.byteLength + tagBytes.byteLength);
    wrappedBuffer.set(ciphertextBytes, 0);
    wrappedBuffer.set(tagBytes, ciphertextBytes.byteLength);

    // 5. Unwrap the Vault Key
    return await self.crypto.subtle.unwrapKey(
      "raw",
      wrappedBuffer.buffer as ArrayBuffer,
      kwk,
      {
        name: "AES-GCM",
        iv: iv,
        tagLength: 128,
      },
      { name: "AES-GCM" },
      true,
      ["encrypt", "decrypt"]
    );
  }
}
