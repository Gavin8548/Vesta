//
//  BottleTuning.swift
//
//  把容器的图形后端、同步方式和渲染开关记到 UserDefaults。
//  启动时再写回内存里的 Bottle，不在冷启动扫描 Wine 目录。
//

import Foundation

nonisolated enum BottleGraphicsBackend: String, CaseIterable, Identifiable, Sendable {
    case dxvk
    case dxmt
    case d3dmetal

    var id: String { rawValue }
}

nonisolated enum BottleSyncMode: String, CaseIterable, Identifiable, Sendable {
    case msync
    case esync
    case fsync
    case off

    var id: String { rawValue }
}

nonisolated enum BottleTuningStore {
    private struct Record: Codable, Sendable {
        var enablesDXVK: Bool
        var enablesMetal3: Bool
        var enablesDXMT: Bool
        var enablesEsync: Bool
        var enablesMsync: Bool
        var disablesRetina: Bool
        var enablesShaderCache: Bool
    }

    static func load(into bottle: inout Bottle) {
        guard let data = UserDefaults.standard.data(forKey: key(bottle.id)),
              let record = try? JSONDecoder().decode(Record.self, from: data) else {
            return
        }
        bottle.enablesDXVK = record.enablesDXVK
        bottle.enablesMetal3 = record.enablesMetal3
        bottle.enablesDXMT = record.enablesDXMT
        bottle.enablesEsync = record.enablesEsync
        bottle.enablesMsync = record.enablesMsync
        bottle.disablesRetina = record.disablesRetina
        bottle.enablesShaderCache = record.enablesShaderCache
    }

    static func save(_ bottle: Bottle) {
        let record = Record(
            enablesDXVK: bottle.enablesDXVK,
            enablesMetal3: bottle.enablesMetal3,
            enablesDXMT: bottle.enablesDXMT,
            enablesEsync: bottle.enablesEsync,
            enablesMsync: bottle.enablesMsync,
            disablesRetina: bottle.disablesRetina,
            enablesShaderCache: bottle.enablesShaderCache
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: key(bottle.id))
    }

    private static func key(_ id: String) -> String {
        "Vesta.bottleTuning." + id
    }
}
