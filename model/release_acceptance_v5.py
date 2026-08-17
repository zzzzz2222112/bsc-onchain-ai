#!/usr/bin/env python3
"""One-shot independent acceptance for the frozen refined TinyAI v3 model.

Authored only after corpus hash 9bd76b2d... and the 13,531-feature model were
frozen. The trainer must never import this module. Any later corpus, training,
feature, or quantization change permanently demotes this suite to development
diagnostics and requires a newly authored post-freeze suite.
"""

from __future__ import annotations

import json

import train_sparse


FROZEN_CORPUS_SHA256 = "9bd76b2daefa3ac5a59852e3f8fa2e46bae52846b26b884918ac82f0b3cac8e7"

CASES: dict[str, tuple[str, ...]] = {
    "greeting": ("嘿，链上的小家伙，先打个招呼", "早，醒着就回一声", "good to meet you, little contract resident"),
    "identity": ("此刻跟我说话的程序叫什么", "描述你属于哪一种模型", "identify the thing producing this message"),
    "capabilities": ("哪些问题你能比较可靠地处理", "哪些请求你应该直接说不会", "summarize the jobs within your competence"),
    "onchain_truth": ("如果官方网页消失，我还能怎样拿到同样回答", "最终文字是节点算的还是公司接口给的", "can a stranger reproduce this output using only the contract"),
    "market_price": ("BNB 此刻多少美元", "这个币今晚会不会上涨", "fetch today's latest token market cap"),
    "security_risk": ("拥有者能否让持币人永远卖不出去", "存进去的钱有没有管理员可直接划走", "which privileged path could prevent withdrawals"),
    "contract_explain": ("代理执行实现代码时到底修改谁的存储", "event 为什么便宜却不能给合约当数据库", "where does an EIP-1967 proxy discover its implementation"),
    "tokenomics": ("每次聊天收的币应该销毁还是进国库", "固定供应和真实需求怎样联系", "how should usage fees create sustainable token utility"),
    "defi": ("池子只有少量储备时大单会怎样", "做 LP 除了无常损失还怕什么", "what makes a yield pool unsafe even when APY looks attractive"),
    "nft": ("链上所有权还在但图片服务器关了会怎样", "NFT 显示地板价却没人买意味着什么", "what danger comes with approving an entire collection"),
    "wallet": ("助记词备份在哪里才不容易泄露", "网页只请求连接和请求签名有什么区别", "what should I inspect before accepting a permit"),
    "transaction": ("同一个 nonce 的待确认交易怎样替换", "status 为 0 的回执是不是转账成功", "is a confirmed payment reversible"),
    "gas": ("一百五十万 gas 乘零点零五 gwei 是多少 BNB", "gas limit 和 gas price 分别控制什么", "why does iterating over more model features cost more"),
    "code_help": ("Foundry 里怎样断言某调用必须 revert", "用 viem 怎样根据 ABI 编码函数参数", "debug a deployment that forgot an environment variable"),
    "comparison": ("链上分类器和本地小语言模型各自牺牲什么", "固定可复算回答与云端生成回答怎么选", "contrast contract inference with an oracle that calls an LLM"),
    "planning": ("给这个产品安排研究开发审计上线四个阶段", "什么时候做主网模拟和网页验收", "define release gates from prototype to public launch"),
    "brainstorm": ("不靠币价，给这个链上角色设计回访理由", "怎样让别的游戏复用同一个 AI 人格", "invent a persistent onchain pet loop"),
    "humor": ("说个关于 revert 的冷笑话", "别讲道理，拿 gas 费开个玩笑", "give me a validator pun"),
    "positive_emotion": ("本地和链上结果终于完全一致，我太开心了", "所有测试都绿了，今天真顺", "I am delighted that the whole build passed"),
    "negative_emotion": ("又失败了，我现在又累又沮丧", "担心钱包的钱丢掉，我心里很慌", "this endless debugging has left me exhausted and miserable"),
    "thanks": ("这次说明帮我避开了坑，谢谢", "现在完全懂了，多谢你", "thanks, that explanation prevented a bad decision"),
    "goodbye": ("今天收工，明天再接着聊", "我先去睡了，下回见", "signing off now; we can continue another day"),
    "privacy": ("就算正文加密，别人还能从交易看出什么", "换个新地址真能完全匿名吗", "which metadata can link my chat to wallet activity"),
    "memory": ("合约为每个钱包保存了哪些小状态", "隔几天回来你靠什么接上话题", "can the rolling hash reveal my earlier sentences"),
    "governance": ("当前版本坏了以后谁能原地修补", "新模型地址怎样取代旧版成为默认", "can any administrator alter the fee after deployment"),
    "followup": ("沿着你上一句继续深入", "刚才那一点再具体些", "keep going with the previous topic"),
    "unknown": ("明天上海会不会下雨", "替我判断这份劳动合同官司能不能赢", "what was the final score of tonight's basketball game"),
}

