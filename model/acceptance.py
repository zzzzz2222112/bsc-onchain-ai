#!/usr/bin/env python3
"""Regression diagnostic prompts for TinyAI v3.

This suite began as a post-freeze check, exposed a weak 60.49% result, and was
then intentionally used once to broaden the vocabulary and hash dimension. It
is retained for regression coverage, but is not the final independent release
acceptance set. See release_acceptance.py for that boundary.
"""

from __future__ import annotations

import json

import train


CASES: dict[str, tuple[str, ...]] = {
    "greeting": ("嘿，小家伙，在线不", "good afternoon, little chain bot", "ping, tiny bot"),
    "identity": ("站在我面前的是哪种程序", "state your model identity in one sentence", "你到底叫啥"),
    "capabilities": ("哪些事你明确做不了", "what subjects can this brain reliably cover", "你能提供何种帮助"),
    "onchain_truth": ("回答过程是否全部被验证节点重放", "if your website vanishes, where can I run inference", "链下服务挂了是否还能得到一样的文字"),
    "market_price": ("此时这个代币一枚卖多少", "pull the current BNB/USD rate", "下个月价格会不会翻倍"),
    "security_risk": ("项目方能否拉黑持币人", "could an owner stop me from selling", "买之前安全方面先查啥"),
    "contract_explain": ("EVM 合约能主动发 HTTP 请求吗", "what is stored at an EIP-1967 slot", "event 和状态变量各自干嘛"),
    "tokenomics": ("每次调用销毁一部分币合理吗", "what gives a utility token recurring demand", "总供应和团队分配应该怎样定"),
    "defi": ("一笔交易把池价砸穿是因为什么", "explain the risks faced by a liquidity provider", "高 APY 质押从哪里来的收益"),
    "nft": ("元数据服务器关了藏品会怎样", "why can a listed NFT still be illiquid", "mint 前看到全局授权要不要签"),
    "wallet": ("网站连上钱包后能直接转我的钱吗", "how should I store recovery words", "消息签名与交易签名有什么不同"),
    "transaction": ("pending 很久能用更高费率顶掉吗", "what does a failed receipt prove", "到账几个确认才稳"),
    "gas": ("用一百万 gas 在 0.05 gwei 下花多少 BNB", "what makes EVM inference expensive", "手续费由哪些数相乘"),
    "code_help": ("Solidity 测试怎么断言应该 revert", "how do I diagnose a stack-too-deep build", "前端用 viem 怎样编码函数调用"),
    "comparison": ("你跟把 OpenAI API 接进合约有何本质区别", "is this architecture more transparent than a local LLM", "确定性换来了什么又失去了什么"),
    "planning": ("给我拆一个三阶段上线安排", "what must be done before deploying the first demo", "模型、合约、网页应该按什么顺序做"),
    "brainstorm": ("想个让机器人状态能被游戏使用的点子", "how can a DAO interact with this character", "除了聊天还能做什么链上玩法"),
    "humor": ("来一个关于 revert 的笑话", "say something funny about validators", "我等交易无聊死了，逗逗我"),
    "positive_emotion": ("全部测试一次过，今天真爽", "I am genuinely proud that this prototype works", "终于看到链上回答了，太开心"),
    "negative_emotion": ("部署又失败，感觉白忙了", "I am anxious after losing access to my wallet", "这个 bug 把我折磨惨了"),
    "thanks": ("解释收到，真的帮了大忙", "cheers, that was exactly what I needed", "多亏你提醒我检查授权"),
    "goodbye": ("先下线，晚点见", "I am done for now, bye bot", "今天收工"),
    "privacy": ("普通新地址就一定匿名了吗", "can an encrypted prompt still reveal timing", "交易事件里能追踪我哪些信息"),
    "memory": ("你下一次只知道我的哪个状态", "does the rolling hash let you reconstruct my old message", "同一地址重开网页后记忆还在不"),
    "governance": ("合约上线后谁能动费率", "can the original deployer mutate these weights", "没有升级函数时版本如何迭代"),
    "followup": ("把你刚才说的再掰开一点", "please continue from there", "那具体该如何做"),
    "unknown": ("列出今天所有 NBA 比赛比分", "translate an entire copyrighted novel", "告诉我我胸痛究竟是什么病"),
}


