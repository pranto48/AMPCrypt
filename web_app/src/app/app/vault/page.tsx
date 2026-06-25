"use client";

import React, { useState, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import Navbar from "@/components/Navbar";
import { Lock, Unlock, FileUp, Shield, Cpu, RefreshCw, CheckCircle, AlertTriangle, Key, Download } from "lucide-react";
import { CryptoWorkerResponse } from "./crypto.worker";

const CHUNK_SIZE = 32 * 1024; // 32 KiB chunking
const MAGIC_SIGNATURE = "AMPCRYPT";

export default function VaultPage() {
  const [passphrase, setPassphrase] = useState("");
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [isDragOver, setIsDragOver] = useState(false);
  const [status, setStatus] = useState<"IDLE" | "PROCESSING" | "SUCCESS" | "ERROR">("IDLE");
  const [statusMessage, setStatusMessage] = useState("");
  const [progress, setProgress] = useState(0);
  const [processingTime, setProcessingTime] = useState<number | null>(null);

  // Downloadable results
  const [downloadUrl, setDownloadUrl] = useState<string | null>(null);
  const [downloadName, setDownloadName] = useState("");

  const workerRef = useRef<Worker | null>(null);
  const workerResolveRef = useRef<((value: CryptoWorkerResponse) => void) | null>(null);
  const startTimeRef = useRef<number | null>(null);

  // Initialize Web Worker
  useEffect(() => {
    workerRef.current = new Worker(new URL("./crypto.worker.ts", import.meta.url));

    workerRef.current.onmessage = (event: MessageEvent<CryptoWorkerResponse>) => {
      if (workerResolveRef.current) {
        workerResolveRef.current(event.data);
      }
    };

    return () => {
      workerRef.current?.terminate();
    };
  }, []);

  // Promisified message exchange with Worker
  const sendWorkerMessage = (type: string, payload: unknown, transfer: Transferable[] = []): Promise<CryptoWorkerResponse> => {
    return new Promise((resolve) => {
      workerResolveRef.current = resolve;
      workerRef.current?.postMessage({ type, payload }, transfer);
    });
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(true);
  };

  const handleDragLeave = () => {
    setIsDragOver(false);
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(false);
    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      setupFile(e.dataTransfer.files[0]);
    }
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      setupFile(e.target.files[0]);
    }
  };

  const setupFile = (file: File) => {
    setSelectedFile(file);
    setStatus("IDLE");
    setProgress(0);
    setProcessingTime(null);
    setDownloadUrl(null);
  };

  // Helper to read file slice as ArrayBuffer
  const readSlice = (file: Blob, start: number, end: number): Promise<ArrayBuffer> => {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result as ArrayBuffer);
      reader.onerror = () => reject(reader.error);
      reader.readAsArrayBuffer(file.slice(start, end));
    });
  };

  // 1. Chunked Encryption Flow
  const handleEncrypt = async () => {
    if (!selectedFile || !passphrase) return;

    setStatus("PROCESSING");
    setProgress(0);
    setDownloadUrl(null);
    startTimeRef.current = performance.now();

    try {
      // Step A: Derive key using Scrypt
      setStatusMessage("Deriving Key using Scrypt (N=16384)...");
      const salt = window.crypto.getRandomValues(new Uint8Array(16));
      
      const deriveRes = await sendWorkerMessage("DERIVE_KEY", {
        passphrase,
        salt,
      });

      if (deriveRes.type === "ERROR") {
        throw new Error(deriveRes.payload.error || "Failed to derive key.");
      }

      // Step B: Slice and encrypt in 32 KiB chunks
      const totalSize = selectedFile.size;
      let offset = 0;
      const encryptedChunks: Blob[] = [];

      // Create file header: Signature (8 bytes) + Salt (16 bytes) + Original Name
      const encoder = new TextEncoder();
      const nameBytes = encoder.encode(selectedFile.name);
      const headerBuffer = new ArrayBuffer(8 + 16 + 4 + nameBytes.byteLength);
      
      // Write Magic Bytes
      const sigView = new Uint8Array(headerBuffer, 0, 8);
      sigView.set(encoder.encode(MAGIC_SIGNATURE));

      // Write Salt
      const saltView = new Uint8Array(headerBuffer, 8, 16);
      saltView.set(salt);

      // Write Name Length
      const lengthView = new DataView(headerBuffer, 24, 4);
      lengthView.setUint32(0, nameBytes.byteLength, false);

      // Write Name
      const nameView = new Uint8Array(headerBuffer, 28, nameBytes.byteLength);
      nameView.set(nameBytes);

      encryptedChunks.push(new Blob([headerBuffer]));

      while (offset < totalSize) {
        const currentChunkSize = Math.min(CHUNK_SIZE, totalSize - offset);
        setStatusMessage(`Encrypting chunk at offset ${offset} of ${totalSize} bytes...`);

        // Read 32 KiB slice
        const chunkBuffer = await readSlice(selectedFile, offset, offset + currentChunkSize);

        // Encrypt chunk in worker
        const encryptRes = await sendWorkerMessage(
          "ENCRYPT_CHUNK",
          { data: chunkBuffer },
          [chunkBuffer] // Transfer chunk buffer
        );

        if (encryptRes.type === "ERROR" || !encryptRes.payload.data || !encryptRes.payload.iv) {
          throw new Error(encryptRes.payload.error || "Encryption failed.");
        }

        // Each encrypted chunk is packed as: 12-byte IV + ciphertext (data + 16-byte auth tag)
        const packedChunk = new Blob([encryptRes.payload.iv as unknown as BlobPart, encryptRes.payload.data as unknown as BlobPart]);
        encryptedChunks.push(packedChunk);

        offset += currentChunkSize;
        setProgress(Math.round((offset / totalSize) * 100));
      }

      // Step C: Compile final file Blob
      const encryptedBlob = new Blob(encryptedChunks, { type: "application/octet-stream" });
      const url = URL.createObjectURL(encryptedBlob);
      
      setDownloadUrl(url);
      setDownloadName(`${selectedFile.name}.amp`);
      setProcessingTime(performance.now() - startTimeRef.current);
      setStatus("SUCCESS");
      setStatusMessage("Vault compiled successfully! Your encrypted file (.amp) is ready.");

    } catch (err: unknown) {
      setStatus("ERROR");
      const errorMsg = err instanceof Error ? err.message : String(err);
      setStatusMessage(errorMsg);
    } finally {
      // Clear key cache from worker
      await sendWorkerMessage("RESET", {});
    }
  };

  // 2. Chunked Decryption Flow
  const handleDecrypt = async () => {
    if (!selectedFile || !passphrase) return;

    setStatus("PROCESSING");
    setProgress(0);
    setDownloadUrl(null);
    startTimeRef.current = performance.now();

    try {
      setStatusMessage("Parsing file header...");
      const fileBuffer = await readSlice(selectedFile, 0, selectedFile.size);

      // Read Magic Bytes (8 bytes)
      const sigView = new Uint8Array(fileBuffer, 0, 8);
      const decoder = new TextDecoder();
      const sig = decoder.decode(sigView);

      if (sig !== MAGIC_SIGNATURE) {
        throw new Error("Invalid file type: Missing AMPCRYPT cryptographic header.");
      }

      // Read Salt (16 bytes)
      const salt = new Uint8Array(fileBuffer, 8, 16);

      // Read Name Length (4 bytes)
      const lengthView = new DataView(fileBuffer, 24, 4);
      const nameLength = lengthView.getUint32(0, false);

      // Read Original File Name
      const nameView = new Uint8Array(fileBuffer, 28, nameLength);
      const originalName = decoder.decode(nameView);

      // Step A: Derive key in worker using extracted Salt
      setStatusMessage("Deriving key using Scrypt...");
      const deriveRes = await sendWorkerMessage("DERIVE_KEY", {
        passphrase,
        salt,
      });

      if (deriveRes.type === "ERROR") {
        throw new Error(deriveRes.payload.error || "Failed to derive key.");
      }

      // Step B: Iterate and decrypt remaining chunks
      let offset = 8 + 16 + 4 + nameLength;
      const decryptedChunks: ArrayBuffer[] = [];
      const totalSize = selectedFile.size;

      // Note: Each encrypted chunk format is: IV (12 bytes) + Ciphertext (original size + 16-byte auth tag)
      // Since original chunk size is 32 KiB, encrypted chunk size is 12 + (32 * 1024) + 16 = 32800 bytes
      const ENCRYPTED_CHUNK_SIZE = 12 + CHUNK_SIZE + 16;

      while (offset < totalSize) {
        const remainingBytes = totalSize - offset;
        // The last chunk might be smaller than 32800 bytes
        const currentChunkSize = Math.min(ENCRYPTED_CHUNK_SIZE, remainingBytes);
        setStatusMessage(`Decrypting chunk at offset ${offset}...`);

        // Slice chunk components: 12-byte IV + ciphertext payload
        const rawChunkBuffer = fileBuffer.slice(offset, offset + currentChunkSize);
        const iv = new Uint8Array(rawChunkBuffer, 0, 12);
        const ciphertext = rawChunkBuffer.slice(12);

        // Decrypt in worker
        const decryptRes = await sendWorkerMessage(
          "DECRYPT_CHUNK",
          {
            data: ciphertext,
            iv,
          },
          [ciphertext] // Transfer ciphertext buffer
        );

        if (decryptRes.type === "ERROR" || !decryptRes.payload.data) {
          throw new Error(decryptRes.payload.error || "Decryption failed. Check passphrase.");
        }

        decryptedChunks.push(decryptRes.payload.data);
        offset += currentChunkSize;
        setProgress(Math.round((offset / totalSize) * 100));
      }

      // Step C: Compile final decrypted file
      const decryptedBlob = new Blob(decryptedChunks);
      const url = URL.createObjectURL(decryptedBlob);

      setDownloadUrl(url);
      setDownloadName(originalName);
      setProcessingTime(performance.now() - startTimeRef.current);
      setStatus("SUCCESS");
      setStatusMessage("Vault decrypted successfully! Original file recovered.");

    } catch (err: unknown) {
      setStatus("ERROR");
      const errorMsg = err instanceof Error ? err.message : String(err);
      setStatusMessage(errorMsg);
    } finally {
      await sendWorkerMessage("RESET", {});
    }
  };

  return (
    <div className="bg-[#0A0A0A] text-white min-h-screen relative font-sans">
      <Navbar />

      <main className="max-w-4xl mx-auto px-4 pt-32 pb-16 relative z-10">
        {/* Ambient Top Glow */}
        <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[500px] h-[300px] bg-[#00E5FF]/10 rounded-full filter blur-[100px] pointer-events-none" />

        <div className="text-center space-y-4 mb-12">
          <h1 className="text-4xl font-extrabold tracking-tight">
            Cryptographic <span className="text-[#00E5FF]">Client Vault</span>
          </h1>
          <p className="text-gray-400 max-w-xl mx-auto text-sm font-mono">
            Zero-knowledge client-side encryption. Keys and data never leave the browser. Heavy operations execute offscreen using Scrypt and 32 KiB chunked AES-GCM.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
          {/* Key and File Configuration Panel */}
          <div className="bg-[#0E0E0E]/80 border border-white/5 rounded-2xl p-6 space-y-6 shadow-xl backdrop-blur-md">
            <h2 className="text-lg font-bold flex items-center gap-2 border-b border-white/5 pb-3">
              <Key className="w-5 h-5 text-[#00E5FF]" /> Configuration
            </h2>

            <div className="space-y-2">
              <label className="text-xs font-semibold text-gray-500 uppercase tracking-wider font-mono">
                Vault Passphrase
              </label>
              <input
                type="password"
                placeholder="Enter strong encryption key"
                value={passphrase}
                onChange={(e) => setPassphrase(e.target.value)}
                className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-3 text-sm focus:outline-none focus:border-[#00E5FF] transition-colors"
              />
            </div>

            {/* Interactive Drag & Drop Area */}
            <div className="space-y-2">
              <label className="text-xs font-semibold text-gray-500 uppercase tracking-wider font-mono">
                Select File to Secure
              </label>
              
              <div
                onDragOver={handleDragOver}
                onDragLeave={handleDragLeave}
                onDrop={handleDrop}
                className={`border border-dashed rounded-xl p-8 text-center transition-all relative group cursor-pointer ${
                  isDragOver
                    ? "border-[#00E5FF] bg-[#00E5FF]/5 shadow-[0_0_15px_rgba(0,229,255,0.1)]"
                    : "border-white/10 hover:border-[#00E5FF]/40 hover:bg-white/[0.02]"
                }`}
              >
                <input
                  type="file"
                  onChange={handleFileChange}
                  className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                />
                
                <motion.div
                  animate={{ scale: isDragOver ? 1.1 : 1 }}
                  transition={{ type: "spring", stiffness: 300, damping: 20 }}
                >
                  <FileUp className={`w-10 h-10 mx-auto mb-3 transition-colors ${
                    isDragOver ? "text-[#00E5FF]" : "text-gray-500 group-hover:text-[#00E5FF]"
                  }`} />
                </motion.div>
                
                <span className="text-sm font-medium text-gray-300 block">
                  {selectedFile ? selectedFile.name : "Drag & drop file or click to browse"}
                </span>
                
                {selectedFile && (
                  <span className="text-xs text-gray-500 font-mono block mt-1">
                    {(selectedFile.size / 1024).toFixed(2)} KB
                  </span>
                )}
              </div>
            </div>

            {/* Action buttons */}
            <div className="grid grid-cols-2 gap-4">
              <button
                onClick={handleEncrypt}
                disabled={!selectedFile || !passphrase || status === "PROCESSING"}
                className="py-3.5 bg-[#00E5FF] text-black font-bold rounded-xl shadow-lg shadow-cyan-500/10 hover:shadow-cyan-500/20 hover:bg-[#00E5FF]/90 active:scale-[0.98] disabled:opacity-40 disabled:pointer-events-none transition-all flex items-center justify-center gap-2"
              >
                <Lock className="w-4 h-4" /> Encrypt (.amp)
              </button>

              <button
                onClick={handleDecrypt}
                disabled={!selectedFile || !passphrase || status === "PROCESSING"}
                className="py-3.5 bg-white/5 border border-white/10 text-white font-bold rounded-xl hover:bg-white/10 active:scale-[0.98] disabled:opacity-40 disabled:pointer-events-none transition-all flex items-center justify-center gap-2"
              >
                <Unlock className="w-4 h-4 text-[#00E5FF]" /> Decrypt
              </button>
            </div>
          </div>

          {/* Cryptographic Execution Console */}
          <div className="bg-[#0E0E0E]/80 border border-white/5 rounded-2xl p-6 space-y-6 shadow-xl backdrop-blur-md flex flex-col">
            <h2 className="text-lg font-bold flex items-center gap-2 border-b border-white/5 pb-3">
              <Cpu className="w-5 h-5 text-[#00E5FF]" /> Worker Console
            </h2>

            <div className="flex-grow flex flex-col justify-center items-center p-6 bg-[#141414] rounded-xl border border-white/5 min-h-[220px]">
              {status === "IDLE" && (
                <div className="text-center space-y-2">
                  <Shield className="w-12 h-12 text-gray-600 mx-auto" />
                  <p className="text-sm text-gray-400">Awaiting configuration parameters...</p>
                </div>
              )}

              {status === "PROCESSING" && (
                <div className="w-full text-center space-y-4">
                  <RefreshCw className="w-8 h-8 text-[#00E5FF] animate-spin mx-auto" />
                  <p className="text-sm font-semibold">{statusMessage}</p>
                  
                  {/* Progressive progress bar */}
                  <div className="w-full bg-white/5 rounded-full h-1.5 overflow-hidden">
                    <motion.div
                      initial={{ width: 0 }}
                      animate={{ width: `${progress}%` }}
                      transition={{ duration: 0.1 }}
                      className="bg-[#00E5FF] h-full"
                    />
                  </div>
                  <span className="text-xs font-mono text-[#00E5FF]">{progress}% Completed</span>
                </div>
              )}

              {status === "SUCCESS" && (
                <div className="text-center space-y-4">
                  <CheckCircle className="w-12 h-12 text-emerald-500 mx-auto animate-bounce" />
                  <p className="text-sm font-semibold text-emerald-400">{statusMessage}</p>
                  
                  {processingTime !== null && (
                    <div className="inline-block px-3 py-1 bg-emerald-500/10 border border-emerald-500/20 rounded-full text-xs font-mono text-emerald-400">
                      Elapsed Time: {processingTime.toFixed(2)} ms
                    </div>
                  )}
                </div>
              )}

              {status === "ERROR" && (
                <div className="text-center space-y-2">
                  <AlertTriangle className="w-12 h-12 text-rose-500 mx-auto" />
                  <p className="text-sm font-semibold text-rose-400">{statusMessage}</p>
                </div>
              )}
            </div>

            {/* Download Link Section */}
            <AnimatePresence>
              {downloadUrl && status === "SUCCESS" && (
                <motion.div
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: 10 }}
                  className="space-y-3 border-t border-white/5 pt-4"
                >
                  <a
                    href={downloadUrl}
                    download={downloadName}
                    className="w-full py-3 bg-[#00E5FF] text-black font-bold rounded-xl shadow-lg shadow-cyan-500/10 hover:shadow-cyan-500/20 hover:bg-[#00E5FF]/90 active:scale-[0.98] transition-all flex items-center justify-center gap-2 text-center text-sm"
                  >
                    <Download className="w-4 h-4" /> Download Result File
                  </a>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </div>
      </main>
    </div>
  );
}