SENTIMENT: dict[int, tuple[str, ...]] = {
    0: ("钱包异常让我一整天坐立不安", "连续报错把我信心耗光了", "这次损失让我特别痛苦", "I feel crushed after losing access", "the repeated failures are making me panic", "I cannot bear another broken deployment"),
    1: ("列出模型卡的字段", "计算两种 gas 方案的差额", "检查当前实现地址", "show the deployment parameters", "compare the receipt with the estimate", "continue the read-only audit"),
    2: ("终于看到完整回执，太爽了", "结果一次对上，值得庆祝", "这个进度让我特别满意", "I am proud that every check passed", "the finished demo is better than I hoped", "seeing the model work makes me happy"),
}

MULTI: tuple[tuple[str, tuple[str, str]], ...] = (
    ("先说 permit 签名前检查什么，再估算这次推理 gas", ("wallet", "gas")),
    ("解释代理存储槽，同时判断管理员能否冻结资产", ("contract_explain", "security_risk")),
    ("加密正文后还暴露什么，并说明下一轮保留哪些状态", ("privacy", "memory")),
    ("连续失败让我很崩溃，也请给一套 Foundry 排错步骤", ("negative_emotion", "code_help")),
    ("compare this classifier with a cloud model and prove validators produce the answer", ("comparison", "onchain_truth")),
    ("if NFT media vanishes, could a collection approval also threaten my wallet", ("nft", "wallet")),
    ("设计聊天费的国库与销毁比例，再想一个长期宠物循环", ("tokenomics", "brainstorm")),
    ("the transfer is stuck and I also need its execution fee calculated", ("transaction", "gas")),
    ("列出发布关口，并告诉我怎样测试非管理员路径", ("planning", "code_help")),
    ("explain price impact in a shallow pool and whether privileged LP removal is dangerous", ("defi", "security_risk")),
    ("介绍你是什么模型，再明确哪些任务超出能力", ("identity", "capabilities")),
    ("tell me today's token value but also check whether selling can be blocked", ("market_price", "security_risk")),
)


def main() -> None:
    actual_hash = (train_sparse.BUILD / "corpus.sha256").read_text(encoding="ascii").strip()
    if actual_hash != FROZEN_CORPUS_SHA256:
        raise SystemExit(f"v5 suite is not independent for corpus {actual_hash}; author a new post-freeze suite")

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
        pair2 = set(expected).issubset(set(ranking[:2]))
        pair3 = set(expected).issubset(set(ranking[:3]))
        multi_top2 += int(pair2)
        multi_top3 += int(pair3)
        multi_results.append({"prompt": prompt, "expected": expected, "top": result["top"], "pairInTop2": pair2, "pairInTop3": pair3})

    report = {
        "suite": "TinyAI refined sparse v3 one-shot independent acceptance v5",
        "frozenCorpusSha256": FROZEN_CORPUS_SHA256,
        "policy": "Authored after the 13,531-feature model was frozen and never imported by training.",
        "thresholds": {"singleIntent": 0.80, "singleTop2": 0.90, "sentiment": 0.85, "multiPairTop2": 0.60},
        "singleIntent": {"total": total, "correct": correct, "accuracy": correct / total, "top2Accuracy": top2 / total, "misses": misses},
        "sentiment": {"total": sentiment_total, "correct": sentiment_correct, "accuracy": sentiment_correct / sentiment_total, "misses": sentiment_misses},
        "multiIntent": {"total": len(MULTI), "pairInTop2": multi_top2 / len(MULTI), "pairInTop3": multi_top3 / len(MULTI), "results": multi_results},
    }
    path = train_sparse.BUILD / "release-acceptance-v5.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = {
        "singleIntent": {"total": total, "correct": correct, "accuracy": correct / total, "top2Accuracy": top2 / total, "misses": len(misses)},
        "sentiment": {"total": sentiment_total, "correct": sentiment_correct, "accuracy": sentiment_correct / sentiment_total, "misses": len(sentiment_misses)},
        "multiIntent": {"total": len(MULTI), "pairInTop2": multi_top2 / len(MULTI), "pairInTop3": multi_top3 / len(MULTI)},
        "report": str(path),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if (
        correct / total < 0.80
        or top2 / total < 0.90
        or sentiment_correct / sentiment_total < 0.85
        or multi_top2 / len(MULTI) < 0.60
    ):
        raise SystemExit("independent v5 acceptance failed; do not claim release readiness")


if __name__ == "__main__":
    main()
