/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

// provider.ts
// Generic interface defining Cloud Storage Provider operations for encrypted chunk synchronization

export interface CloudStorageProvider {
  id: string;
  name: string;
  
  /**
   * Upload an encrypted chunk shard to the cloud provider.
   */
  uploadShard(vaultId: string, shardId: string, data: ArrayBuffer): Promise<void>;

  /**
   * Download a chunk shard from the cloud provider.
   */
  downloadShard(vaultId: string, shardId: string): Promise<ArrayBuffer>;

  /**
   * Delete a chunk shard from the cloud provider.
   */
  deleteShard(vaultId: string, shardId: string): Promise<void>;
}
