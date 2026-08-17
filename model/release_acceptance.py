#!/usr/bin/env python3
"""Exposed v2 diagnostic suite for TinyAI.

This once served as post-freeze acceptance, but later model changes invalidated
that status. It is retained only for regression diagnosis.
"""

from __future__ import annotations

import json

import train


CASES: dict[str, tuple[str, ...]] = {
    "greeting": ("哟，链上的小脑袋醒了吗", "hello there, contract resident", "晚上来聊会儿"),
    "identity": ("现在回复我的究竟是哪一个模型", "describe the thing living at this address", "你属于哪类 AI"),
    "capabilities": ("给我说清楚你会与不会的范围", "which requests are beyond your competence", "你的专长是什么"),
    "onchain_truth": ("若域名失效我如何直接取到答案", "does an eth_call perform the same model math", "回答由节点算还是后台签名"),
    "market_price": ("帮我报一下当下的成交价", "can you see live market capitalization", "预测这个月的最高价"),
    "security_risk": ("owner 能让转账只进不出吗", "is there a route for the team to seize assets", "怎样确认不是 honeypot"),
    "contract_explain": ("代理后面的逻辑地址存在哪儿", "can bytecode query an external REST endpoint", "为什么 event 不能当合约存储读"),
    "tokenomics": ("聊天消耗代币能形成长期需求吗", "where should collected usage fees flow", "供应量定死有什么经济影响"),
    "defi": ("池子深度不足为何造成巨大滑点", "what can make a staking pool unsafe", "LP 提供者会承担哪些损失"),
    "nft": ("藏品图片链接失效后 token 还剩啥", "does a royalty guarantee resale value", "免费铸造为何也可能危险"),
    "wallet": ("把 recovery phrase 存云盘安全不", "what does a dapp learn when I connect", "签一个 permit 可能授权什么"),
    "transaction": ("广播之后一直未打包该怎么处理", "can a confirmed blockchain transfer be undone", "receipt 里哪些字段说明执行成功"),
    "gas": ("六十万 gas 乘当前费率是多少钱", "why do longer prompts cost more EVM work", "gas price 和 limit 分别控制什么"),
    "code_help": ("Foundry 里如何测试权限失败", "what information does a contract ABI expose", "部署脚本执行前应检查哪些变量"),
    "comparison": ("这和在 IPFS 放模型再让服务器推理有啥区别", "compare an immutable classifier with a cloud chatbot", "链上可验证性值得牺牲多少能力"),
    "planning": ("先做最小原型再上线该分哪些关卡", "outline a safe release sequence", "主网前最后一轮检查怎么安排"),
    "brainstorm": ("设计一个由聊天记忆驱动的 NFT 角色", "suggest a non-financial use for this onchain brain", "怎么让其他游戏复用它的状态"),
    "humor": ("给区块确认编个段子", "make a nerdy joke about calldata", "说句不正经的让我开心"),
    "positive_emotion": ("终于没有任何失败测试了，真棒", "the result exceeded everything I hoped for", "看到它跑起来我太激动"),
    "negative_emotion": ("我担心操作错了会把资金全丢掉", "this repeated failure has drained me", "今天一直出错，心态崩了"),
    "thanks": ("明白，感谢你讲得这么细", "that caution was genuinely useful, thank you", "收到啦，帮大忙了"),
    "goodbye": ("先不聊了，回头继续", "time to log off, see you", "我去休息了"),
    "privacy": ("链上只写哈希还能暴露身份线索吗", "who can read the calldata of this chat", "加密正文后地址关系还公开不"),
    "memory": ("这个钱包的历史状态保存在哪个 mapping", "what survives between two sessions", "你能从 context hash 知道我原句吗"),
    "governance": ("发布以后团队还能暂停回答吗", "how would users discover a replacement model version", "权重地址是否可以被换掉"),
    "followup": ("照着上面的主题往下说", "could you elaborate on your last point", "接下来又该怎么办呢"),
    "unknown": ("帮我查现在东京地铁是否延误", "give legal advice for my court case", "完整背诵一本在售小说"),
}


SENTIMENT: dict[int, tuple[str, ...]] = {
    0: ("我很后悔刚才的错误", "损失让我特别不安", "this setback is crushing", "I am terrified of losing the wallet", "反复失败让我筋疲力尽", "everything feels awful"),
    1: ("读取这个地址的状态", "说明构造参数", "calculate the required gas", "show the deployment order", "继续下一项检查", "which value should I verify"),
    2: ("这次结果让我特别满意", "终于成功上线，真令人兴奋", "I am proud of what we built", "everything worked beautifully", "今天的成果值得庆祝", "this is an excellent outcome"),
}


