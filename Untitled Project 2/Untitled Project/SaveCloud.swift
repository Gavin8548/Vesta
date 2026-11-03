//
//  SaveCloud.swift
//
//  把已经打好的存档包上传到当前登录用户的 Supabase Storage。
//  没有登录、没有桶，或上传失败时只返回说明，不假装已经同步。
//
//  需要先在 Supabase 建好私有桶 save-backups，以及这张表：
//  create table save_backups (
//    id uuid primary key default gen_random_uuid(),
//    user_id uuid not null references auth.users on delete cascade,
//    bottle text not null,
//    bytes bigint not null,
//    storage_path text not null,
//    created_at timestamptz not null default now()
//  );
//  alter table save_backups enable row level security;
//  create policy "own saves" on save_backups
//    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
//

import Foundation
import Supabase

struct SaveCloudRecord: Decodable, Identifiable, Sendable {
    var id: UUID
    var bottle: String
    var bytes: Int64
    var storagePath: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, bottle, bytes
        case storagePath = "storage_path"
        case createdAt = "created_at"
    }
}

private struct SaveCloudInsert: Encodable {
    var userId: UUID
    var bottle: String
    var bytes: Int64
    var storagePath: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case bottle, bytes
        case storagePath = "storage_path"
    }
}

@MainActor
enum SaveCloudSync {
    private static let bucket = "save-backups"

    static func upload(bottleName: String) async -> String {
        let language = L10n.savedLanguage()
        guard SupabaseManager.shared.isAuthenticated else {
            return L10n.string(.saveNeedAccount, language: language)
        }
        let name = bottleName
        let file = await Task.detached(priority: .utility) {
            SaveSyncManager.latestPayload(bottleName: name)
        }.value
        guard let file else {
            return L10n.string(.saveSyncEmpty, language: language)
        }
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let object = "\(session.user.id.uuidString.lowercased())/\(safe(name))/\(stamp).vestasave"
            try await SupabaseManager.shared.client.storage
                .from(bucket)
                .upload(object, fileURL: file, options: FileOptions(contentType: "application/octet-stream"))
            let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            let row = SaveCloudInsert(
                userId: session.user.id,
                bottle: name,
                bytes: bytes,
                storagePath: object
            )
            try await SupabaseManager.shared.client.from("save_backups").insert(row).execute()
            return L10n.string(.saveCloudDone, language: language)
        } catch {
            print("[SaveCloud] \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    static func list(bottleName: String) async -> [SaveCloudRecord] {
        guard SupabaseManager.shared.isAuthenticated else { return [] }
        do {
            let rows: [SaveCloudRecord] = try await SupabaseManager.shared.client
                .from("save_backups")
                .select()
                .eq("bottle", value: bottleName)
                .order("created_at", ascending: false)
                .limit(12)
                .execute()
                .value
            return rows
        } catch {
            print("[SaveCloud] 列表失败：\(error.localizedDescription)")
            return []
        }
    }

    static func restore(_ record: SaveCloudRecord, bottleName: String) async -> String {
        do {
            let data = try await SupabaseManager.shared.client.storage
                .from(bucket)
                .download(path: record.storagePath)
            let name = bottleName
            return await Task.detached(priority: .utility) {
                do {
                    let folder = FileManager.default.temporaryDirectory
                        .appendingPathComponent("VestaCloud-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let payload = folder.appendingPathComponent("payload.vestasave")
                    try data.write(to: payload, options: .atomic)
                    return SaveSyncManager.restorePayload(payload, bottleName: name)
                } catch {
                    print("[SaveCloud] 下载失败：\(error.localizedDescription)")
                    return error.localizedDescription
                }
            }.value
        } catch {
            print("[SaveCloud] 下载失败：\(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    /// 仅当这只瓶子里已经没有其他游戏时，才删掉该瓶子的云端存档记录。
    static func deleteBottleRecords(named bottle: String) async -> Bool {
        guard SupabaseManager.shared.isAuthenticated else { return false }
        let name = bottle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        do {
            let rows: [SaveCloudRecord] = try await SupabaseManager.shared.client
                .from("save_backups")
                .select()
                .eq("bottle", value: name)
                .execute()
                .value
            let paths = rows.map(\.storagePath).filter { !$0.isEmpty }
            if !paths.isEmpty {
                try await SupabaseManager.shared.client.storage
                    .from(bucket)
                    .remove(paths: paths)
            }
            try await SupabaseManager.shared.client
                .from("save_backups")
                .delete()
                .eq("bottle", value: name)
                .execute()
            return true
        } catch {
            print("[SaveCloud] 删除云端记录失败：\(error.localizedDescription)")
            return false
        }
    }

    private static func safe(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? "bottle" : cleaned
    }
}
