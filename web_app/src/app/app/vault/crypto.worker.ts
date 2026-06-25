// crypto.worker.ts
// Background Web Worker implementing the W3C WebCrypto API and Scrypt KEK derivation for chunked AES-256-GCM operations

import { scrypt } from "scrypt-js";

export interface CryptoWorkerMessage {
  type: "DERIVE_KEY" | "ENCRYPT_CHUNK" | "DECRYPT_CHUNK" | "RESET";
  payload: {
    data?: ArrayBuffer; // Used for chunk data
    passphrase?: string; // Used for key derivation
    salt?: Uint8Array; // Used for key derivation (16 bytes)
    iv?: Uint8Array; // Required for decryption chunk
  };
}

export interface CryptoWorkerResponse {
  type: "KEY_DERIVED_SUCCESS" | "ENCRYPT_CHUNK_SUCCESS" | "DECRYPT_CHUNK_SUCCESS" | "ERROR" | "RESET_SUCCESS";
  payload: {
    data?: ArrayBuffer;
    iv?: Uint8Array;
    error?: string;
  };
}

interface WorkerContext {
  postMessage(message: CryptoWorkerResponse, transfer: Transferable[]): void;
  postMessage(message: CryptoWorkerResponse): void;
}

const ctx = self as unknown as WorkerContext;

// Cached active CryptoKey for the current session
let cachedKey: CryptoKey | null = null;

// Derive AES-256 CryptoKey using Scrypt client-side
async function deriveScryptKey(passphrase: string, salt: Uint8Array): Promise<CryptoKey> {
  const encoder = new TextEncoder();
  const passwordBytes = encoder.encode(passphrase);

  // Scrypt parameters: N=16384 (CPU/memory cost), r=8 (block size), p=1 (parallelization), dkLen=32 (256-bit key)
  const derivedKeyBytes = await scrypt(passwordBytes, salt, 16384, 8, 1, 32);

  return await self.crypto.subtle.importKey(
    "raw",
    derivedKeyBytes as unknown as BufferSource,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"]
  );
}

self.onmessage = async (event: MessageEvent<CryptoWorkerMessage>) => {
  const { type, payload } = event.data;

  try {
    if (type === "DERIVE_KEY") {
      if (!payload.passphrase || !payload.salt) {
        throw new Error("Passphrase and salt are required for key derivation.");
      }
      cachedKey = await deriveScryptKey(payload.passphrase, payload.salt);
      ctx.postMessage({ type: "KEY_DERIVED_SUCCESS", payload: {} });

    } else if (type === "ENCRYPT_CHUNK") {
      if (!cachedKey) {
        throw new Error("Encryption key has not been derived. Perform DERIVE_KEY first.");
      }
      if (!payload.data) {
        throw new Error("Chunk data buffer is missing.");
      }

      // Generate a unique random 12-byte IV for this specific 32 KiB chunk
      const iv = self.crypto.getRandomValues(new Uint8Array(12));

      const ciphertext = await self.crypto.subtle.encrypt(
        {
          name: "AES-GCM",
          iv: iv,
        },
        cachedKey,
        payload.data
      );

      const response: CryptoWorkerResponse = {
        type: "ENCRYPT_CHUNK_SUCCESS",
        payload: {
          data: ciphertext,
          iv: iv,
        },
      };

      // Post back ciphertext chunk utilizing Transferable Objects to maintain flat memory
      ctx.postMessage(response, [ciphertext]);

    } else if (type === "DECRYPT_CHUNK") {
      if (!cachedKey) {
        throw new Error("Decryption key has not been derived. Perform DERIVE_KEY first.");
      }
      if (!payload.data || !payload.iv) {
        throw new Error("Ciphertext chunk data or IV is missing.");
      }

      const plaintext = await self.crypto.subtle.decrypt(
        {
          name: "AES-GCM",
          iv: payload.iv as unknown as BufferSource,
        },
        cachedKey,
        payload.data
      );

      const response: CryptoWorkerResponse = {
        type: "DECRYPT_CHUNK_SUCCESS",
        payload: {
          data: plaintext,
        },
      };

      // Post back plaintext chunk utilizing Transferable Objects
      ctx.postMessage(response, [plaintext]);

    } else if (type === "RESET") {
      cachedKey = null;
      ctx.postMessage({ type: "RESET_SUCCESS", payload: {} });
    }
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    ctx.postMessage({
      type: "ERROR",
      payload: {
        error: errorMsg,
      },
    });
  }
};
