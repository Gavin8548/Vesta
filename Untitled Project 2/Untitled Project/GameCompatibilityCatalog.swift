//
//  GameCompatibilityCatalog.swift
//
//  内置主流游戏兼容性目录。按名称和 Steam 编号匹配。
//  不爬网页，也不把未实测的游戏写成“完美运行”。
//

import Foundation

nonisolated enum CompatibilityTier: String, Sendable {
    case native
    case tunable
    case blocked
}

nonisolated struct CompatibilityRecord: Sendable, Identifiable {
    var title: String
    var aliases: [String]
    var steamAppID: String
    var tier: CompatibilityTier
    var reason: String

    var id: String { steamAppID.isEmpty ? title : steamAppID }

    fileprivate static func native(_ title: String, _ aliases: [String], _ steam: String = "", _ reason: String) -> CompatibilityRecord {
        CompatibilityRecord(title: title, aliases: aliases, steamAppID: steam, tier: .native, reason: reason)
    }

    fileprivate static func tunable(_ title: String, _ aliases: [String], _ steam: String = "", _ reason: String) -> CompatibilityRecord {
        CompatibilityRecord(title: title, aliases: aliases, steamAppID: steam, tier: .tunable, reason: reason)
    }

    fileprivate static func blocked(_ title: String, _ aliases: [String], _ steam: String = "", _ reason: String) -> CompatibilityRecord {
        CompatibilityRecord(title: title, aliases: aliases, steamAppID: steam, tier: .blocked, reason: reason)
    }
}

nonisolated struct LibraryProbe: Sendable {
    var name: String
    var steamAppID: String
    var platform: String
    var imported: Bool
}

nonisolated struct LibraryMatch: Sendable {
    var probe: LibraryProbe
    var record: CompatibilityRecord?
}

