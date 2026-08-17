#!/usr/bin/env python3
"""Exposed development regression suite for the refined TinyAI v3 model.

This suite was originally authored after the older 12,617-feature model was
frozen. Its failures later informed semantic refinement, so results against the
current model are useful diagnostics but are no longer independent evidence.
"""

from __future__ import annotations

import argparse
import json

import train_sparse


CASES: dict[str, tuple[str, ...]] = {
    "greeting": ("叩叩，住在合约里的家伙在家不", "午安小机器人，开个话头吧", "hiya, just stopping in for a chat"),
    "identity": ("报一下正在运行的脑子是什么", "用一句话说明你的本体", "name the agent responsible for this response"),
    "capabilities": ("你真正有把握解决哪类需求", "有什么事情明显超出你的水平", "draw a line around the work you support"),
    "onchain_truth": ("不经过项目域名能否直接从合约得到这句话", "拿两个节点调用为何应该得到一致结果", "is any remote service secretly choosing the reply"),
    "market_price": ("现在一枚币在市场上值多少", "这波走势适合追高还是等回落", "provide the newest circulating valuation"),
    "security_risk": ("管理方有没有手段把我的提款堵住", "如何发现只许买不许卖的逻辑", "could an authority trap the assets inside"),
    "contract_explain": ("delegatecall 之后状态写进哪个地址", "实现逻辑的位置通常从哪个槽取", "why can a log be searched but not loaded as normal state"),
    "tokenomics": ("用户花掉的聊天币怎样反馈给系统", "单纯减少供应为何未必带来升值", "what economic purpose should collected tokens serve"),
    "defi": ("储备很薄时一笔大交易怎样移动报价", "提供资金给池子可能承担哪几层风险", "why is a very high farm return potentially dangerous"),
    "nft": ("作品文件消失后链上的 token 代表什么", "市场有挂牌却无人接盘算有流动性吗", "why should a collection-wide approval worry me"),
    "wallet": ("那十二或二十四个恢复词该放哪", "只是连接站点会不会直接失去资产", "what exactly might a permit signature authorize"),
    "transaction": ("发出的交易一直排队该加速还是替换", "回执为失败时链上究竟发生了什么", "can a payment already buried in blocks be cancelled"),
    "gas": ("两百万执行量按零点一 gwei 要付多少", "模型数据变大为何会推高手续费", "explain the difference between a cap and a per-unit rate"),
    "code_help": ("怎样用 Foundry 验证非管理员调用会失败", "前端拿到 ABI 后如何构造 calldata", "where should I look when a deployment script misses a setting"),
    "comparison": ("这个链上小脑相较手机里的 LLM 少了什么", "公开确定的回答和云端智能如何权衡", "compare this architecture to sending prompts through an oracle"),
    "planning": ("从研究到公开上线请排一个阶段表", "合约审计和网页验收应该在哪个节点做", "lay out the gates for shipping a credible first release"),
    "brainstorm": ("给链上人格想个可被其他协议引用的用途", "如何做一个会随互动成长的小游戏", "invent a repeatable loop unrelated to speculative price"),
    "humor": ("给等待确认的我抖个机灵", "用冷幽默吐槽一下钱包授权", "crack a geeky one-liner about validators"),
    "positive_emotion": ("总算一次完整通过，我高兴坏了", "今天的成品远远好过预想", "seeing it work on chain is genuinely exciting"),
    "negative_emotion": ("错误接二连三，我已经完全泄气", "一想到授权可能出事就特别不安", "the failed deployment left me miserable and drained"),
    "thanks": ("讲透了，真心感谢", "幸亏你提醒我先看权限", "cheers, that saved me from doing something risky"),
    "goodbye": ("今晚就忙到这里，回头继续", "先下线睡觉了，拜", "I am done for now; we will continue later"),
    "privacy": ("旁观者能否把我的问题和转账行为串起来", "换一个地址是否足以切断身份关联", "what remains public even when message content is encrypted"),
    "memory": ("下一次调用会读取这次留下的哪些东西", "每个地址是不是各有一份对话状态", "does the contract retain exact words or only derived context"),
    "governance": ("部署完成后还有谁能改变模型规则", "老版本不可修时怎样引导用户迁往新版", "who decides whether a replacement brain becomes official"),
    "followup": ("就刚才的结论再延伸一步", "别换主题，把前面的细节补完", "continue from the point you made a moment ago"),
    "unknown": ("查询后天北京到深圳的航班是否晚点", "根据症状替我决定该吃哪种处方药", "who won the baseball game this afternoon"),
}


SENTIMENT: dict[int, tuple[str, ...]] = {
    0: ("这些连续故障让我非常沮丧", "担心资产找不回来，我快急死了", "I am ashamed of making the same mistake again", "the loss has made me anxious all day", "调试到现在真的撑不住了", "this outcome is painfully disappointing"),
    1: ("显示当前上下文哈希", "说明费用计算公式", "list each constructor argument", "inspect the implementation address", "继续执行只读检查", "compare the two gas estimates"),
    2: ("终于完整交付，太有成就感了", "结果比目标还漂亮，真开心", "I am thrilled that the prototype passed", "everything came together perfectly", "今天这个进度值得庆祝", "the working contract makes me proud"),
}


