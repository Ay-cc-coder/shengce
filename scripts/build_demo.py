#!/usr/bin/env python3
"""Build the fictional demo recordings with macOS voices.

Run on macOS: python3 scripts/build_demo.py
The generated m4a files and manifests are committed so the Docker image does
not need a TTS engine.
"""
from __future__ import annotations

import audioop
import json
import math
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MEDIA = ROOT / "demo" / "media"
DATA = ROOT / "demo" / "data"
RATE = 22050

VOICES = {
    "我": "Reed (中文（中国大陆）)",
    "陈岚": "Tingting",
    "周启明": "Eddy (中文（中国大陆）)",
    "妈妈": "Meijia",
    "林舟": "Flo (中文（中国大陆）)",
    "孙师傅": "Rocko (中文（中国大陆）)",
    "吴姐": "Flo (中文（中国大陆）)",
}

SCENARIOS = [
    {
        "slug": "chen-lan-cabinet",
        "kind": "call",
        "contact": "陈岚",
        "phone": "13800138024",
        "title": "橱柜复尺与台面颜色",
        "days_ago": 3,
        "time": "19:42",
        "topics": ["装修", "家居"],
        "summary": "陈岚确认明天下午三点半师傅上门复尺；台面颜色要在周五前定下，你倾向浅灰；另外需要量水槽尺寸并拍照发给她。",
        "key_points": [
            "明天下午三点半，复尺师傅从地下车库上门。",
            "台面颜色要在周五前定下，你在浅灰和米白之间倾向浅灰。",
            "还要量水槽尺寸，并把目前台面颜色拍照发给陈岚。",
        ],
        "lines": [
            ("陈岚", "喂，是我。明天下午师傅过去复尺，你在家吗？"),
            ("我", "在，明天下午我尽量早点回来。大概几点到？"),
            ("陈岚", "他说三点半左右，从地下车库上来。你把现在台面的颜色拍一张发我。"),
            ("我", "行，我晚上拍给你。台面颜色是不是还要再定一下？"),
            ("陈岚", "对，周五之前得定下来，不然工厂排不上。你倾向浅灰还是米白？"),
            ("我", "浅灰吧，和柜门更搭。周五前我给你准信。"),
            ("陈岚", "好，那我把色卡明天带过去。还有水槽的尺寸也量一下。"),
            ("我", "好，我记下了，明天一起量。"),
        ],
        "actions": [
            {"text": "明天下午在家等复尺师傅", "line_index": 0, "priority": "high", "due_rule": {"type": "offset", "days": 1, "time": "15:30"}},
            {"text": "把台面颜色拍照发给陈岚", "line_index": 2, "priority": "high", "due_rule": {"type": "offset", "days": 0, "time": "21:00"}},
            {"text": "周五前确认台面颜色", "line_index": 4, "priority": "high", "due_rule": {"type": "weekday", "weekday": 4, "time": "18:00", "before": True}},
            {"text": "量水槽尺寸并发给陈岚", "line_index": 6, "priority": "normal", "due_rule": {"type": "weekday", "weekday": 4, "time": "18:00", "before": True}},
        ],
    },
    {
        "slug": "zhou-qiming-quote",
        "kind": "call",
        "contact": "周启明",
        "phone": "13911226508",
        "title": "修改报价与合同用印",
        "days_ago": 1,
        "time": "10:08",
        "topics": ["工作", "合同与财务"],
        "summary": "周启明认可报价整体方案，要求人工费下调约三个点；修改后的报价单要在明天下午三点前发他，交付仍按十号前进场，周五上午安排合同用印。",
        "key_points": [
            "第二项人工费偏高，按工时核减约三个点。",
            "修改后的报价单明天下午三点前发给周启明走审批。",
            "十号之前必须进场，合同用印安排在周五上午。",
        ],
        "lines": [
            ("周启明", "早，报价单我看了。整体没问题，就是第二项的人工费高了点。"),
            ("我", "我也觉得，昨天核了一遍。按现在的工时，大概能降三个点。"),
            ("周启明", "行，那你把修改后的版本明天下午三点前发我，我拿去走审批。"),
            ("我", "没问题。交付日期还是按原计划，下个月十号？"),
            ("周启明", "对，十号之前必须进场。合同用印我这边周五上午能安排。"),
            ("我", "好，那我把用印时间写进邮件。还有别的要改吗？"),
            ("周启明", "暂时没有。你把报价、排期和用印时间整理成一页发我就行。"),
            ("我", "明白，明天下午三点前给你。"),
        ],
        "actions": [
            {"text": "明天三点前发修改后的报价单", "line_index": 2, "priority": "high", "due_rule": {"type": "offset", "days": 1, "time": "15:00"}},
            {"text": "整理一页报价、排期和用印时间", "line_index": 6, "priority": "high", "due_rule": {"type": "offset", "days": 1, "time": "15:00"}},
            {"text": "确认周五上午合同用印时间", "line_index": 4, "priority": "medium", "due_rule": {"type": "weekday", "weekday": 4, "time": "10:00"}},
        ],
    },
    {
        "slug": "mama-checkup",
        "kind": "call",
        "contact": "妈妈",
        "phone": "13701829033",
        "title": "妈妈体检报告与复诊",
        "days_ago": 2,
        "time": "20:15",
        "topics": ["家庭", "健康"],
        "summary": "妈妈的体检报告显示血脂偏高，医生要求周四上午九点取纸质报告并复诊；你答应陪她去，周日再回家吃饭。",
        "key_points": [
            "体检其他指标正常，血脂偏高。",
            "周四上午九点取报告并复诊，你请假陪同。",
            "周日中午回家吃饭，爸爸买了螃蟹。",
        ],
        "lines": [
            ("妈妈", "吃饭了没有？我跟你说，体检报告出来了。"),
            ("我", "刚吃完。报告怎么样，医生怎么说？"),
            ("妈妈", "别的都还好，就是血脂有点高。医生让周四上午去拿纸质报告，再挂个复诊。"),
            ("我", "周四上午几点？我请个假陪你去。"),
            ("妈妈", "九点。你要忙就不用跑，我自己能行。"),
            ("我", "没事，我陪你去。你把身份证和医保卡放包里。"),
            ("妈妈", "好。周日你回来吃饭吗？你爸买了螃蟹。"),
            ("我", "回，周日上午我过去。报告的事我来记着。"),
        ],
        "actions": [
            {"text": "周四上午九点陪妈妈取报告复诊", "line_index": 3, "priority": "high", "due_rule": {"type": "weekday", "weekday": 3, "time": "09:00"}},
            {"text": "提醒妈妈带身份证和医保卡", "line_index": 5, "priority": "medium", "due_rule": {"type": "weekday", "weekday": 3, "time": "08:30"}},
            {"text": "周日上午回家吃饭", "line_index": 6, "priority": "low", "due_rule": {"type": "weekday", "weekday": 6, "time": "11:30"}},
        ],
    },
    {
        "slug": "lin-zhou-dental",
        "kind": "call",
        "contact": "林舟",
        "phone": "13601678215",
        "title": "洗牙预约与麻药备注",
        "days_ago": 4,
        "time": "15:26",
        "topics": ["健康"],
        "summary": "林医生诊所帮你约了周三上午十点洗牙，时长约四十分钟；需要带医保卡，并备注对麻药敏感，本次不做深层清洁。",
        "key_points": [
            "周三上午十点洗牙，检查加清洁约四十分钟。",
            "需要带医保卡。",
            "对麻药敏感，本次先不做深层清洁。",
        ],
        "lines": [
            ("林舟", "你好，这里是林医生诊所。你上次洗牙的时间到了，帮你约一下？"),
            ("我", "对，最近正好想约。这周三上午还有位置吗？"),
            ("林舟", "周三上午十点有一个，洗牙加检查大概四十分钟。"),
            ("我", "可以，就周三十点。需要带什么吗？"),
            ("林舟", "带医保卡就行。你上次说对麻药有点敏感，这次先不做深层清洁。"),
            ("我", "好，记得帮我备注一下。"),
        ],
        "actions": [
            {"text": "周三上午十点去洗牙并带医保卡", "line_index": 2, "priority": "high", "due_rule": {"type": "weekday", "weekday": 2, "time": "10:00"}},
            {"text": "确认诊所已备注麻药敏感", "line_index": 5, "priority": "normal", "due_rule": {"type": "weekday", "weekday": 1, "time": "18:00"}},
        ],
    },
    {
        "slug": "sun-ac-repair",
        "kind": "call",
        "contact": "孙师傅",
        "phone": "13501983726",
        "title": "空调不制冷上门维修",
        "days_ago": 5,
        "time": "09:12",
        "topics": ["生活服务"],
        "summary": "孙师傅周六下午两点到四点上门修空调，需要你提前拍外机型号给他；家里留人即可，不用断电。",
        "key_points": [
            "周六下午两点到四点之间上门。",
            "提前拍外机型号发给孙师傅。",
            "家里留人，不用提前断电。",
        ],
        "lines": [
            ("孙师傅", "我是修空调的孙师傅。你昨天报的那个不制冷，我周六下午过去看。"),
            ("我", "好，周六下午几点？我安排一下时间。"),
            ("孙师傅", "两点到四点之间。你把外机型号拍给我，我先看看是不是主板的问题。"),
            ("我", "行，我中午拍给你。需要提前把电断了吗？"),
            ("孙师傅", "不用，我到了再弄。家里有人就行。"),
            ("我", "好，那周六下午我在家等您。"),
        ],
        "actions": [
            {"text": "周六下午在家等孙师傅修空调", "line_index": 0, "priority": "high", "due_rule": {"type": "weekday", "weekday": 6, "time": "14:00"}},
            {"text": "中午前拍外机型号发给孙师傅", "line_index": 2, "priority": "medium", "due_rule": {"type": "weekday", "weekday": 6, "time": "12:00"}},
        ],
    },
    {
        "slug": "wu-invoice",
        "kind": "call",
        "contact": "吴姐",
        "phone": "13917652048",
        "title": "补开发票与开票信息",
        "days_ago": 6,
        "time": "16:05",
        "topics": ["合同与财务", "工作"],
        "summary": "吴姐确认月底前补开发票，需要你提供抬头、税号和项目名称；发票按合同全额开具，项目写技术服务费。",
        "key_points": [
            "发票在月底前补开。",
            "提供抬头、税号和项目名称。",
            "按合同全额开，项目写技术服务费。",
        ],
        "lines": [
            ("吴姐", "小陈，上次那笔款收到了。发票这边我月底前给你补开。"),
            ("我", "好，需要我把抬头和税号再发你一遍吗？"),
            ("吴姐", "对，你发我一下。还有项目名称，写技术服务费就行。"),
            ("我", "行，我这就发。金额是按合同全额开吗？"),
            ("吴姐", "对，全额。开好我发你电子版。"),
            ("我", "好，麻烦吴姐了。"),
        ],
        "actions": [
            {"text": "把抬头、税号和项目名称发给吴姐", "line_index": 1, "priority": "high", "due_rule": {"type": "offset", "days": 0, "time": "17:00"}},
            {"text": "月底前确认收到电子发票", "line_index": 4, "priority": "normal", "due_rule": {"type": "offset", "days": 4, "time": "18:00"}},
        ],
    },
    {
        "slug": "chen-lan-sink",
        "kind": "call",
        "contact": "陈岚",
        "phone": "13800138024",
        "title": "改大单槽与周末看样",
        "days_ago": 9,
        "time": "11:20",
        "topics": ["装修"],
        "summary": "陈岚想把水槽改成大单槽，约你周六下午看样；需要先量现有水槽尺寸发她，让工厂重算，颜色仍为浅灰，周末一起选龙头。",
        "key_points": [
            "水槽改成大单槽，会影响台下盆尺寸。",
            "今晚量现有水槽尺寸发给陈岚。",
            "周六下午看样，顺便把龙头定下来。",
        ],
        "lines": [
            ("陈岚", "水槽那边我想改成大单槽，你周末有空去看样吗？"),
            ("我", "可以，周六下午去。大单槽会不会影响台下盆的尺寸？"),
            ("陈岚", "会，所以得先定型号。你把现在的水槽尺寸量给我，我让工厂重新算。"),
            ("我", "好，今晚量了发你。颜色还是浅灰吗？"),
            ("陈岚", "对，浅灰。你顺便看看龙头，周末一起定。"),
        ],
        "actions": [
            {"text": "今晚量水槽尺寸发给陈岚", "line_index": 2, "priority": "high", "due_rule": {"type": "offset", "days": 0, "time": "20:00"}},
            {"text": "周六下午看水槽和龙头样品", "line_index": 0, "priority": "medium", "due_rule": {"type": "weekday", "weekday": 6, "time": "15:00"}},
        ],
    },
    {
        "slug": "zhou-qiming-delivery",
        "kind": "call",
        "contact": "周启明",
        "phone": "13911226508",
        "title": "交付延期与尺寸变更",
        "days_ago": 12,
        "time": "17:30",
        "topics": ["工作", "装修"],
        "summary": "客户需求又改了一版，交付可能从下周一到周三；周启明今晚与客户确认，明天上午给准信，你先把排期改为待定并更新展厅墙面尺寸图。",
        "key_points": [
            "交付时间可能从下周一到周三。",
            "周启明今晚确认，明天上午给准信。",
            "排期先改待定，展厅墙面尺寸图要更新。",
        ],
        "lines": [
            ("周启明", "客户那边把需求又改了一版，交付时间可能要往后挪。"),
            ("我", "挪到什么时候？原计划下周一进场，工人已经排好了。"),
            ("周启明", "先按周三吧，我今晚跟客户确认，明天上午给你准信。"),
            ("我", "行，那我先把排期改成待定，等你消息再通知工人。"),
            ("周启明", "好。改动不大，主要是展厅那面墙的尺寸。"),
            ("我", "明白，尺寸图我这边也更新一下。"),
        ],
        "actions": [
            {"text": "等明天上午的准信再通知工人排期", "line_index": 3, "priority": "high", "due_rule": {"type": "offset", "days": 1, "time": "12:00"}},
            {"text": "更新展厅墙面尺寸图", "line_index": 5, "priority": "medium", "due_rule": {"type": "offset", "days": 2, "time": "18:00"}},
        ],
    },
    {
        "slug": "mama-weekend",
        "kind": "call",
        "contact": "妈妈",
        "phone": "13701829033",
        "title": "周日家庭聚餐",
        "days_ago": 15,
        "time": "19:05",
        "topics": ["家庭"],
        "summary": "妈妈让你周日中午回家吃饭，表妹也会来；你尽量十一点半到，她还让你劝爸爸少干点活。",
        "key_points": [
            "周日中午十二点吃饭，表妹也来。",
            "你尽量十一点半到。",
            "爸爸腰不舒服，妈妈让你劝他少干活。",
        ],
        "lines": [
            ("妈妈", "周日你表妹过来，你有空就回来一起吃个饭。"),
            ("我", "周日几点？我上午可能要去一趟公司。"),
            ("妈妈", "中午十二点。你忙完再过来也行，给你留菜。"),
            ("我", "好，我尽量十一点半到。需要我带什么吗？"),
            ("妈妈", "不用，人来就行。你爸最近腰不舒服，你回来劝劝他少干点活。"),
        ],
        "actions": [
            {"text": "周日上午回家吃饭并劝爸爸少干活", "line_index": 3, "priority": "low", "due_rule": {"type": "weekday", "weekday": 6, "time": "11:30"}},
        ],
    },
    {
        "slug": "lin-zhou-review",
        "kind": "call",
        "contact": "林舟",
        "phone": "13601678215",
        "title": "补牙复查",
        "days_ago": 18,
        "time": "14:10",
        "topics": ["健康"],
        "summary": "补牙位置恢复良好但咬硬物发酸，林医生约你下周二下午三点半复查咬合，直接到诊所即可。",
        "key_points": [
            "补牙位置不疼了，咬硬物发酸。",
            "下周二下午三点半复查咬合。",
            "直接到诊所，不用提前挂号。",
        ],
        "lines": [
            ("林舟", "你上次补牙的位置还疼吗？"),
            ("我", "不疼了，就是咬硬东西有点酸。"),
            ("林舟", "那下周二下午来复查一下，我看看咬合。三点以后都可以。"),
            ("我", "好，我约下周二三点半。"),
            ("林舟", "行，我给你记上。到时候直接过来就行。"),
        ],
        "actions": [
            {"text": "下周二下午三点半去复查咬合", "line_index": 2, "priority": "medium", "due_rule": {"type": "weekday", "weekday": 1, "time": "15:30"}},
        ],
    },
    {
        "slug": "chen-lan-swatches",
        "kind": "call",
        "contact": "陈岚",
        "phone": "13800138024",
        "title": "取色卡与柜门对比",
        "days_ago": 22,
        "time": "10:30",
        "topics": ["装修"],
        "summary": "陈岚把色卡放在物业前台，让你中午去拿；共浅灰、米白、暖白三色，今晚对比柜门后拍照给她。",
        "key_points": [
            "色卡在物业前台，中午去拿。",
            "三个颜色：浅灰、米白、暖白。",
            "今晚对比柜门后拍照发给陈岚。",
        ],
        "lines": [
            ("陈岚", "色卡我放物业前台了，你路过拿一下。"),
            ("我", "好，我中午去拿。还是那三个颜色吗？"),
            ("陈岚", "对，浅灰、米白和暖白。你拿回家对比一下柜门。"),
            ("我", "行，我今晚对比完拍给你。"),
        ],
        "actions": [
            {"text": "中午去物业前台拿色卡", "line_index": 0, "priority": "high", "due_rule": {"type": "offset", "days": 0, "time": "12:00"}},
            {"text": "今晚对比柜门颜色并拍照", "line_index": 3, "priority": "medium", "due_rule": {"type": "offset", "days": 0, "time": "21:00"}},
        ],
    },
    {
        "slug": "voice-monday-meeting",
        "kind": "voice",
        "contact": None,
        "title": "周一晨会四件事",
        "days_ago": 0,
        "time": "08:36",
        "topics": ["工作"],
        "summary": "周一晨会安排了四件事：十点前发周报、两点前确认合同盖章、今天约好周五客户来访的会议室和设备、下午四点跟周启明确认报价修改版。",
        "key_points": [
            "上午十点前发周报给陈岚。",
            "下午两点前确认合同盖章。",
            "今天约好周五客户来访的会议室和设备。",
            "下午四点跟周启明确认报价修改版。",
        ],
        "lines": [
            ("我", "周一晨会记一下。第一，周报上午十点前发给陈岚，把上周的交付和风险写清楚。"),
            ("我", "第二，合同盖章下午两点前找行政确认，法务那边还差一页附件。"),
            ("我", "第三，周五客户来访，今天要把会议室和演示设备约好。"),
            ("我", "还有，下午四点跟周启明确认报价修改版，别忘了。"),
        ],
        "actions": [
            {"text": "上午十点前把周报发给陈岚", "line_index": 0, "priority": "high", "due_rule": {"type": "offset", "days": 0, "time": "10:00"}},
            {"text": "下午两点前找行政确认合同盖章", "line_index": 1, "priority": "high", "due_rule": {"type": "offset", "days": 0, "time": "14:00"}},
            {"text": "约好周五客户来访的会议室和设备", "line_index": 2, "priority": "high", "due_rule": {"type": "offset", "days": 0, "time": "18:00"}},
            {"text": "下午四点确认报价修改版", "line_index": 3, "priority": "high", "due_rule": {"type": "offset", "days": 0, "time": "16:00"}},
        ],
    },
    {
        "slug": "voice-renovation-size",
        "kind": "voice",
        "contact": None,
        "title": "阳台尺寸与插座位置",
        "days_ago": 1,
        "time": "22:08",
        "topics": ["装修", "家居"],
        "summary": "语音备忘记录了阳台净宽一米四二、深度六十，洗衣机放左边；客厅要加三个插座，厨房灯光改为四千K；明天把尺寸发给陈岚并确认台面开孔位置。",
        "key_points": [
            "阳台净宽一米四二，深度六十，洗衣机放左边。",
            "客厅加三个插座：沙发两边各一个，电视柜后面一个。",
            "厨房灯光改为四千K，不要暖黄。",
            "明天把尺寸发给陈岚，确认台面开孔位置。",
        ],
        "lines": [
            ("我", "记一下今天的尺寸。阳台净宽是一米四二，深度六十，洗衣机放左边。"),
            ("我", "客厅插座要加三个，沙发两边各一个，电视柜后面一个。"),
            ("我", "明天记得把尺寸发给陈岚，顺便问一下台面开孔的位置。"),
            ("我", "还有，厨房灯光换成四千K，不要暖黄。"),
        ],
        "actions": [
            {"text": "把阳台尺寸发给陈岚并确认开孔位置", "line_index": 2, "priority": "high", "due_rule": {"type": "offset", "days": 1, "time": "10:00"}},
            {"text": "买三个插座面板", "line_index": 1, "priority": "medium", "due_rule": {"type": "offset", "days": 2, "time": "18:00"}},
        ],
    },
]