nonisolated enum GameCompatibilityCatalog {
    static var records: [CompatibilityRecord] { catalog }

    static func match(name: String, steamAppID: String) -> CompatibilityRecord? {
        let steam = steamAppID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !steam.isEmpty, let found = catalog.first(where: { $0.steamAppID == steam }) {
            return found
        }
        let folded = fold(name)
        guard folded.count >= 2 else { return nil }
        var best: (record: CompatibilityRecord, score: Int)?
        for record in catalog {
            for alias in [record.title] + record.aliases {
                let needle = fold(alias)
                guard needle.count >= 3 else { continue }
                let score: Int
                if folded == needle {
                    score = 1_000 + needle.count
                } else if folded.contains(needle), needle.count >= containsThreshold(needle) {
                    score = needle.count
                } else {
                    continue
                }
                if score > (best?.score ?? 0) {
                    best = (record, score)
                }
            }
        }
        return best?.record
    }

    private static func containsThreshold(_ needle: String) -> Int {
        needle.unicodeScalars.contains { $0.value > 127 } ? 2 : 6
    }

    static func records(in tier: CompatibilityTier) -> [CompatibilityRecord] {
        catalog.filter { $0.tier == tier }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "：", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "'", with: "")
    }

    private static let nativeReason = "有官方 macOS 版本，不经过 Wine。这里只说明发行平台，没有在这台 Mac 上测量帧率。"
    private static let tunableReason = "没有已知的内核级反作弊。仍要放进 Wine / GPTK 容器，并按游戏调整图形参数。这不是逐款实测结论。"
    private static let vanguard = "使用 Riot Vanguard。它是内核级反作弊，不能在 Wine 或 macOS 容器里加载。"
    private static let eac = "使用 Easy Anti-Cheat。内核组件不能在 Wine 容器里通过校验。"
    private static let battleye = "使用 BattlEye。内核组件不能在 Wine 容器里通过校验。"
    private static let guardReason = "使用 nProtect GameGuard。内核驱动不能在 Wine 容器里加载。"
    private static let ricochet = "使用 Ricochet 等内核级反作弊，不能在 Wine 容器里运行。"
    private static let mhy = "使用米哈游内核保护模块，不能在 Wine 容器里加载。"

    private static let catalog: [CompatibilityRecord] = [
        .native("博德之门 3", ["baldur's gate 3", "baldurs gate 3", "博德之门3"], "1086940", nativeReason),
        .native("无人深空", ["no man's sky", "no mans sky"], "275850", nativeReason),
        .native("死亡搁浅 导演剪辑版", ["death stranding"], "1850570", nativeReason),
        .native("星露谷物语", ["stardew valley"], "413150", nativeReason),
        .native("哈迪斯", ["hades"], "1145360", nativeReason),
        .native("哈迪斯 II", ["hades ii", "hades 2"], "1145350", nativeReason),
        .native("极乐迪斯科", ["disco elysium"], "632470", nativeReason),
        .native("空洞骑士", ["hollow knight"], "367520", nativeReason),
        .native("茶杯头", ["cuphead"], "268910", nativeReason),
        .native("潜水员戴夫", ["dave the diver"], "1868140", nativeReason),
        .native("迷失", ["stray"], "1332010", nativeReason),
        .native("生化危机 8：村庄", ["resident evil village", "resident evil 8"], "1196590", nativeReason),
        .native("生化危机 4 重制版", ["resident evil 4"], "2050650", nativeReason),
        .native("怪物猎人崛起", ["monster hunter rise"], "1446780", nativeReason),
        .native("魔兽世界", ["world of warcraft", "wow"], "", nativeReason),
        .native("我的世界", ["minecraft"], "", nativeReason),
        .native("泰拉瑞亚", ["terraria"], "105600", nativeReason),
        .native("异星工厂", ["factorio"], "427520", nativeReason),
        .native("文明 VI", ["civilization vi", "civilization 6", "sid meier's civilization vi"], "289070", nativeReason),
        .native("神界：原罪 2", ["divinity original sin 2", "divinity: original sin 2"], "435150", nativeReason),
        .native("环世界", ["rimworld"], "294100", nativeReason),
        .native("杀戮尖塔", ["slay the spire"], "646570", nativeReason),
        .native("死亡细胞", ["dead cells"], "588650", nativeReason),
        .native("蔚蓝", ["celeste"], "504230", nativeReason),
        .native("深海迷航", ["subnautica"], "264710", nativeReason),
        .native("见证者", ["the witness"], "210970", nativeReason),
        .native("Gris", ["gris"], "683320", nativeReason),
        .native("吸血鬼幸存者", ["vampire survivors"], "1794680", nativeReason),
        .native("Balatro", ["balatro"], "2379780", nativeReason),
        .native("咩咩启示录", ["cult of the lamb"], "1313140", nativeReason),
        .native("渔帆暗涌", ["dredge"], "1562430", nativeReason),
        .native("Tunic", ["tunic"], "553420", nativeReason),
        .native("星之海", ["sea of stars"], "1244090", nativeReason),
        .native("无题鹅游戏", ["untitled goose game"], "837470", nativeReason),
        .native("Inside", ["inside"], "304430", nativeReason),
        .native("Limbo", ["limbo"], "48000", nativeReason),
        .native("幽浮 2", ["xcom 2"], "268500", nativeReason),
        .native("陷阵之志", ["into the breach"], "590380", nativeReason),
        .native("永恒之柱", ["pillars of eternity"], "291650", nativeReason),
        .native("足球经理", ["football manager"], "", nativeReason),
        .native("Spiritfarer", ["spiritfarer"], "972660", nativeReason),
        .native("Cocoon", ["cocoon"], "1497440", nativeReason),
        .native("Night in the Woods", ["night in the woods"], "481510", nativeReason),
        .native("Oxenfree", ["oxenfree"], "388880", nativeReason),
        .native("Tomb Raider", ["tomb raider"], "203160", "2013 版有官方 macOS 版本。较新的《崛起》和《暗影》没有原生版。"),
        .native("生化奇兵：无限", ["bioshock infinite"], "8870", nativeReason),
        .native("异形：隔离", ["alien isolation", "alien: isolation"], "214490", nativeReason),
        .native("缺氧", ["oxygen not included"], "457140", nativeReason),
        .native("城市：天际线", ["cities skylines", "cities: skylines"], "255710", nativeReason),
        .native("FTL", ["ftl: faster than light", "faster than light"], "212680", nativeReason),
        .native("Bastion", ["bastion"], "107100", nativeReason),
        .native("Transistor", ["transistor"], "237930", nativeReason),
        .native("饥荒", ["don't starve", "dont starve"], "219740", nativeReason),
        .native("饥荒：联机版", ["don't starve together", "dont starve together"], "322330", nativeReason),
        .native("坎巴拉太空计划", ["kerbal space program"], "220200", nativeReason),
        .native("监狱建筑师", ["prison architect"], "233450", nativeReason),
        .native("双点医院", ["two point hospital"], "535930", nativeReason),
        .native("十字军之王 III", ["crusader kings iii", "crusader kings 3"], "1158310", nativeReason),
        .native("欧陆风云 IV", ["europa universalis iv", "europa universalis 4"], "236850", nativeReason),
        .native("钢铁雄心 IV", ["hearts of iron iv", "hearts of iron 4"], "394360", nativeReason),
        .native("群星", ["stellaris"], "281990", nativeReason),
        .native("请出示文件", ["papers please"], "239030", nativeReason),
        .native("奥伯拉·丁的回归", ["return of the obra dinn"], "653530", nativeReason),
        .native("邪恶冥刻", ["inscryption"], "1092790", nativeReason),
        .native("奥日与黑暗森林", ["ori and the blind forest"], "261570", nativeReason),
        .native("奥日与精灵意志", ["ori and the will of the wisps"], "1057090", nativeReason),
        .native("看火人", ["firewatch"], "383870", nativeReason),
        .native("艾迪芬奇的记忆", ["what remains of edith finch", "edith finch"], "501300", nativeReason),
        .native("传送门 2", ["portal 2"], "620", nativeReason),
        .native("半衰期 2", ["half-life 2", "half life 2"], "220", nativeReason),
        .native("求生之路 2", ["left 4 dead 2"], "550", nativeReason),
        .native("刀塔 2", ["dota 2", "dota2"], "570", nativeReason),
        .native("模拟人生 4", ["the sims 4", "sims 4"], "", nativeReason),
        .native("欧洲卡车模拟 2", ["euro truck simulator 2"], "227300", nativeReason),
        .native("美国卡车模拟", ["american truck simulator"], "270880", nativeReason),
        .native("生化奇兵", ["bioshock"], "7670", "初代有官方 macOS 版本。《生化奇兵 2》没有对等的现行原生版。"),

        .tunable("王国来临：救赎", ["kingdom come deliverance"], "379430", tunableReason),
        .tunable("王国来临：救赎 2", ["kingdom come deliverance ii", "kingdom come deliverance 2"], "1771300", tunableReason),
        .tunable("黑暗之魂 2", ["dark souls ii", "dark souls 2"], "335300", tunableReason),
        .tunable("仁王 2", ["nioh 2"], "1325200", tunableReason),
        .tunable("卧龙：苍天陨落", ["wo long", "wo long fallen dynasty"], "1448440", tunableReason),
        .tunable("最终幻想 15", ["final fantasy xv", "final fantasy 15"], "637650", tunableReason),
        .tunable("辐射：新维加斯", ["fallout new vegas"], "22380", tunableReason),
        .tunable("掠食", ["prey"], "480490", tunableReason),
        .tunable("耻辱", ["dishonored"], "205100", tunableReason),
        .tunable("黑手党：决定版", ["mafia definitive edition"], "1030840", tunableReason),
        .tunable("热血无赖", ["sleeping dogs"], "307690", tunableReason),
        .tunable("如龙 极", ["yakuza kiwami"], "834530", tunableReason),
        .tunable("审判之眼", ["judgment", "judge eyes"], "", tunableReason),
        .tunable("审判之逝", ["lost judgment"], "", tunableReason),
        .tunable("女神异闻录 3 Reload", ["persona 3 reload"], "2161700", tunableReason),
        .tunable("女神异闻录 4 黄金版", ["persona 4 golden"], "1113000", tunableReason),
        .tunable("神秘海域：盗贼传奇合集", ["uncharted legacy of thieves", "uncharted"], "1659420", tunableReason),
        .tunable("死亡空间 重制版", ["dead space"], "1693980", tunableReason),
        .tunable("木卫四协议", ["the callisto protocol"], "1544020", tunableReason),
        .tunable("直到黎明", ["until dawn"], "", tunableReason),
        .tunable("底特律：变人", ["detroit become human"], "1222140", tunableReason),
        .tunable("地平线：西之绝境", ["horizon forbidden west"], "", tunableReason),
        .tunable("战神：诸神黄昏", ["god of war ragnarok", "ragnarok"], "2322010", tunableReason),
        .tunable("漫威蜘蛛侠：迈尔斯", ["spider-man miles morales", "miles morales"], "1817190", tunableReason),
        .tunable("黑神话：悟空", ["black myth", "wukong", "黑神话"], "2358720", tunableReason),
        .tunable("艾尔登法环", ["elden ring"], "1245620", tunableReason),
        .tunable("赛博朋克 2077", ["cyberpunk 2077", "cyberpunk"], "1091500", tunableReason),
        .tunable("巫师 3：狂猎", ["the witcher 3", "witcher 3", "巫师3"], "292030", tunableReason),
        .tunable("GTA 5", ["grand theft auto v", "gta v", "gta5"], "271590", "故事模式没有内核级反作弊，仍要放进容器。GTA 线上模式的反作弊不保证可用。"),
        .tunable("荒野大镖客：救赎 2", ["red dead redemption 2", "rdr2"], "1174180", "故事模式没有内核级反作弊，仍要放进容器。线上模式的反作弊不保证可用。"),
        .tunable("怪物猎人：世界", ["monster hunter world", "monster hunter: world"], "582010", tunableReason),
        .tunable("只狼", ["sekiro"], "814380", tunableReason),
        .tunable("黑暗之魂 3", ["dark souls iii", "dark souls 3"], "374320", tunableReason),
        .tunable("装甲核心 VI", ["armored core vi", "armored core 6"], "1888160", tunableReason),
        .tunable("匹诺曹的谎言", ["lies of p"], "1627720", tunableReason),
        .tunable("霍格沃茨之遗", ["hogwarts legacy"], "990080", tunableReason),
        .tunable("战神", ["god of war"], "1593500", tunableReason),
        .tunable("地平线：零之曙光", ["horizon zero dawn"], "1151640", tunableReason),
        .tunable("对马岛之鬼", ["ghost of tsushima"], "2215430", tunableReason),
        .tunable("漫威蜘蛛侠重制版", ["spider-man remastered", "marvel's spider-man remastered"], "1817070", tunableReason),
        .tunable("美国末日", ["the last of us part i", "last of us"], "1888930", tunableReason),
        .tunable("往日不再", ["days gone"], "1259420", tunableReason),
        .tunable("控制", ["control"], "870780", tunableReason),
        .tunable("心灵杀手 2", ["alan wake 2", "alan wake ii"], "2420110", tunableReason),
        .tunable("地铁：离去", ["metro exodus"], "412020", tunableReason),
        .tunable("生化危机 2 重制版", ["resident evil 2"], "883710", tunableReason),
        .tunable("生化危机 3 重制版", ["resident evil 3"], "952060", tunableReason),
        .tunable("生化危机 7", ["resident evil 7"], "418370", tunableReason),
        .tunable("鬼泣 5", ["devil may cry 5"], "601150", tunableReason),
        .tunable("尼尔：机械纪元", ["nier automata", "nier: automata"], "524220", tunableReason),
        .tunable("最终幻想 7 重制版", ["final fantasy vii remake", "final fantasy 7 remake"], "1462040", tunableReason),
        .tunable("最终幻想 16", ["final fantasy xvi", "final fantasy 16"], "2515020", tunableReason),
        .tunable("女神异闻录 5 皇家版", ["persona 5 royal"], "1687950", tunableReason),
        .tunable("如龙 0", ["yakuza 0"], "638970", tunableReason),
        .tunable("如龙 8", ["like a dragon infinite wealth", "如龙8"], "2072450", tunableReason),
        .tunable("上古卷轴 V：天际", ["skyrim"], "489830", tunableReason),
        .tunable("辐射 4", ["fallout 4"], "377160", tunableReason),
        .tunable("星空", ["starfield"], "1716740", tunableReason),
        .tunable("天外世界", ["the outer worlds"], "578650", tunableReason),
        .tunable("质量效应：传奇版", ["mass effect legendary edition"], "1328670", tunableReason),
        .tunable("龙腾世纪：宗教裁判所", ["dragon age inquisition"], "1222690", tunableReason),
        .tunable("刺客信条：奥德赛", ["assassin's creed odyssey"], "812140", tunableReason),
        .tunable("刺客信条：英灵殿", ["assassin's creed valhalla"], "2208920", tunableReason),
        .tunable("刺客信条：幻景", ["assassin's creed mirage"], "", "单机内容没有内核级反作弊。仍要放进 Wine / GPTK 容器。这不是逐款实测结论。"),
        .tunable("孤岛惊魂 5", ["far cry 5"], "552520", tunableReason),
        .tunable("孤岛惊魂 6", ["far cry 6"], "2369390", tunableReason),
        .tunable("看门狗 2", ["watch dogs 2"], "447040", tunableReason),
        .tunable("古墓丽影：崛起", ["rise of the tomb raider"], "391220", tunableReason),
        .tunable("古墓丽影：暗影", ["shadow of the tomb raider"], "750920", tunableReason),
        .tunable("杀手：暗杀世界", ["hitman world of assassination", "hitman 3"], "1659040", "离线任务通常不依赖内核反作弊。联机入侵模式不保证可用。"),
        .tunable("毁灭战士：永恒", ["doom eternal"], "782330", tunableReason),
        .tunable("毁灭战士", ["doom"], "379720", tunableReason),
        .tunable("德军总部：新血脉", ["wolfenstein youngblood"], "1056960", tunableReason),
        .tunable("耻辱 2", ["dishonored 2"], "403640", tunableReason),
        .tunable("死亡循环", ["deathloop"], "1252330", tunableReason),
        .tunable("原子之心", ["atomic heart"], "668580", tunableReason),
        .tunable("遗迹 2", ["remnant ii", "remnant 2"], "1282100", tunableReason),
        .tunable("双人成行", ["it takes two"], "1426210", tunableReason),
        .tunable("英灵神殿", ["valheim"], "892970", tunableReason),
        .tunable("幻兽帕鲁", ["palworld"], "1623730", "专用服务器或单机没有内核级反作弊。官方联机反作弊策略若变更，需要重新评估。"),
        .tunable("幸福工厂", ["satisfactory"], "526870", tunableReason),
        .tunable("怪物猎人：荒野", ["monster hunter wilds"], "2246340", tunableReason),
        .tunable("戴森球计划", ["dyson sphere program"], "1366540", tunableReason),
        .tunable("以撒的结合", ["the binding of isaac rebirth"], "250900", tunableReason),
        .tunable("黑暗之魂 重制版", ["dark souls remastered"], "570940", tunableReason),
        .blocked("血源诅咒", ["bloodborne"], "", "没有官方 PC 或 macOS 版本，Wine 不能直接运行这款主机游戏。"),
        .blocked("对马岛之魂", ["ghost of yotei"], "", "若仍没有 PC 版本，容器里没有可运行的 Windows 构建。"),
        .tunable("剑星", ["stellar blade"], "3489700", tunableReason),
        .tunable("艾尔登法环 黑夜君临", ["elden ring nightreign"], "2622380", "合作模式。若后续要求内核级反作弊，应改为无法运行。当前记录不是逐款实测。"),
        .tunable("双影奇境", ["split fiction"], "2001120", tunableReason),
        .tunable("光与影：33 号远征队", ["clair obscur", "expedition 33"], "1903340", tunableReason),
        .blocked("王国之泪", ["tears of the kingdom", "zelda tears"], "", "任天堂主机游戏没有合法的 macOS 或 Windows 版本。"),
        .blocked("塞尔达传说：旷野之息", ["breath of the wild"], "", "任天堂主机游戏没有合法的 macOS 或 Windows 版本。"),
        .blocked("超级马力欧 奥德赛", ["super mario odyssey"], "", "任天堂主机游戏没有合法的 macOS 或 Windows 版本。"),
        .blocked("宝可梦 朱紫", ["pokemon scarlet", "pokemon violet"], "", "任天堂主机游戏没有合法的 macOS 或 Windows 版本。"),

        .blocked("无畏契约", ["valorant", "瓦罗兰特"], "", vanguard),
        .blocked("英雄联盟", ["league of legends", "lol"], "", "现行客户端使用 Vanguard。旧的 macOS 客户端已经停用，不能再当成原生支持。"),
        .blocked("绝地求生", ["pubg", "battlegrounds"], "578080", battleye),
        .blocked("堡垒之夜", ["fortnite"], "", eac),
        .blocked("Apex 英雄", ["apex legends"], "1172470", eac),
        .blocked("Rust", ["rust"], "252490", eac),
        .blocked("黎明杀机", ["dead by daylight"], "381210", eac),
        .blocked("The Finals", ["the finals"], "2073850", eac),
        .blocked("地狱潜兵 2", ["helldivers 2", "helldivers"], "553850", guardReason),
        .blocked("使命召唤：战区", ["call of duty", "warzone"], "", ricochet),
        .blocked("彩虹六号：围攻", ["rainbow six siege", "rainbow six"], "359550", battleye),
        .blocked("逃离塔科夫", ["escape from tarkov", "tarkov"], "", battleye),
        .blocked("DayZ", ["dayz"], "221100", battleye),
        .blocked("武装突袭 3", ["arma 3"], "107410", battleye),
        .blocked("命运 2", ["destiny 2"], "1085660", battleye),
        .blocked("猎杀：对决", ["hunt showdown", "hunt: showdown"], "594650", eac),
        .blocked("光环：无限", ["halo infinite"], "1240440", eac),
        .blocked("失落的方舟", ["lost ark"], "1599340", eac),
        .blocked("新世界", ["new world"], "1063730", eac),
        .blocked("永劫无间", ["naraka bladepoint", "naraka"], "1203220", "使用自有内核反作弊，Wine 容器无法加载该驱动。"),
        .blocked("战地 2042", ["battlefield 2042", "battlefield"], "1517290", "使用 EA Anti-Cheat。内核组件不能在 Wine 容器里通过校验。"),
        .blocked("EA Sports FC", ["ea sports fc", "fifa"], "", "使用 EA Anti-Cheat，不能在 Wine 容器里运行。"),
        .blocked("原神", ["genshin impact", "genshin"], "", mhy),
        .blocked("崩坏：星穹铁道", ["honkai star rail", "star rail"], "", mhy),
        .blocked("绝区零", ["zenless zone zero"], "", mhy),
        .blocked("鸣潮", ["wuthering waves"], "", "使用自有内核保护，不能在 Wine 容器里加载。"),
        .blocked("三角洲行动", ["delta force"], "", "使用内核级反作弊，不能在 Wine 容器里加载。"),
        .blocked("漫威争锋", ["marvel rivals"], "2767030", "使用在线反作弊，当前没有可用的 macOS 或 Wine 支持。"),
        .blocked("守望先锋 2", ["overwatch 2", "overwatch"], "", "使用暴雪在线反作弊，没有当前可用的 macOS 客户端。"),
        .blocked("Valorant 国服", ["无畏契约国服", "valorant cn"], "", vanguard),
        .blocked("深岩银河", ["deep rock galactic"], "548430", eac),
        .blocked("战锤 40K：暗潮", ["warhammer 40000 darktide", "darktide"], "1361210", eac),
        .blocked("PUBG 手游模拟器", ["gameloop", "pubg mobile"], "", "安卓模拟器和内核反作弊都不在 Vesta 的支持范围内。")
    ]
}