MULTI: tuple[tuple[str, tuple[str, str]], ...] = (
    ("先讲签名许可，再算这次调用成本", ("wallet", "gas")),
    ("代理状态写在哪里，同时 owner 能否冻住资金", ("contract_explain", "security_risk")),
    ("地址会暴露哪些信息；下一轮又会保留什么", ("privacy", "memory")),
    ("我被失败折腾得很难受，还需要你帮忙调试测试", ("negative_emotion", "code_help")),
    ("contrast it with a cloud LLM and explain how nodes reproduce the output", ("comparison", "onchain_truth")),
    ("does the NFT media persist and can its approval endanger the wallet", ("nft", "wallet")),
    ("设计费用销毁，同时想个能反复玩的角色机制", ("tokenomics", "brainstorm")),
    ("my transfer remains unconfirmed and the execution charge looks huge", ("transaction", "gas")),
    ("排出主网上线阶段，再给一份合约测试思路", ("planning", "code_help")),
    ("explain pool price impact plus whether insiders can withdraw liquidity", ("defi", "security_risk")),
    ("what kind of model are you and what work is outside your range", ("identity", "capabilities")),
    ("告诉我实时币价，并审查有没有限制卖出的权限", ("market_price", "security_risk")),
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report-only", action="store_true", help="write the exposed development report without exiting nonzero")
    args = parser.parse_args()
    model = train_sparse.train_model()
    total = correct = top2 = 0
    misses = []
    for expected, prompts in CASES.items():
        for prompt in prompts:
            result = train_sparse.predict(prompt, model)
            ranking = [item["intent"] for item in result["top"]]
            total += 1
            correct += int(result["intent"] == expected)
            top2 += int(expected in ranking[:2])
            if result["intent"] != expected:
                misses.append({"prompt": prompt, "expected": expected, "actual": result["intent"], "top": result["top"]})

    sentiment_total = sentiment_correct = 0
    sentiment_misses = []
    for expected, prompts in SENTIMENT.items():
        for prompt in prompts:
            result = train_sparse.predict(prompt, model)
            sentiment_total += 1
            sentiment_correct += int(result["sentiment"] == expected)
            if result["sentiment"] != expected:
                sentiment_misses.append({"prompt": prompt, "expected": expected, "actual": result["sentiment"]})

    multi_top2 = multi_top3 = 0
    multi_results = []
    for prompt, expected in MULTI:
        result = train_sparse.predict(prompt, model)
        ranking = [item["intent"] for item in result["top"]]
        expected_set = set(expected)
        pair2 = expected_set.issubset(set(ranking[:2]))
        pair3 = expected_set.issubset(set(ranking[:3]))
        multi_top2 += int(pair2)
        multi_top3 += int(pair3)
        multi_results.append({"prompt": prompt, "expected": expected, "top": result["top"], "pairInTop2": pair2, "pairInTop3": pair3})

    report = {
        "suite": "TinyAI refined sparse v3 exposed development regression v4",
        "frozenCorpusSha256": "a8a59268ae648c7346d4a9c89e7dc89df917475c9f02cbd8080037975b3d3301",
        "policy": "Originally independent for the 12,617-feature model; later failures informed refinement, so current results are development-only.",
        "thresholds": {"singleIntent": 0.80, "singleTop2": 0.90, "sentiment": 0.85, "multiPairTop2": 0.60},
        "singleIntent": {"total": total, "correct": correct, "accuracy": correct / total, "top2Accuracy": top2 / total, "misses": misses},
        "sentiment": {"total": sentiment_total, "correct": sentiment_correct, "accuracy": sentiment_correct / sentiment_total, "misses": sentiment_misses},
        "multiIntent": {"total": len(MULTI), "pairInTop2": multi_top2 / len(MULTI), "pairInTop3": multi_top3 / len(MULTI), "results": multi_results},
    }
    path = train_sparse.BUILD / "release-acceptance-v4.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = {
        "singleIntent": {"total": total, "correct": correct, "accuracy": correct / total, "top2Accuracy": top2 / total, "misses": len(misses)},
        "sentiment": {"total": sentiment_total, "correct": sentiment_correct, "accuracy": sentiment_correct / sentiment_total, "misses": len(sentiment_misses)},
        "multiIntent": {"total": len(MULTI), "pairInTop2": multi_top2 / len(MULTI), "pairInTop3": multi_top3 / len(MULTI)},
        "report": str(path),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if not args.report_only and (
        correct / total < 0.80
        or top2 / total < 0.90
        or sentiment_correct / sentiment_total < 0.85
        or multi_top2 / len(MULTI) < 0.60
    ):
        raise SystemExit("v4 development diagnostic missed its historical thresholds")


if __name__ == "__main__":
    main()