ACTION_OVERRIDES = {
    ("chen-lan-cabinet", "把台面颜色拍照发给陈岚"): {"done": True},
    ("chen-lan-cabinet", "量水槽尺寸并发给陈岚"): {"done": True},
    ("zhou-qiming-quote", "整理一页报价、排期和用印时间"): {"done": True},
    ("mama-checkup", "周日上午回家吃饭"): {"done": True},
    ("lin-zhou-dental", "确认诊所已备注麻药敏感"): {"done": True},
    ("sun-ac-repair", "中午前拍外机型号发给孙师傅"): {"done": True},
    ("chen-lan-sink", "今晚量水槽尺寸发给陈岚"): {"done": True},
    ("zhou-qiming-delivery", "等明天上午的准信再通知工人排期"): {"done": True},
    ("zhou-qiming-delivery", "更新展厅墙面尺寸图"): {"done": True},
    ("mama-weekend", "周日上午回家吃饭并劝爸爸少干活"): {"done": True},
    ("lin-zhou-review", "下周二下午三点半去复查咬合"): {"done": True},
    ("chen-lan-swatches", "中午去物业前台拿色卡"): {"done": True},
    ("chen-lan-swatches", "今晚对比柜门颜色并拍照"): {"done": True},
    ("wu-invoice", "把抬头、税号和项目名称发给吴姐"): {
        "done": False,
        "due_rule": {"type": "offset", "days": -1, "time": "17:00"},
    },
    ("voice-renovation-size", "买三个插座面板"): {"due_rule": {}},
}