MULTI: tuple[tuple[str, tuple[str, str]], ...] = (
    ("钱包签名有什么风险，同时会花多少 gas", ("wallet", "gas")),
    ("解释代理合约并检查管理员后门", ("contract_explain", "security_risk")),
    ("how private is the prompt and what memory persists", ("privacy", "memory")),
    ("I feel terrible, please help debug my Solidity test", ("negative_emotion", "code_help")),
    ("compare it with ChatGPT and prove validators run it", ("comparison", "onchain_truth")),
    ("give the NFT risks and explain whether it can be sold", ("nft", "security_risk")),
    ("设计聊天代币收费，再想一个长期玩法", ("tokenomics", "brainstorm")),
    ("my transfer failed and the fee was enormous", ("transaction", "gas")),
    ("先给上线步骤，再讲代码如何测试", ("planning", "code_help")),
    ("流动性为何滑点高，项目方又能否撤池", ("defi", "security_risk")),
    ("tell me who you are and which tasks you support", ("identity", "capabilities")),
    ("查实时价格并判断合约是否有跑路风险", ("market_price", "security_risk")),
)


def main() -> None:
    heads = train.train_quantized_heads()
    iw, ib, sw, sb, cw, cb = heads[:6]
    key_to_id = {intent.key: index for index, intent in enumerate(train.INTENTS)}
    total = correct = top2 = 0
    misses: list[dict[str, object]] = []
    for expected, prompts in CASES.items():
        for prompt in prompts:
            result = train.predict(prompt, iw, ib, sw, sb, cw, cb)
            ranking = [item["intent"] for item in result["top"]]
            total += 1
            is_correct = result["intentId"] == key_to_id[expected]
            correct += int(is_correct)
            top2 += int(expected in ranking[:2])
            if not is_correct:
                misses.append({"prompt": prompt, "expected": expected, "actual": result["intent"], "top": result["top"]})

    sentiment_total = sentiment_correct = 0
    sentiment_misses: list[dict[str, object]] = []
    for expected, prompts in SENTIMENT.items():
        for prompt in prompts:
            result = train.predict(prompt, iw, ib, sw, sb, cw, cb)
            sentiment_total += 1
            sentiment_correct += int(result["sentiment"] == expected)
            if result["sentiment"] != expected:
                sentiment_misses.append({"prompt": prompt, "expected": expected, "actual": result["sentiment"]})

    multi_top2 = multi_top3 = composed = 0
    multi_results: list[dict[str, object]] = []
    for prompt, expected in MULTI:
        result = train.predict(prompt, iw, ib, sw, sb, cw, cb)
        ranking = [item["intent"] for item in result["top"]]
        expected_set = set(expected)
        in_top2 = expected_set.issubset(set(ranking[:2]))
        in_top3 = expected_set.issubset(set(ranking[:3]))
        gate = result["composition"] == 1
        multi_top2 += int(in_top2)
        multi_top3 += int(in_top3)
        composed += int(in_top2 and gate)
        multi_results.append({"prompt": prompt, "expected": expected, "top": result["top"], "pairInTop2": in_top2, "pairInTop3": in_top3, "compositionGate": gate})

    report = {
        "suite": "TinyAI exposed release acceptance v2 diagnostic",
        "policy": "Later model changes used these results diagnostically, so this is not independent release evidence.",
        "singleIntent": {"total": total, "correct": correct, "accuracy": correct / total, "top2Accuracy": top2 / total, "misses": misses},
        "sentiment": {"total": sentiment_total, "correct": sentiment_correct, "accuracy": sentiment_correct / sentiment_total, "misses": sentiment_misses},
        "multiIntent": {"total": len(MULTI), "pairInTop2": multi_top2 / len(MULTI), "pairInTop3": multi_top3 / len(MULTI), "composedPairAccuracy": composed / len(MULTI), "results": multi_results},
    }
    path = train.BUILD / "release-acceptance.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = {
        "singleIntent": {"total": total, "correct": correct, "accuracy": correct / total, "top2Accuracy": top2 / total, "misses": len(misses)},
        "sentiment": {"total": sentiment_total, "correct": sentiment_correct, "accuracy": sentiment_correct / sentiment_total, "misses": len(sentiment_misses)},
        "multiIntent": report["multiIntent"] | {"results": len(multi_results)},
        "report": str(path),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))



if __name__ == "__main__":
    main()