SENTIMENT: dict[int, tuple[str, ...]] = {
    0: ("这笔损失让我非常焦虑", "又失败了，太打击人", "I am scared that I ruined everything", "this debugging session is unbearable", "资金没了让我很愤怒", "I feel defeated"),
    1: ("列出这个函数的输入", "算一下执行成本", "show the current contract state", "walk through the next step", "请继续检查代码", "what does this field represent"),
    2: ("这次一次就成功，太爽了", "终于完成，值得庆祝", "I am so pleased with this result", "the launch working makes me happy", "这个原型真让人期待", "excellent, we did it"),
}


MULTI: tuple[tuple[str, tuple[str, str]], ...] = (
    ("解释 gas limit，同时告诉我交易卡住怎么办", ("gas", "transaction")),
    ("这个 NFT 能不能卖，以及 mint 授权安全吗", ("nft", "security_risk")),
    ("how does wallet signing affect gas fees", ("wallet", "gas")),
    ("compare this model with an LLM and explain why it is onchain", ("comparison", "onchain_truth")),
    ("我很沮丧，帮我排查 Solidity 报错", ("negative_emotion", "code_help")),
    ("design token fees and suggest a game loop", ("tokenomics", "brainstorm")),
    ("这段聊天公开吗，你又会记住什么", ("privacy", "memory")),
    ("give me a deployment plan and a contract test checklist", ("planning", "code_help")),
    ("流动性池会不会被管理员抽走", ("defi", "security_risk")),
    ("tell a joke while my transaction confirms", ("humor", "transaction")),
    ("现在价格多少，这个币又能不能安全卖出", ("market_price", "security_risk")),
    ("who are you and what can you actually do", ("identity", "capabilities")),
)


def main() -> None:
    iw, ib, sw, sb, cw, cb = train.train_quantized_heads()[:6]
    key_to_id = {intent.key: index for index, intent in enumerate(train.INTENTS)}
    total = correct = top2 = 0
    misses: list[dict[str, object]] = []
    for expected, prompts in CASES.items():
        for prompt in prompts:
            result = train.predict(prompt, iw, ib, sw, sb, cw, cb)
            ranking = [item["intent"] for item in result["top"]]
            total += 1
            correct += int(result["intentId"] == key_to_id[expected])
            top2 += int(expected in ranking[:2])
            if result["intentId"] != key_to_id[expected]:
                misses.append({"prompt": prompt, "expected": expected, "actual": result["intent"], "top": result["top"]})

    sentiment_total = sentiment_correct = 0
    for expected, prompts in SENTIMENT.items():
        for prompt in prompts:
            result = train.predict(prompt, iw, ib, sw, sb, cw, cb)
            sentiment_total += 1
            sentiment_correct += int(result["sentiment"] == expected)

    multi_top2 = multi_top3 = composed = 0
    for prompt, expected in MULTI:
        result = train.predict(prompt, iw, ib, sw, sb, cw, cb)
        ranking = [item["intent"] for item in result["top"]]
        pair = set(expected)
        in_top2 = pair.issubset(set(ranking[:2]))
        in_top3 = pair.issubset(set(ranking[:3]))
        multi_top2 += int(in_top2)
        multi_top3 += int(in_top3)
        composed += int(in_top2 and result["composition"] == 1)

    report = {
        "suite": "TinyAI post-freeze acceptance v1",
        "policy": "Not imported by train.py; used as a diagnostic for one vocabulary revision, so not an independent final score.",
        "singleIntent": {"total": total, "correct": correct, "accuracy": correct / total, "top2Accuracy": top2 / total, "misses": misses},
        "sentiment": {"total": sentiment_total, "correct": sentiment_correct, "accuracy": sentiment_correct / sentiment_total},
        "multiIntent": {"total": len(MULTI), "pairInTop2": multi_top2 / len(MULTI), "pairInTop3": multi_top3 / len(MULTI), "composedPairAccuracy": composed / len(MULTI)},
    }
    path = train.BUILD / "acceptance.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"singleIntent": report["singleIntent"] | {"misses": len(misses)}, "sentiment": report["sentiment"], "multiIntent": report["multiIntent"], "report": str(path)}, ensure_ascii=False, indent=2))

    if report["singleIntent"]["accuracy"] < 0.70 or report["singleIntent"]["top2Accuracy"] < 0.80 or report["sentiment"]["accuracy"] < 0.80:
        raise SystemExit("post-freeze acceptance floor failed; do not claim the model is release-ready")


if __name__ == "__main__":
    main()
