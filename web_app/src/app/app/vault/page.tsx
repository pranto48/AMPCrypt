"use client";

import React, { useState, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import Navbar from "@/components/Navbar";
import {
  Lock,
  Unlock,
  FileUp,
  Shield,
  Cpu,
  RefreshCw,
  CheckCircle,
  AlertTriangle,
  Key,
  Download,
  Split,
  Users,
  Clipboard,
  Mail,
  FileText
} from "lucide-react";
import { CryptoWorkerResponse } from "./crypto.worker";
import { splitSecret, recombineShares } from "@/lib/shamir";

const CHUNK_SIZE = 32 * 1024; // 32 KiB chunking
const MAGIC_SIGNATURE = "AMPCRYPT";

interface RecoveryConfig {
  questions_recovery_enabled: boolean;
  questions_recovery_email: string;
  questions_recovery_questions: string[];
  questions_recovery_salt: string;
  questions_recovery_iv: string;
  questions_recovery_encrypted_master_key: string;
}

type ActiveTab = "crypto" | "sss" | "recovery";

export default function VaultPage() {
  const [activeTab, setActiveTab] = useState<ActiveTab>("crypto");

  // ─── SYMMETRIC CRYPTO STATE ──────────────────────────────────────────────────
  const [passphrase, setPassphrase] = useState("");
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [isDragOver, setIsDragOver] = useState(false);
  const [status, setStatus] = useState<"IDLE" | "PROCESSING" | "SUCCESS" | "ERROR">("IDLE");
  const [statusMessage, setStatusMessage] = useState("");
  const [progress, setProgress] = useState(0);
  const [processingTime, setProcessingTime] = useState<number | null>(null);
  const [downloadUrl, setDownloadUrl] = useState<string | null>(null);
  const [downloadName, setDownloadName] = useState("");

  // ─── SSS STATE ───────────────────────────────────────────────────────────────
  const [sssPassphrase, setSssPassphrase] = useState("");
  const [sssN, setSssN] = useState(3);
  const [sssT, setSssT] = useState(2);
  const [sssShares, setSssShares] = useState<string[]>([]);
  const [sssRawSharesInput, setSssRawSharesInput] = useState("");
  const [sssCombinedResult, setSssCombinedResult] = useState("");
  const [sssCombineError, setSssCombineError] = useState("");
  const [copiedShareIndex, setCopiedShareIndex] = useState<number | null>(null);

  // ─── RECOVERY STATE ──────────────────────────────────────────────────────────
  // Configurator (Create backup)
  const [recMasterKey, setRecMasterKey] = useState("");
  const [recEmail, setRecEmail] = useState("");
  const recQ1 = "What was the name of your first pet?";
  const recQ2 = "What city were you born in?";
  const recQ3 = "What was your childhood nickname?";
  const [recA1, setRecA1] = useState("");
  const [recA2, setRecA2] = useState("");
  const [recA3, setRecA3] = useState("");
  const [recConfigDownloadUrl, setRecConfigDownloadUrl] = useState<string | null>(null);

  // Reconstructor (Restore backup)
  const [recUploadDragOver, setRecUploadDragOver] = useState(false);
  const [recLoadedConfig, setRecLoadedConfig] = useState<RecoveryConfig | null>(null);
  const [recInputEmail, setRecInputEmail] = useState("");
  const [recInputA1, setRecInputA1] = useState("");
  const [recInputA2, setRecInputA2] = useState("");
  const [recInputA3, setRecInputA3] = useState("");
  const [recOtpSent, setRecOtpSent] = useState(false);
  const [recInputOtp, setRecInputOtp] = useState("");
  const [recGeneratedOtp, setRecGeneratedOtp] = useState("");
  const [recStatus, setRecStatus] = useState<"IDLE" | "PROCESSING" | "SUCCESS" | "ERROR">("IDLE");
  const [recStatusMessage, setRecStatusMessage] = useState("");
  const [recoveredMasterKey, setRecoveredMasterKey] = useState<string | null>(null);

  // Web Worker Ref
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
      setStatusMessage("Deriving Key using Scrypt (N=16384)...");
      const salt = window.crypto.getRandomValues(new Uint8Array(16));
      
      const deriveRes = await sendWorkerMessage("DERIVE_KEY", {
        passphrase,
        salt,
      });

      if (deriveRes.type === "ERROR") {
        throw new Error(deriveRes.payload.error || "Failed to derive key.");
      }

      const totalSize = selectedFile.size;
      let offset = 0;
      const encryptedChunks: Blob[] = [];

      const encoder = new TextEncoder();
      const nameBytes = encoder.encode(selectedFile.name);
      const headerBuffer = new ArrayBuffer(8 + 16 + 4 + nameBytes.byteLength);
      
      const sigView = new Uint8Array(headerBuffer, 0, 8);
      sigView.set(encoder.encode(MAGIC_SIGNATURE));

      const saltView = new Uint8Array(headerBuffer, 8, 16);
      saltView.set(salt);

      const lengthView = new DataView(headerBuffer, 24, 4);
      lengthView.setUint32(0, nameBytes.byteLength, false);

      const nameView = new Uint8Array(headerBuffer, 28, nameBytes.byteLength);
      nameView.set(nameBytes);

      encryptedChunks.push(new Blob([headerBuffer]));

      while (offset < totalSize) {
        const currentChunkSize = Math.min(CHUNK_SIZE, totalSize - offset);
        setStatusMessage(`Encrypting chunk at offset ${offset} of ${totalSize} bytes...`);

        const chunkBuffer = await readSlice(selectedFile, offset, offset + currentChunkSize);

        const encryptRes = await sendWorkerMessage(
          "ENCRYPT_CHUNK",
          { data: chunkBuffer },
          [chunkBuffer]
        );

        if (encryptRes.type === "ERROR" || !encryptRes.payload.data || !encryptRes.payload.iv) {
          throw new Error(encryptRes.payload.error || "Encryption failed.");
        }

        const packedChunk = new Blob([encryptRes.payload.iv as unknown as BlobPart, encryptRes.payload.data as unknown as BlobPart]);
        encryptedChunks.push(packedChunk);

        offset += currentChunkSize;
        setProgress(Math.round((offset / totalSize) * 100));
      }

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

      const sigView = new Uint8Array(fileBuffer, 0, 8);
      const decoder = new TextDecoder();
      const sig = decoder.decode(sigView);

      if (sig !== MAGIC_SIGNATURE) {
        throw new Error("Invalid file type: Missing AMPCRYPT cryptographic header.");
      }

      const salt = new Uint8Array(fileBuffer, 8, 16);

      const lengthView = new DataView(fileBuffer, 24, 4);
      const nameLength = lengthView.getUint32(0, false);

      const nameView = new Uint8Array(fileBuffer, 28, nameLength);
      const originalName = decoder.decode(nameView);

      setStatusMessage("Deriving key using Scrypt...");
      const deriveRes = await sendWorkerMessage("DERIVE_KEY", {
        passphrase,
        salt,
      });

      if (deriveRes.type === "ERROR") {
        throw new Error(deriveRes.payload.error || "Failed to derive key.");
      }

      let offset = 8 + 16 + 4 + nameLength;
      const decryptedChunks: ArrayBuffer[] = [];
      const totalSize = selectedFile.size;

      const ENCRYPTED_CHUNK_SIZE = 12 + CHUNK_SIZE + 16;

      while (offset < totalSize) {
        const remainingBytes = totalSize - offset;
        const currentChunkSize = Math.min(ENCRYPTED_CHUNK_SIZE, remainingBytes);
        setStatusMessage(`Decrypting chunk at offset ${offset}...`);

        const rawChunkBuffer = fileBuffer.slice(offset, offset + currentChunkSize);
        const iv = new Uint8Array(rawChunkBuffer, 0, 12);
        const ciphertext = rawChunkBuffer.slice(12);

        const decryptRes = await sendWorkerMessage(
          "DECRYPT_CHUNK",
          {
            data: ciphertext,
            iv,
          },
          [ciphertext]
        );

        if (decryptRes.type === "ERROR" || !decryptRes.payload.data) {
          throw new Error(decryptRes.payload.error || "Decryption failed. Check passphrase.");
        }

        decryptedChunks.push(decryptRes.payload.data);
        offset += currentChunkSize;
        setProgress(Math.round((offset / totalSize) * 100));
      }

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

  // ─── SSS ACTIONS ─────────────────────────────────────────────────────────────
  const handleSssSplit = () => {
    if (!sssPassphrase) return;
    try {
      const generated = splitSecret(sssPassphrase, sssN, sssT);
      setSssShares(generated);
    } catch {
      // Ignore error
    }
  };

  const handleSssRecombine = () => {
    setSssCombineError("");
    setSssCombinedResult("");
    const parsed = sssRawSharesInput
      .split(/[\n,]+/)
      .map(s => s.trim())
      .filter(s => s.length > 0);

    if (parsed.length < 2) {
      setSssCombineError("Please enter at least 2 shares to combine.");
      return;
    }

    try {
      const recovered = recombineShares(parsed);
      setSssCombinedResult(recovered);
    } catch (e: unknown) {
      const errMsg = e instanceof Error ? e.message : "Failed to combine shares. Ensure hex shares are copied accurately.";
      setSssCombineError(errMsg);
    }
  };

  const copyShareToClipboard = (share: string, idx: number) => {
    navigator.clipboard.writeText(share);
    setCopiedShareIndex(idx);
    setTimeout(() => setCopiedShareIndex(null), 2000);
  };

  // ─── RECOVERY ACTIONS ─────────────────────────────────────────────────────────
  const handleGenerateRecoveryConfig = async () => {
    if (!recMasterKey || !recEmail || !recA1 || !recA2 || !recA3) return;

    setRecStatus("PROCESSING");
    setRecStatusMessage("Generating recovery configuration metadata...");

    try {
      const salt = window.crypto.getRandomValues(new Uint8Array(16));
      const combinedAnswers = [recA1, recA2, recA3].map(a => a.trim().toLowerCase()).join("_");

      const encoder = new TextEncoder();
      const masterKeyBytes = encoder.encode(recMasterKey);

      // Perform encryption inside worker
      const encryptRes = await sendWorkerMessage("ENCRYPT_RECOVERY", {
        passphrase: combinedAnswers,
        salt,
        data: masterKeyBytes,
      });

      if (encryptRes.type === "ERROR" || !encryptRes.payload.data || !encryptRes.payload.iv) {
        throw new Error(encryptRes.payload.error || "Recovery encryption failed.");
      }

      // Convert typed array properties to base64 using helper function
      const uint8ArrayToBase64 = (arr: Uint8Array): string => {
        let binary = "";
        const len = arr.byteLength;
        for (let i = 0; i < len; i++) {
          binary += String.fromCharCode(arr[i]);
        }
        return window.btoa(binary);
      };

      const saltBase64 = uint8ArrayToBase64(salt);
      const ivBase64 = uint8ArrayToBase64(new Uint8Array(encryptRes.payload.iv));
      const encryptedMasterKeyBase64 = uint8ArrayToBase64(new Uint8Array(encryptRes.payload.data));

      const configObj = {
        questions_recovery_enabled: true,
        questions_recovery_email: recEmail,
        questions_recovery_questions: [recQ1, recQ2, recQ3],
        questions_recovery_salt: saltBase64,
        questions_recovery_iv: ivBase64,
        questions_recovery_encrypted_master_key: encryptedMasterKeyBase64,
      };

      const configStr = JSON.stringify(configObj, null, 2);
      const blob = new Blob([configStr], { type: "application/json" });
      const url = URL.createObjectURL(blob);

      setRecConfigDownloadUrl(url);
      setRecStatus("SUCCESS");
      setRecStatusMessage("Recovery backup config file successfully compiled!");
    } catch (e: unknown) {
      setRecStatus("ERROR");
      const errMsg = e instanceof Error ? e.message : "Failed to generate recovery config.";
      setRecStatusMessage(errMsg);
    }
  };

  const handleConfigJsonUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      parseConfigJson(e.target.files[0]);
    }
  };

  const parseConfigJson = (file: File) => {
    const reader = new FileReader();
    reader.onload = () => {
      try {
        const parsed = JSON.parse(reader.result as string);
        if (!parsed.questions_recovery_enabled) {
          throw new Error("Invalid configuration file: Recovery not enabled.");
        }
        setRecLoadedConfig(parsed);
        setRecStatus("IDLE");
        setRecStatusMessage("Configuration loaded. Answer your security questions.");
      } catch (e: unknown) {
        setRecStatus("ERROR");
        const errMsg = e instanceof Error ? e.message : "Failed to parse JSON file.";
        setRecStatusMessage(errMsg);
      }
    };
    reader.readAsText(file);
  };

  const handleSendOtpCode = async () => {
    if (!recLoadedConfig || !recInputEmail) return;

    if (recLoadedConfig.questions_recovery_email.toLowerCase() !== recInputEmail.toLowerCase()) {
      setRecStatus("ERROR");
      setRecStatusMessage("Incorrect recovery email address.");
      return;
    }

    setRecStatus("PROCESSING");
    setRecStatusMessage("Sending verification code...");

    const code = (Math.floor(Math.random() * 900000) + 100000).toString();
    setRecGeneratedOtp(code);

    try {
      const response = await fetch("/api/send-email", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          to: [recInputEmail],
          subject: "AMPCrypt Web Recovery Verification Code",
          html: `<p>Your AMPCrypt security recovery code is: <strong>${code}</strong></p><p>Please enter this code in the web client along with your security question answers to recover your master key.</p>`,
        }),
      });

      if (response.ok) {
        setRecOtpSent(true);
        setRecStatus("SUCCESS");
        setRecStatusMessage(`Verification code sent to ${recInputEmail}!`);
      } else {
        const errData = await response.json();
        throw new Error(errData.message || "Failed to dispatch email.");
      }
    } catch (e: unknown) {
      setRecStatus("ERROR");
      const errMsg = e instanceof Error ? e.message : "Failed to send code. Please check your internet connection.";
      setRecStatusMessage(errMsg);
    }
  };

  const handleRestoreMasterKey = async () => {
    if (!recLoadedConfig || !recInputOtp || !recInputA1 || !recInputA2 || !recInputA3) return;

    if (recInputOtp !== recGeneratedOtp) {
      setRecStatus("ERROR");
      setRecStatusMessage("Invalid OTP verification code.");
      return;
    }

    setRecStatus("PROCESSING");
    setRecStatusMessage("Verifying security questions and deriving master key...");

    try {
      const salt = new Uint8Array(
        atob(recLoadedConfig.questions_recovery_salt)
          .split("")
          .map(c => c.charCodeAt(0))
      );
      const iv = new Uint8Array(
        atob(recLoadedConfig.questions_recovery_iv)
          .split("")
          .map(c => c.charCodeAt(0))
      );
      const encryptedMasterKey = new Uint8Array(
        atob(recLoadedConfig.questions_recovery_encrypted_master_key)
          .split("")
          .map(c => c.charCodeAt(0))
      );

      const combinedAnswers = [recInputA1, recInputA2, recInputA3]
        .map(a => a.trim().toLowerCase())
        .join("_");

      // Perform recovery decryption inside worker
      const decryptRes = await sendWorkerMessage("DECRYPT_RECOVERY", {
        passphrase: combinedAnswers,
        salt,
        data: encryptedMasterKey,
        iv,
      });

      if (decryptRes.type === "ERROR" || !decryptRes.payload.data) {
        throw new Error(decryptRes.payload.error || "Recovery failed. Incorrect security answers.");
      }

      const decoder = new TextDecoder();
      const decodedMasterKey = decoder.decode(new Uint8Array(decryptRes.payload.data));

      setRecoveredMasterKey(decodedMasterKey);
      setRecStatus("SUCCESS");
      setRecStatusMessage("Master key recovered successfully!");
    } catch (e: unknown) {
      setRecStatus("ERROR");
      const errMsg = e instanceof Error ? e.message : "Failed to reconstruct master key. Please check your answers.";
      setRecStatusMessage(errMsg);
    }
  };

  return (
    <div className="bg-[#0A0A0A] text-white min-h-screen relative font-sans">
      <Navbar />

      <main className="max-w-5xl mx-auto px-4 pt-32 pb-16 relative z-10">
        {/* Ambient Top Glow */}
        <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[600px] h-[300px] bg-[#00E5FF]/10 rounded-full filter blur-[100px] pointer-events-none" />

        <div className="text-center space-y-4 mb-10">
          <h1 className="text-4xl font-extrabold tracking-tight">
            Cryptographic <span className="text-[#00E5FF]">Client Portal</span>
          </h1>
          <p className="text-gray-400 max-w-xl mx-auto text-sm font-mono">
            Zero-knowledge cryptographic security suite. Protect files, split secrets, and setup offline recovery backups locally.
          </p>
        </div>

        {/* Premium Tab Navigation Bar */}
        <div className="flex justify-center mb-8">
          <div className="flex bg-[#0E0E0E] border border-white/5 rounded-2xl p-1.5 gap-2 backdrop-blur-md shadow-xl">
            <button
              onClick={() => setActiveTab("crypto")}
              className={`flex items-center gap-2.5 px-6 py-3 rounded-xl text-sm font-bold tracking-wider uppercase transition-all duration-300 ${
                activeTab === "crypto"
                  ? "bg-[#00E5FF] text-black shadow-lg shadow-cyan-500/10"
                  : "text-gray-400 hover:text-white hover:bg-white/5"
              }`}
            >
              <Shield className="w-4 h-4" /> Symmetric Crypto
            </button>
            <button
              onClick={() => setActiveTab("sss")}
              className={`flex items-center gap-2.5 px-6 py-3 rounded-xl text-sm font-bold tracking-wider uppercase transition-all duration-300 ${
                activeTab === "sss"
                  ? "bg-[#00E5FF] text-black shadow-lg shadow-cyan-500/10"
                  : "text-gray-400 hover:text-white hover:bg-white/5"
              }`}
            >
              <Split className="w-4 h-4" /> Key Splitting (SSS)
            </button>
            <button
              onClick={() => setActiveTab("recovery")}
              className={`flex items-center gap-2.5 px-6 py-3 rounded-xl text-sm font-bold tracking-wider uppercase transition-all duration-300 ${
                activeTab === "recovery"
                  ? "bg-[#00E5FF] text-black shadow-lg shadow-cyan-500/10"
                  : "text-gray-400 hover:text-white hover:bg-white/5"
              }`}
            >
              <Mail className="w-4 h-4" /> Emergency Recovery
            </button>
          </div>
        </div>

        <AnimatePresence mode="wait">
          {/* TAB 1: SYMMETRIC CRYPTO */}
          {activeTab === "crypto" && (
            <motion.div
              key="crypto"
              initial={{ opacity: 0, y: 15 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -15 }}
              transition={{ duration: 0.25 }}
              className="grid grid-cols-1 md:grid-cols-2 gap-8"
            >
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
            </motion.div>
          )}

          {/* TAB 2: KEY SPLITTING (SSS) */}
          {activeTab === "sss" && (
            <motion.div
              key="sss"
              initial={{ opacity: 0, y: 15 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -15 }}
              transition={{ duration: 0.25 }}
              className="grid grid-cols-1 md:grid-cols-2 gap-8"
            >
              {/* SPLIT ENGINE */}
              <div className="bg-[#0E0E0E]/80 border border-white/5 rounded-2xl p-6 space-y-6 shadow-xl backdrop-blur-md">
                <h2 className="text-lg font-bold flex items-center gap-2 border-b border-white/5 pb-3">
                  <Split className="w-5 h-5 text-[#00E5FF]" /> Split Secret
                </h2>

                <div className="space-y-2">
                  <label className="text-xs font-semibold text-gray-500 uppercase tracking-wider font-mono">
                    Passphrase to Split
                  </label>
                  <input
                    type="password"
                    placeholder="Enter Master Vault Secret Key"
                    value={sssPassphrase}
                    onChange={(e) => setSssPassphrase(e.target.value)}
                    className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-3 text-sm focus:outline-none focus:border-[#00E5FF] transition-colors"
                  />
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <label className="text-xs font-semibold text-gray-500 uppercase tracking-wider font-mono">
                      Total Shares (N)
                    </label>
                    <input
                      type="number"
                      min={2}
                      max={10}
                      value={sssN}
                      onChange={(e) => setSssN(Math.max(2, parseInt(e.target.value, 10) || 2))}
                      className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-3 text-sm focus:outline-none focus:border-[#00E5FF] transition-colors"
                    />
                  </div>

                  <div className="space-y-2">
                    <label className="text-xs font-semibold text-gray-500 uppercase tracking-wider font-mono">
                      Threshold (T)
                    </label>
                    <input
                      type="number"
                      min={2}
                      max={sssN}
                      value={sssT}
                      onChange={(e) => setSssT(Math.max(2, Math.min(sssN, parseInt(e.target.value, 10) || 2)))}
                      className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-3 text-sm focus:outline-none focus:border-[#00E5FF] transition-colors"
                    />
                  </div>
                </div>

                <button
                  onClick={handleSssSplit}
                  disabled={!sssPassphrase}
                  className="w-full py-3.5 bg-[#00E5FF] text-black font-bold rounded-xl shadow-lg shadow-cyan-500/10 hover:shadow-cyan-500/20 hover:bg-[#00E5FF]/90 active:scale-[0.98] disabled:opacity-40 disabled:pointer-events-none transition-all flex items-center justify-center gap-2"
                >
                  <Split className="w-4 h-4" /> Generate Cryptographic Shares
                </button>

                {sssShares.length > 0 && (
                  <div className="space-y-3 pt-4 border-t border-white/5">
                    <label className="text-xs font-semibold text-gray-500 uppercase tracking-wider font-mono block">
                      Generated Shares (T of N = {sssT} of {sssN})
                    </label>
                    <div className="space-y-2 max-h-[220px] overflow-y-auto pr-1">
                      {sssShares.map((share, idx) => (
                        <div key={idx} className="flex gap-2 items-center bg-[#141414] border border-white/5 rounded-xl px-4 py-2.5 text-xs font-mono">
                          <span className="text-[#00E5FF] font-bold">#{idx + 1}</span>
                          <span className="flex-grow truncate text-gray-400">{share}</span>
                          <button
                            onClick={() => copyShareToClipboard(share, idx)}
                            className="text-gray-400 hover:text-white transition-colors"
                          >
                            <Clipboard className="w-4 h-4" />
                          </button>
                          {copiedShareIndex === idx && (
                            <span className="text-[10px] text-emerald-400 font-bold">COPIED</span>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>

              {/* RECOMBINE ENGINE */}
              <div className="bg-[#0E0E0E]/80 border border-white/5 rounded-2xl p-6 space-y-6 shadow-xl backdrop-blur-md flex flex-col">
                <h2 className="text-lg font-bold flex items-center gap-2 border-b border-white/5 pb-3">
                  <Users className="w-5 h-5 text-[#00E5FF]" /> Recombine Shares
                </h2>

                <div className="space-y-2 flex-grow">
                  <label className="text-xs font-semibold text-gray-500 uppercase tracking-wider font-mono block">
                    Enter Shares (one per line)
                  </label>
                  <textarea
                    placeholder="1-abcd123...\n2-efgh456..."
                    value={sssRawSharesInput}
                    onChange={(e) => setSssRawSharesInput(e.target.value)}
                    className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-3 text-xs font-mono focus:outline-none focus:border-[#00E5FF] transition-colors resize-none h-[180px]"
                  />
                </div>

                <button
                  onClick={handleSssRecombine}
                  disabled={!sssRawSharesInput}
                  className="w-full py-3.5 bg-white/5 border border-white/10 text-white font-bold rounded-xl hover:bg-white/10 active:scale-[0.98] transition-all flex items-center justify-center gap-2"
                >
                  <Unlock className="w-4 h-4 text-[#00E5FF]" /> Recover Vault Key
                </button>

                {sssCombinedResult && (
                  <div className="p-4 bg-emerald-500/10 border border-emerald-500/20 rounded-xl text-center space-y-1 animate-pulse">
                    <span className="text-xs text-emerald-400 font-bold uppercase tracking-wider font-mono">Reconstructed Passphrase:</span>
                    <p className="text-base font-bold text-emerald-300 font-mono break-all">{sssCombinedResult}</p>
                  </div>
                )}

                {sssCombineError && (
                  <div className="p-4 bg-rose-500/10 border border-rose-500/20 rounded-xl text-center">
                    <p className="text-sm font-semibold text-rose-400">{sssCombineError}</p>
                  </div>
                )}
              </div>
            </motion.div>
          )}

          {/* TAB 3: EMERGENCY RECOVERY */}
          {activeTab === "recovery" && (
            <motion.div
              key="recovery"
              initial={{ opacity: 0, y: 15 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -15 }}
              transition={{ duration: 0.25 }}
              className="grid grid-cols-1 md:grid-cols-2 gap-8"
            >
              {/* CONFIGURATOR PANEL */}
              <div className="bg-[#0E0E0E]/80 border border-white/5 rounded-2xl p-6 space-y-6 shadow-xl backdrop-blur-md">
                <h2 className="text-lg font-bold flex items-center gap-2 border-b border-white/5 pb-3">
                  <FileText className="w-5 h-5 text-[#00E5FF]" /> Setup Recovery Backup
                </h2>

                <div className="space-y-4">
                  <div className="space-y-1">
                    <label className="text-[10px] font-semibold text-gray-500 uppercase tracking-wider font-mono">
                      Master Key (Passphrase/Key to Backup)
                    </label>
                    <input
                      type="password"
                      placeholder="Enter the Master Key to secure"
                      value={recMasterKey}
                      onChange={(e) => setRecMasterKey(e.target.value)}
                      className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-2.5 text-xs focus:outline-none focus:border-[#00E5FF] transition-colors"
                    />
                  </div>

                  <div className="space-y-1">
                    <label className="text-[10px] font-semibold text-gray-500 uppercase tracking-wider font-mono">
                      Recovery Email Address
                    </label>
                    <input
                      type="email"
                      placeholder="e.g. mail@itsupport.bd"
                      value={recEmail}
                      onChange={(e) => setRecEmail(e.target.value)}
                      className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-2.5 text-xs focus:outline-none focus:border-[#00E5FF] transition-colors"
                    />
                  </div>

                  <div className="space-y-2 pt-2 border-t border-white/5">
                    <label className="text-[10px] font-bold text-[#00E5FF] uppercase tracking-wider font-mono">
                      Security Questions & Answers
                    </label>
                    
                    <div className="space-y-2">
                      <div className="space-y-1">
                        <span className="text-[10px] text-gray-500 font-mono">Q1: {recQ1}</span>
                        <input
                          type="text"
                          placeholder="Your answer"
                          value={recA1}
                          onChange={(e) => setRecA1(e.target.value)}
                          className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-2 text-xs focus:outline-none focus:border-[#00E5FF] transition-colors"
                        />
                      </div>
                      
                      <div className="space-y-1">
                        <span className="text-[10px] text-gray-500 font-mono">Q2: {recQ2}</span>
                        <input
                          type="text"
                          placeholder="Your answer"
                          value={recA2}
                          onChange={(e) => setRecA2(e.target.value)}
                          className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-2 text-xs focus:outline-none focus:border-[#00E5FF] transition-colors"
                        />
                      </div>

                      <div className="space-y-1">
                        <span className="text-[10px] text-gray-500 font-mono">Q3: {recQ3}</span>
                        <input
                          type="text"
                          placeholder="Your answer"
                          value={recA3}
                          onChange={(e) => setRecA3(e.target.value)}
                          className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-2 text-xs focus:outline-none focus:border-[#00E5FF] transition-colors"
                        />
                      </div>
                    </div>
                  </div>
                </div>

                <button
                  onClick={handleGenerateRecoveryConfig}
                  disabled={!recMasterKey || !recEmail || !recA1 || !recA2 || !recA3 || recStatus === "PROCESSING"}
                  className="w-full py-3 bg-[#00E5FF] text-black font-bold rounded-xl shadow-lg hover:bg-[#00E5FF]/90 transition-all text-xs flex items-center justify-center gap-2"
                >
                  <Download className="w-4 h-4" /> Compile & Download Recovery File
                </button>

                {recConfigDownloadUrl && (
                  <a
                    href={recConfigDownloadUrl}
                    download="ampcrypt_recovery.json"
                    className="w-full py-3 bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 font-bold rounded-xl hover:bg-emerald-500/20 transition-all text-xs flex items-center justify-center gap-2 text-center"
                  >
                    <Download className="w-4 h-4" /> ampcrypt_recovery.json
                  </a>
                )}
              </div>

              {/* RECONSTRUCTOR PANEL */}
              <div className="bg-[#0E0E0E]/80 border border-white/5 rounded-2xl p-6 space-y-6 shadow-xl backdrop-blur-md flex flex-col">
                <h2 className="text-lg font-bold flex items-center gap-2 border-b border-white/5 pb-3">
                  <Unlock className="w-5 h-5 text-[#00E5FF]" /> Reconstruct Master Key
                </h2>

                {!recLoadedConfig ? (
                  <div
                    onDragOver={(e) => { e.preventDefault(); setRecUploadDragOver(true); }}
                    onDragLeave={() => setRecUploadDragOver(false)}
                    onDrop={(e) => {
                      e.preventDefault();
                      setRecUploadDragOver(false);
                      if (e.dataTransfer.files && e.dataTransfer.files[0]) {
                        parseConfigJson(e.dataTransfer.files[0]);
                      }
                    }}
                    className={`border border-dashed rounded-xl p-10 text-center transition-all relative cursor-pointer flex-grow flex flex-col justify-center items-center ${
                      recUploadDragOver
                        ? "border-[#00E5FF] bg-[#00E5FF]/5"
                        : "border-white/10 hover:border-[#00E5FF]/40 hover:bg-white/[0.02]"
                    }`}
                  >
                    <input
                      type="file"
                      accept=".json"
                      onChange={handleConfigJsonUpload}
                      className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                    />
                    <FileText className="w-10 h-10 text-gray-500 mb-3" />
                    <span className="text-xs text-gray-300 block">
                      Drag & drop recovery backup file (.json) or click to browse
                    </span>
                  </div>
                ) : (
                  <div className="space-y-4 flex-grow">
                    {/* STEP 1: Verify Email Code */}
                    {!recOtpSent ? (
                      <div className="space-y-3">
                        <div className="p-3 bg-white/[0.02] border border-white/5 rounded-xl">
                          <span className="text-[10px] text-gray-500 font-mono block">Backup Recovery Target:</span>
                          <span className="text-xs text-[#00E5FF] font-semibold">{recLoadedConfig.questions_recovery_email}</span>
                        </div>

                        <div className="space-y-1">
                          <label className="text-[10px] font-semibold text-gray-500 uppercase tracking-wider font-mono">
                            Enter Recovery Email to confirm
                          </label>
                          <input
                            type="email"
                            placeholder="Confirm your recovery email"
                            value={recInputEmail}
                            onChange={(e) => setRecInputEmail(e.target.value)}
                            className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-2.5 text-xs focus:outline-none focus:border-[#00E5FF] transition-colors"
                          />
                        </div>

                        <button
                          onClick={handleSendOtpCode}
                          disabled={!recInputEmail || recStatus === "PROCESSING"}
                          className="w-full py-3 bg-[#00E5FF] text-black font-bold rounded-xl hover:bg-[#00E5FF]/90 transition-all text-xs flex items-center justify-center gap-2"
                        >
                          <Mail className="w-4 h-4" /> Send Verification Code
                        </button>
                      </div>
                    ) : (
                      // STEP 2: Answer Questions + OTP
                      <div className="space-y-4">
                        <div className="space-y-1.5 p-3.5 bg-emerald-500/5 border border-emerald-500/10 rounded-xl text-xs text-emerald-400">
                          Code successfully sent! Please check your recovery inbox.
                        </div>

                        <div className="space-y-1">
                          <label className="text-[10px] font-semibold text-gray-500 uppercase tracking-wider font-mono">
                            6-Digit Verification Code
                          </label>
                          <input
                            type="text"
                            placeholder="Enter verification code"
                            value={recInputOtp}
                            onChange={(e) => setRecInputOtp(e.target.value)}
                            className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-2.5 text-xs font-mono text-center tracking-widest focus:outline-none focus:border-[#00E5FF] transition-colors"
                          />
                        </div>

                        <div className="space-y-3 pt-2 border-t border-white/5">
                          <label className="text-[10px] font-bold text-[#00E5FF] uppercase tracking-wider font-mono">
                            Answer Security Questions
                          </label>
                          
                          <div className="space-y-2">
                            <div className="space-y-1">
                              <span className="text-[10px] text-gray-500 font-mono">Q1: {recLoadedConfig.questions_recovery_questions[0]}</span>
                              <input
                                type="text"
                                placeholder="Your answer"
                                value={recInputA1}
                                onChange={(e) => setRecInputA1(e.target.value)}
                                className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-2 text-xs focus:outline-none focus:border-[#00E5FF] transition-colors"
                              />
                            </div>
                            
                            <div className="space-y-1">
                              <span className="text-[10px] text-gray-500 font-mono">Q2: {recLoadedConfig.questions_recovery_questions[1]}</span>
                              <input
                                type="text"
                                placeholder="Your answer"
                                value={recInputA2}
                                onChange={(e) => setRecInputA2(e.target.value)}
                                className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-2 text-xs focus:outline-none focus:border-[#00E5FF] transition-colors"
                              />
                            </div>

                            <div className="space-y-1">
                              <span className="text-[10px] text-gray-500 font-mono">Q3: {recLoadedConfig.questions_recovery_questions[2]}</span>
                              <input
                                type="text"
                                placeholder="Your answer"
                                value={recInputA3}
                                onChange={(e) => setRecInputA3(e.target.value)}
                                className="w-full bg-[#141414] border border-white/10 rounded-xl px-4 py-2 text-xs focus:outline-none focus:border-[#00E5FF] transition-colors"
                              />
                            </div>
                          </div>
                        </div>

                        <button
                          onClick={handleRestoreMasterKey}
                          disabled={!recInputOtp || !recInputA1 || !recInputA2 || !recInputA3 || recStatus === "PROCESSING"}
                          className="w-full py-3 bg-[#00E5FF] text-black font-bold rounded-xl hover:bg-[#00E5FF]/90 transition-all text-xs flex items-center justify-center gap-2"
                        >
                          <Unlock className="w-4 h-4" /> Reconstruct Master Key
                        </button>
                      </div>
                    )}
                  </div>
                )}

                {/* Console Log status panel for recovery */}
                {recStatusMessage && (
                  <div className={`mt-4 p-3 rounded-xl border text-xs text-center flex items-center justify-center gap-2 ${
                    recStatus === "SUCCESS"
                      ? "bg-emerald-500/10 border-emerald-500/20 text-emerald-400"
                      : recStatus === "ERROR"
                      ? "bg-rose-500/10 border-rose-500/20 text-rose-400"
                      : "bg-[#141414] border-white/5 text-gray-400"
                  }`}>
                    {recStatus === "PROCESSING" && <RefreshCw className="w-3.5 h-3.5 animate-spin text-[#00E5FF]" />}
                    {recStatus === "SUCCESS" && <CheckCircle className="w-3.5 h-3.5 text-emerald-400" />}
                    {recStatus === "ERROR" && <AlertTriangle className="w-3.5 h-3.5 text-rose-400" />}
                    <span>{recStatusMessage}</span>
                  </div>
                )}

                {/* Success Recovered Display */}
                {recoveredMasterKey && (
                  <div className="mt-4 p-4 bg-emerald-500/10 border border-emerald-500/20 rounded-xl text-center space-y-1">
                    <span className="text-[10px] text-emerald-400 font-bold uppercase tracking-wider font-mono">Successfully Recovered Master Key:</span>
                    <p className="text-sm font-bold text-emerald-300 font-mono break-all">{recoveredMasterKey}</p>
                    <button
                      onClick={() => navigator.clipboard.writeText(recoveredMasterKey)}
                      className="mt-2 inline-flex items-center gap-1 px-3 py-1 bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-300 rounded-lg text-xs transition-colors"
                    >
                      <Clipboard className="w-3 h-3" /> Copy Master Key
                    </button>
                  </div>
                )}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </main>
    </div>
  );
}
