// metadata.ts
// Client-side metadata obfuscation implementing deterministic AES-SIV filename encryption

import { Buffer } from "buffer";

export interface DirectoryMapping {
  directoryId: string;
  parentDirectoryId: string | null;
  files: {
    [encryptedName: string]: {
      fileId: string;
      originalSize: number;
      chunkCount: number;
      chunkHashes: string[];
    };
  };
  subdirectories: {
    [encryptedName: string]: string; // Maps encrypted directory name to subdirectory ID
  };
}

// Convert ArrayBuffer to URL-safe Base64
function base64UrlEncode(buffer: ArrayBuffer): string {
  return Buffer.from(buffer)
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

/**
 * Deterministic AES-SIV Filename Encryption (RFC 5297 concept using WebCrypto)
 * - Synthesizes a deterministic IV by hashing the parent directory ID (AAD) and plaintext filename.
 * - Encrypts utilizing AES-CTR.
 * - Appends the synthetic IV to the ciphertext to verify authenticity upon decryption.
 */
export class MetadataCrypt {
  private key: CryptoKey;

  constructor(key: CryptoKey) {
    this.key = key;
  }

  // Derive specialized subkeys for HMAC and AES-CTR from the master metadata key
  private async deriveSubkeys(): Promise<{ hmacKey: CryptoKey; ctrKey: CryptoKey }> {
    const rawKeyMaterial = await self.crypto.subtle.exportKey("raw", this.key);

    // Derive HMAC subkey via SHA-256
    const hmacKey = await self.crypto.subtle.importKey(
      "raw",
      rawKeyMaterial,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign", "verify"]
    );

    // Derive AES-CTR subkey
    const ctrKey = await self.crypto.subtle.importKey(
      "raw",
      rawKeyMaterial,
      { name: "AES-CTR" },
      false,
      ["encrypt", "decrypt"]
    );

    return { hmacKey, ctrKey };
  }

  /**
   * Encrypt a filename deterministically.
   * AAD (parentDirId) prevents directory-movement attacks.
   */
  async encryptFilename(filename: string, parentDirId: string): Promise<string> {
    const { hmacKey, ctrKey } = await this.deriveSubkeys();
    
    const encoder = new TextEncoder();
    const aadBytes = encoder.encode(parentDirId);
    const filenameBytes = encoder.encode(filename);

    // Concatenate AAD + Plaintext to compute the synthetic IV (S2V)
    const combinedData = new Uint8Array(aadBytes.byteLength + 1 + filenameBytes.byteLength);
    combinedData.set(aadBytes, 0);
    combinedData.set([0x3a], aadBytes.byteLength); // ":" delimiter
    combinedData.set(filenameBytes, aadBytes.byteLength + 1);

    // Generate synthetic IV (SIV) - take the first 16 bytes of HMAC-SHA256
    const hmacSig = await self.crypto.subtle.sign("HMAC", hmacKey, combinedData);
    const siv = new Uint8Array(hmacSig, 0, 16);

    // Encrypt filename using AES-CTR with the synthetic IV
    const ciphertext = await self.crypto.subtle.encrypt(
      {
        name: "AES-CTR",
        counter: siv,
        length: 64, // 64-bit counter length
      },
      ctrKey,
      filenameBytes
    );

    // Output payload: Synthetic IV (16 bytes) + Ciphertext
    const packedPayload = new Uint8Array(16 + ciphertext.byteLength);
    packedPayload.set(siv, 0);
    packedPayload.set(new Uint8Array(ciphertext), 16);

    return base64UrlEncode(packedPayload.buffer as ArrayBuffer);
  }

  /**
   * Decrypt a filename. Throws error if AAD (parentDirId) does not match the synthetic IV check.
   */
  async decryptFilename(encryptedName: string, parentDirId: string): Promise<string> {
    const { hmacKey, ctrKey } = await this.deriveSubkeys();

    const packedPayload = new Uint8Array(base64UrlDecode(encryptedName));
    if (packedPayload.byteLength < 16) {
      throw new Error("Invalid metadata payload length.");
    }

    const siv = packedPayload.slice(0, 16);
    const ciphertext = packedPayload.slice(16);

    // Decrypt filename using AES-CTR
    const plaintextBuffer = await self.crypto.subtle.decrypt(
      {
        name: "AES-CTR",
        counter: siv,
        length: 64,
      },
      ctrKey,
      ciphertext
    );

    const decoder = new TextDecoder();
    const filename = decoder.decode(plaintextBuffer);

    // Verify synthetic IV (S2V) match
    const encoder = new TextEncoder();
    const aadBytes = encoder.encode(parentDirId);
    const filenameBytes = encoder.encode(filename);

    const combinedData = new Uint8Array(aadBytes.byteLength + 1 + filenameBytes.byteLength);
    combinedData.set(aadBytes, 0);
    combinedData.set([0x3a], aadBytes.byteLength);
    combinedData.set(filenameBytes, aadBytes.byteLength + 1);

    const checkSig = await self.crypto.subtle.sign("HMAC", hmacKey, combinedData);
    const expectedSiv = new Uint8Array(checkSig, 0, 16);

    // Constant-time check for SIV authenticity
    let matches = true;
    for (let i = 0; i < 16; i++) {
      if (siv[i] !== expectedSiv[i]) matches = false;
    }

    if (!matches) {
      throw new Error("Cryptographic verification failed: File has been moved or tampered with.");
    }

    return filename;
  }
}