def apply_overrides(scenario: dict) -> None:
    for action in scenario["actions"]:
        override = ACTION_OVERRIDES.get((scenario["slug"], action["text"]))
        if override:
            action.update(override)


for _scenario in SCENARIOS:
    apply_overrides(_scenario)


def read_wav(path: Path) -> tuple[bytes, int, int, int]:
    with wave.open(str(path), "rb") as handle:
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        rate = handle.getframerate()
        frames = handle.readframes(handle.getnframes())
    return frames, channels, width, rate


def silence(seconds: float) -> bytes:
    return b"\x00\x00" * int(RATE * seconds)


def peaks_from_wav(path: Path, bars: int = 96) -> list[int]:
    with wave.open(str(path), "rb") as handle:
        frames = handle.readframes(handle.getnframes())
        width = handle.getsampwidth()
    step = 2048
    values = []
    for offset in range(0, len(frames), step):
        chunk = frames[offset : offset + step]
        if len(chunk) < width:
            continue
        try:
            values.append(audioop.rms(chunk, width))
        except Exception:
            values.append(0)
    if not values:
        return [0] * bars
    ceiling = sorted(values)[int(len(values) * 0.96)] or max(values) or 1
    result = []
    for index in range(bars):
        left = int(len(values) * index / bars)
        right = max(left + 1, int(len(values) * (index + 1) / bars))
        bucket = values[left:right] or [0]
        ratio = min(1.0, (sum(bucket) / len(bucket)) / ceiling)
        result.append(int(round(math.sqrt(ratio) * 100)))
    return result


