--[[
  Today's ventures for VenGo. Rotates at JST midnight (10:00 AM Central).
  Update from catseyexi.com/events, then click "Reload" in the VenGo window.

  EXP / HVNM fields:
    key      : shorthand (/vengo b4)
    tier     : tier number        levels : level range text
    zone     : FFXI zone ID (tells VenGo whether you're in the right zone)
    zone_name: display name       nm     : VNM name as it appears in game
    grid     : map square         progress: server progress %
    map      : (optional) which map of a multi-map dungeon the grid is on, e.g. map=3
]]

return {
    hvnm = {
        key='hvnm', zone=105, zone_name='Batallia Downs', nm='Tidepincher', grid='J-6',
        progress=59, level=75, hp=500000, next_up='Emberwing', aliases={'hv'},
        loot={ 'Furys Edge', 'Pincer Mantle', 'Water V', 'Thunder V', 'Kupo Nut' },
    },

    exp = {
        -- Pool A (classic zones)
        { key='a1', tier=1, levels='10-19', zone=104, zone_name='Jugner Forest',          nm='Forest Prowler',  grid='F-8',  progress=58 },
        { key='a2', tier=2, levels='20-29', zone=120, zone_name='Sauromugue Champaign',   nm='Feral Feline',    grid='L-7',  progress=67 },
        { key='a3', tier=3, levels='30-39', zone=197, zone_name="Crawlers' Nest",         nm='Monarch Crawler', grid='J-7',  progress=18, map=3 },
        { key='a4', tier=4, levels='40-49', zone=169, zone_name='Toraimarai Canal',       nm='Depth Lurker',    grid='I-6',  progress=1  },
        { key='a5', tier=5, levels='50-59', zone=5,   zone_name='Uleguerand Range',       nm='Icehoof',         grid='G-10', progress=64 },
        { key='a6', tier=6, levels='60-69', zone=153, zone_name='The Boyahda Tree',       nm='Ancient Wyrm',    grid='J-8',  progress=5  },
        -- Pool B (ToAU / WotG zones)
        { key='b1', tier=1, levels='10-19', zone=81,  zone_name='East Ronfaure [S]',      nm='Ironhorn Ram',    grid='G-9',  progress=86 },
        { key='b2', tier=2, levels='20-29', zone=52,  zone_name='Bhaflau Thickets',       nm='Swift Stalker',   grid='H-9',  progress=68 },
        { key='b3', tier=3, levels='30-39', zone=96,  zone_name='Fort Karugo-Narugo [S]', nm='Dire Rafflesia',  grid='G-5',  progress=73 },
        { key='b4', tier=4, levels='40-49', zone=164, zone_name='Garlaige Citadel [S]',   nm='Citadel Ooze',    grid='I-7',  progress=70 },
        { key='b5', tier=5, levels='50-59', zone=52,  zone_name='Bhaflau Thickets',       nm='Vile Vine',       grid='H-7',  progress=0  },
        { key='b6', tier=6, levels='60-69', zone=61,  zone_name='Mount Zhayolm',          nm='Magma Piercer',   grid='M-6',  progress=67 },
    },

    helm = {
        { kind='Harvesting', zones='West Sarutabaruta, West Sarutabaruta [S], Bhaflau Thickets' },
        { kind='Excavation', zones='Tahrongi Canyon, Maze of Shakhrami, Arrapago Reef' },
        { kind='Logging',    zones='Buburimu Peninsula, Jugner Forest, Caedarva Mire' },
        { kind='Mining',     zones='Palborough Mines, North Gustaberg [S], Mount Zhayolm' },
    },

    fishing = {
        { tier=1, levels='0-19',   fish='Quus',          count=18 },
        { tier=2, levels='20-39',  fish='Giant Catfish', count=10 },
        { tier=3, levels='40-59',  fish='Zafmlug Bass',  count=14 },
        { tier=4, levels='60-79',  fish='Tavnazian Goby', count=12 },
        { tier=5, levels='80-99',  fish='Dil',           count=12 },
        { tier=6, levels='100+',   fish='Ryugu Titan',   count=6  },
    },

    dynamis = {
        { kind='Cities', zone='Dynamis - Jeuno' },
    },
};
