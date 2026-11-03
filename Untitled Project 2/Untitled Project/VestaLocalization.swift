//
//  VestaLocalization.swift
//
//  六种界面语言的查表入口，以及游戏库标题。
//  库里的 name 仍是中文目录键，用来对上存档和示例数据。
//  显示时按当前语言取标题；没有译文时先用英文，再用目录键。
//  界面句子继续走 L10nKey。应用内语言一切换就会刷新，不依赖系统 String Catalog。
//

import SwiftUI

enum VestaLocalization {
    /// 英语、日语、韩语、意大利语、法语、西班牙语。中文是目录原文。
    static let interfaceLanguages: [AppLanguage] = [
        .english, .japanese, .korean, .italian, .french, .spanish
    ]

    static func text(_ key: L10nKey, language: AppLanguage = L10n.savedLanguage()) -> String {
        L10n.string(key, language: language)
    }

    static func catalogTitle(canonical: String, language: AppLanguage) -> String {
        if language == .chinese {
            return canonical
        }
        guard let pack = CatalogTitles.titles[canonical] else {
            return SampleCopy.english(forName: canonical)?.name ?? canonical
        }
        let chosen = pack.text(for: language)
        if !chosen.isEmpty {
            return chosen
        }
        if !pack.en.isEmpty {
            return pack.en
        }
        return canonical
    }
}

struct CatalogTitlePack {
    var en: String
    var ja: String
    var ko: String
    var it: String
    var fr: String
    var es: String

    func text(for language: AppLanguage) -> String {
        switch language {
        case .chinese:
            return ""
        case .english:
            return en
        case .japanese:
            return ja
        case .korean:
            return ko
        case .italian:
            return it
        case .french:
            return fr
        case .spanish:
            return es
        }
    }
}

enum CatalogTitles {
    /// 新增游戏时在这里加一行。键必须和 WindowsApp.name 完全一致。
    static let titles: [String: CatalogTitlePack] = [
        "黑神话：悟空 (Black Myth: Wukong)": pack(
            "Black Myth: Wukong",
            "黒神話：悟空",
            "검은 신화: 오공"
        ),
        "赛博朋克 2077 (Cyberpunk 2077)": pack(
            "Cyberpunk 2077",
            "サイバーパンク2077",
            "사이버펑크 2077"
        ),
        "艾尔登法环 (Elden Ring)": pack(
            "Elden Ring",
            "エルデンリング",
            "엘든 링"
        ),
        "GTA 5 (Grand Theft Auto V)": pack(
            "Grand Theft Auto V",
            "グランド・セフト・オートV",
            "그랜드 테프트 오토 V"
        ),
        "荒野大镖客：救赎 2 (Red Dead Redemption 2)": pack(
            "Red Dead Redemption 2",
            "レッド・デッド・リデンプション2",
            "레드 데드 리뎀션 2"
        ),
        "博德之门 3 (Baldur's Gate 3)": pack(
            "Baldur's Gate 3",
            "バルダーズ・ゲート3",
            "발더스 게이트 3"
        ),
        "怪物猎人：世界 (Monster Hunter: World)": pack(
            "Monster Hunter: World",
            "モンスターハンター：ワールド",
            "몬스터 헌터: 월드"
        ),
        "巫师 3：狂猎 (The Witcher 3: Wild Hunt)": pack(
            "The Witcher 3: Wild Hunt",
            "ウィッチャー3 ワイルドハント",
            "위쳐 3: 와일드 헌트"
        ),
        "星露谷物语 (Stardew Valley)": pack(
            "Stardew Valley",
            "スターデューバレー",
            "스타듀 밸리"
        ),
        "生化危机 4：重制版 (Resident Evil 4)": pack(
            "Resident Evil 4",
            "バイオハザード RE:4",
            "바이오하자드 RE:4"
        ),
        "死亡搁浅 导演剪辑版 (Death Stranding Director's Cut)": pack(
            "Death Stranding Director's Cut",
            "デス・ストランディング ディレクターズカット",
            "데스 스트랜딩 디렉터스 컷"
        ),
        "博德之门 3 (Baldur's Gate 3 - Native)": pack(
            "Baldur's Gate 3 (macOS)",
            "バルダーズ・ゲート3（macOS）",
            "발더스 게이트 3 (macOS)"
        ),
        "无人深空 (No Man's Sky - Apple Silicon Native)": pack(
            "No Man's Sky",
            "ノーマンズスカイ",
            "노 맨즈 스카이"
        ),
        "无畏契约（国服）": pack(
            "VALORANT (China)",
            "VALORANT（中国）",
            "발로란트 (중국)"
        ),
        "瓦罗兰特（亚服）": pack(
            "VALORANT (Asia-Pacific)",
            "VALORANT（アジア太平洋）",
            "발로란트 (아시아 태평양)"
        ),
        "瓦罗兰特（美服）": pack(
            "VALORANT (Americas)",
            "VALORANT（アメリカ）",
            "발로란트 (아메리카)"
        ),
        "瓦罗兰特（欧服）": pack(
            "VALORANT (Europe)",
            "VALORANT（ヨーロッパ）",
            "발로란트 (유럽)"
        ),
        "绝地求生 (PUBG)": pack(
            "PUBG: BATTLEGROUNDS",
            "PUBG: BATTLEGROUNDS",
            "배틀그라운드"
        ),
        "Microsoft Word (Mac 原生版)": pack(
            "Microsoft Word (Mac)",
            "Microsoft Word（Mac）",
            "Microsoft Word (Mac)"
        ),
        "Microsoft Excel (Mac 原生版)": pack(
            "Microsoft Excel (Mac)",
            "Microsoft Excel（Mac）",
            "Microsoft Excel (Mac)"
        ),
        "Microsoft PowerPoint (Mac 原生版)": pack(
            "Microsoft PowerPoint (Mac)",
            "Microsoft PowerPoint（Mac）",
            "Microsoft PowerPoint (Mac)"
        ),
        "Microsoft Word (Windows 容器版)": pack(
            "Microsoft Word (Windows)",
            "Microsoft Word（Windows）",
            "Microsoft Word (Windows)"
        ),
        "Microsoft Excel (Windows 容器版)": pack(
            "Microsoft Excel (Windows)",
            "Microsoft Excel（Windows）",
            "Microsoft Excel (Windows)"
        ),
        "Microsoft PowerPoint": pack(
            "Microsoft PowerPoint (Windows)",
            "Microsoft PowerPoint（Windows）",
            "Microsoft PowerPoint (Windows)"
        ),
        "Notepad++ (Windows 容器版)": pack(
            "Notepad++ (Windows)",
            "Notepad++（Windows）",
            "Notepad++ (Windows)"
        ),
        "Steam": pack("Steam", "Steam", "Steam")
    ]

    private static func pack(_ en: String, _ ja: String, _ ko: String) -> CatalogTitlePack {
        CatalogTitlePack(en: en, ja: ja, ko: ko, it: en, fr: en, es: en)
    }
}