def build_one(scenario: dict) -> dict:
    lines = scenario["lines"]
    output_frames = bytearray(silence(0.28))
    segments = []
    cursor = 0.28
    with tempfile.TemporaryDirectory(prefix="shengce-tts-") as tmp:
        tmp_dir = Path(tmp)
        for index, (speaker, text) in enumerate(lines):
            aiff = tmp_dir / f"line-{index}.aiff"
            line_wav = tmp_dir / f"line-{index}.wav"
            voice = VOICES.get(speaker, VOICES["我"])
            subprocess.run(
                ["say", "-v", voice, "-r", "180", "-o", str(aiff), text],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
            )
            subprocess.run(
                ["afconvert", "-f", "WAVE", "-d", "LEI16@22050", str(aiff), str(line_wav)],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
            )
            frames, channels, width, rate = read_wav(line_wav)
            if channels != 1 or width != 2 or rate != RATE:
                raise RuntimeError(f"unexpected audio format {channels}/{width}/{rate}")
            duration = len(frames) / (RATE * 2)
            start = cursor
            end = start + duration
            segments.append(
                {
                    "speaker": "me" if scenario["kind"] == "voice" else ("1" if speaker != "我" else "2"),
                    "start": round(start, 2),
                    "end": round(end, 2),
                    "text": text,
                }
            )
            output_frames.extend(frames)
            pause = 0.52 if index < len(lines) - 1 else 0.35
            output_frames.extend(silence(pause))
            cursor = end + pause
        wav_path = tmp_dir / "demo.wav"
        with wave.open(str(wav_path), "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(RATE)
            handle.writeframes(bytes(output_frames))
        peaks = peaks_from_wav(wav_path)
        m4a_path = tmp_dir / "demo.m4a"
        subprocess.run(
            ["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", str(wav_path), str(m4a_path)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        destination = MEDIA / f"{scenario['slug']}.m4a"
        shutil.copy2(m4a_path, destination)

    duration = len(output_frames) / (RATE * 2)
    manifest = {
        "slug": scenario["slug"],
        "kind": scenario["kind"],
        "contact": scenario.get("contact"),
        "phone": scenario.get("phone"),
        "title": scenario["title"],
        "days_ago": scenario["days_ago"],
        "time": scenario["time"],
        "topics": scenario["topics"],
        "summary": scenario["summary"],
        "key_points": scenario["key_points"],
        "actions": scenario["actions"],
        "speakers": (
            {"1": scenario["contact"], "2": "我"}
            if scenario["kind"] == "call"
            else {"me": "我"}
        ),
        "audio": destination.name,
        "duration": round(duration, 2),
        "waveform": peaks,
        "segments": segments,
    }
    (DATA / f"{scenario['slug']}.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return manifest


def main() -> None:
    MEDIA.mkdir(parents=True, exist_ok=True)
    DATA.mkdir(parents=True, exist_ok=True)
    for index, scenario in enumerate(SCENARIOS, start=1):
        manifest = build_one(scenario)
        print(
            f"[{index:02d}/{len(SCENARIOS)}] {scenario['slug']} "
            f"{manifest['duration']:.1f}s {len(manifest['segments'])} turns"
        )


if __name__ == "__main__":
    main()
