#!/usr/bin/env python3
"""Independent quality benchmark for TinyAI v3.

The prompts in this file are deliberately kept out of the training corpus.
They test paraphrases, colloquial wording, bilingual usage, multi-intent
questions, and sentiment generalisation. Do not copy benchmark prompts into
the training set when improving the model.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

import train


SINGLE_INTENT_CASES: dict[str, tuple[str, ...]] = {
    "greeting": (
        "冒个泡，机器人",
        "老铁早呀",
        "yooo bot",
        "anyone awake in the contract?",
        "knock knock, tiny machine",
    ),
    "identity": (
        "报上名来，你究竟是什么东西",
        "你的大脑是什么结构",
        "tell me what entity is answering this",
        "what should I call this contract creature",
        "是谁在这头跟我说话",
    ),
    "capabilities": (
        "你实际能处理到哪一步",
        "除了套话你还有啥本领",
        "list the kinds of questions within your scope",
        "can this little model reason about anything useful",
        "你的短板和长处分别是什么",
    ),
    "onchain_truth": (
        "把前端关了回答还能出来吗",
        "有没有哪个 API 在服务器上替你生成文字",
        "which exact computation is performed by validators",
        "prove the returned sentence was not fetched offchain",
        "我怎么用另一个 RPC 复核同一答案",
    ),
    "market_price": (
        "这会儿一枚 BNB 值几个美元",
        "帮我看看盘面下一小时往哪走",
        "give me the latest quote for this coin",
        "is now a good entry based on current market conditions",
        "你知道此刻的流通市值不",
    ),
    "security_risk": (
        "owner 有办法把我的币冻住吗",
        "这个东西买完会不会卖不掉",
        "walk me through the ways this protocol could steal deposits",
        "what privileges should scare me in an upgradeable contract",
        "我该从哪里排查骗局",
    ),
    "contract_explain": (
        "delegatecall 到底改变了谁的存储",
        "为什么日志比 storage 便宜",
        "can a Solidity program fetch a normal website by itself",
        "break down how an implementation slot works",
        "节点拿到 bytecode 之后干嘛",
    ),
    "tokenomics": (
        "如果每次提问都收币，钱怎么分才不坑",
        "靠销毁真的能让代币升值吗",
        "design a sustainable usage fee for the chat token",
        "does a billion-token supply make any economic sense",
        "机器人和币之间除了收费还能怎么绑定",
    ),
    "defi": (
        "池子只有两万刀时大单会发生什么",
        "提供流动性究竟会亏在哪",
        "why does a constant product pool move the quote",
        "what could go wrong with a yield farm",
        "怎么确认 LP 没被项目方随时抽走",
    ),
    "nft": (
        "图片在 IPFS 就等于永远在链上吗",
        "mint 页面让我 setApprovalForAll 正常吗",
        "how can an NFT show a floor price but have no buyer",
        "where does token metadata actually come from",
        "NFT 与普通 ERC20 的所有权记录差在哪",
    ),
    "wallet": (
        "能把十二个单词发给客服找回吗",
        "我点签名之前最少看哪些东西",
        "does connecting my wallet give the site control of funds",
        "what is the safest recovery backup routine",
        "为什么换了浏览器地址还在",
    ),
    "transaction": (
        "区块浏览器显示 status 0 是啥意思",
        "同一个 nonce 发两笔会怎么样",
        "my transfer has been pending for an hour, what now",
        "when is a chain payment practically irreversible",
        "tx hash 能证明收款人实际收到币吗",
    ),
    "gas": (
        "二百 gwei 和 gas limit 怎么算最终花费",
        "合约推理为何比转账烧气",
        "estimate the fee if execution uses five million gas",
        "can calldata or model size make inference cheaper",
        "报 out of gas 和合约 revert 有何区别",
    ),
    "code_help": (
        "我的 forge test 一直 revert 怎么定位",
        "前端调用合约需要哪些 ABI 条目",
        "show a safe deployment checklist for Solidity code",
        "why does my compiler say stack too deep",
        "如何给 permit 支付写单元测试",
    ),
    "comparison": (
        "你这更像分类器还是生成式大模型",
        "把链上小脑和手机离线 LLM 对比一下",
        "is determinism worth the loss in intelligence",
        "compare this design with an oracle-based AI service",
        "只会选词库答案还能称 AI 吗",
    ),
    "planning": (
        "从零做到可用 demo 要拆哪几期",
        "上主网之前我该验收哪些指标",
        "map out the work from model training to BSC launch",
        "what is the smallest credible version we can ship",
        "先研究模型还是先发行代币",
    ),
    "brainstorm": (
        "给这个电子宠物设计一个能长期玩的循环",
        "有哪些别的合约可以直接调用它",
        "invent an onchain mechanic that is not just pay-to-chat",
        "how could users co-create the character over time",
        "再来三个不靠炒币的玩法",
    ),
    "humor": (
        "说点能让我笑的 EVM 梗",
        "给 nonce 讲个冷笑话",
        "roast my absurd gas bill",
        "entertain me while the block confirms",
        "别讲道理了，整点乐子",
    ),
    "positive_emotion": (
        "终于把主网测试全部跑绿，爽",
        "这个效果比我预期的好多了",
        "I cannot believe we actually shipped it",
        "the demo works and I am delighted",
        "今天进展顺利得离谱",
    ),
    "negative_emotion": (
        "又卡在同一个错误，我快炸了",
        "钱包被盗让我特别难受",
        "I am exhausted after debugging all night",
        "everything broke and I feel hopeless",
        "这个失败真的打击到我了",
    ),
    "thanks": (
        "收到，解释得很明白",
        "这下懂了，谢啦",
        "your warning saved me a mistake, much appreciated",
        "perfect, that answers my question",
        "辛苦你把细节捋清楚",
    ),
    "goodbye": (
        "我撤了，改天接着搞",
        "关机睡觉，回见",
        "I am signing off for the night",
        "let us pick this up next week",
        "今天先到这儿吧",
    ),
    "privacy": (
        "我用新地址聊天就没人能关联了吗",
        "链上的 prompt 后面能抹掉不",
        "can observers connect my questions to wallet activity",
        "does encrypting text hide who paid the transaction",
        "公开事件会暴露哪些行为线索",
    ),
    "memory": (
        "你保存的是原文还是一个摘要状态",
        "下一轮你怎么利用我刚才说的话",
        "if I call from another account, do I inherit this history",
        "can your contract truly recall a previous topic",
        "这份记忆会不会随着前端消失",
    ),
    "governance": (
        "部署者还能换掉那几份权重吗",
        "谁有权把聊天费调成天价",
        "can any multisig pause or rewrite the model",
        "what happens when the community wants version four",
        "不可升级的话修漏洞怎么办",
    ),
    "followup": (
        "刚才那一点再往下讲",
        "所以我接下来该干嘛",
        "could you unpack that a bit more",
        "keep going from your last answer",
        "why exactly is that the case",
    ),
    "unknown": (
        "给我算 238947 乘以 773 的精确结果",
        "查一下今晚上海浦东会不会下雨",
        "summarize the latest meeting of the Federal Reserve",
        "prescribe medicine for the pain in my chest",
        "帮我写一篇完整的三国同人小说",
    ),
}


MULTI_INTENT_CASES: tuple[tuple[str, tuple[str, str]], ...] = (
    ("查完合约风险后顺便告诉我现在币价", ("security_risk", "market_price")),
    ("先解释代理合约，再说管理员能不能跑路", ("contract_explain", "security_risk")),
    ("这个聊天费怎么算，收到的代币又去哪里", ("gas", "tokenomics")),
    ("连接钱包签名会不会付手续费", ("wallet", "gas")),
    ("NFT mint 后卖不出去是不是骗局", ("nft", "security_risk")),
    ("thanks, and tell me whether the model can be upgraded", ("thanks", "governance")),
    ("I am frustrated; help me debug the revert", ("negative_emotion", "code_help")),
    ("compare this bot to ChatGPT and prove it is onchain", ("comparison", "onchain_truth")),
    ("how much gas does a token-paid question use", ("gas", "tokenomics")),
    ("brainstorm a DeFi game using this AI", ("brainstorm", "defi")),
    ("我很开心，顺便讲个笑话", ("positive_emotion", "humor")),
    ("我先走了，记住今天聊的东西", ("goodbye", "memory")),
    ("这聊天匿名吗，换钱包还认得我不", ("privacy", "memory")),
    ("给我路线图，还要说明第一版合约怎么写", ("planning", "code_help")),
    ("你是谁以及到底能干嘛", ("identity", "capabilities")),
    ("what is an AMM and can the admin drain its pool", ("defi", "security_risk")),
    ("show the latest price and audit the token for rug risk", ("market_price", "security_risk")),
    ("my transaction is stuck and I cannot afford the gas", ("transaction", "gas")),
    ("design token utility for a persistent onchain pet", ("tokenomics", "brainstorm")),
    ("is the artwork private if the NFT metadata is on IPFS", ("nft", "privacy")),
    ("why is inference expensive if this is not a real LLM", ("gas", "comparison")),
    ("用另一个 RPC 验证回答以后怎么部署它", ("onchain_truth", "planning")),
    ("助记词泄露后交易被转走了，我很崩溃", ("wallet", "negative_emotion")),
    ("is the contract immutable and who controls upgrades", ("governance", "contract_explain")),
    ("能不能用代币收费同时把隐私保护好", ("tokenomics", "privacy")),
)


SENTIMENT_CASES: dict[int, tuple[str, ...]] = {
    0: (
        "这次损失让我睡不着",
        "折腾半天还是失败，真泄气",
        "看到资产被转走我很恐慌",
        "又报错了，整个人都麻了",
        "I feel crushed by this loss",
        "debugging this has made me miserable",
        "I am worried the funds are gone",
        "nothing works and I am losing patience",
        "被骗以后我既生气又难过",
        "today's failure really hurt",
    ),
    1: (
        "说明一下这个字段",
        "给出部署所需步骤",
        "我想知道合约地址",
        "继续分析下一项",
        "explain the mechanism",
        "show me the relevant value",
        "continue with the review",
        "what does this output mean",
        "请列出已知事实",
        "tell me how the fee is calculated",
    ),
    2: (
        "整个流程终于顺利跑通啦",
        "这个结果真让人兴奋",
        "我太喜欢这个设计了",
        "干得漂亮，值得庆祝",
        "we finally made it work",
        "this result is fantastic",
        "I am thrilled with the prototype",
        "excellent work, I love it",
        "今天的进度特别顺利",
        "that success made my day",
    ),
}


def train_current_model() -> tuple[
    list[list[int]],
    list[int],
    list[list[int]],
    list[int],
    list[list[int]],
    list[int],
]:
    return train.train_quantized_heads()[:6]


def evaluate() -> dict[str, object]:
    iw, ib, sw, sb, cw, cb = train_current_model()
    key_to_id = {intent.key: index for index, intent in enumerate(train.INTENTS)}

    confusion: Counter[tuple[str, str]] = Counter()
    per_intent: dict[str, dict[str, int]] = defaultdict(
        lambda: {"correct": 0, "top2": 0, "total": 0}
    )
    misses: list[dict[str, object]] = []
    margins: list[int] = []
    total = correct = top2_correct = 0

    for expected_key, prompts in SINGLE_INTENT_CASES.items():
        expected_id = key_to_id[expected_key]
        for prompt in prompts:
            result = train.predict(prompt, iw, ib, sw, sb, cw, cb)
            ranking = [item["intent"] for item in result["top"]]
            actual = str(result["intent"])
            total += 1
            per_intent[expected_key]["total"] += 1
            margins.append(int(result["margin"]))
            confusion[(expected_key, actual)] += 1
            if actual == expected_key:
                correct += 1
                per_intent[expected_key]["correct"] += 1
            else:
                misses.append(
                    {
                        "prompt": prompt,
                        "expected": expected_key,
                        "actual": actual,
                        "top": result["top"],
                    }
                )
            if expected_key in ranking[:2]:
                top2_correct += 1
                per_intent[expected_key]["top2"] += 1

    multi_results: list[dict[str, object]] = []
    multi_top2 = multi_top3 = primary_top1 = 0
    multi_gate = composed_pair = 0
    for prompt, expected in MULTI_INTENT_CASES:
        result = train.predict(prompt, iw, ib, sw, sb, cw, cb)
        ranking = [str(item["intent"]) for item in result["top"]]
        expected_set = set(expected)
        top2_match = expected_set.issubset(set(ranking[:2]))
        top3_match = expected_set.issubset(set(ranking[:3]))
        primary_match = ranking[0] == expected[0]
        multi_top2 += int(top2_match)
        multi_top3 += int(top3_match)
        primary_top1 += int(primary_match)
        gate = int(result["composition"]) == 1
        multi_gate += int(gate)
        composed_pair += int(gate and top2_match)
        multi_results.append(
            {
                "prompt": prompt,
                "expected": expected,
                "top": result["top"],
                "pairInTop2": top2_match,
                "pairInTop3": top3_match,
                "primaryTop1": primary_match,
                "compositionGate": gate,
            }
        )

    sentiment_total = sentiment_correct = 0
    sentiment_misses: list[dict[str, object]] = []
    for expected, prompts in SENTIMENT_CASES.items():
        for prompt in prompts:
            result = train.predict(prompt, iw, ib, sw, sb, cw, cb)
            actual = int(result["sentiment"])
            sentiment_total += 1
            sentiment_correct += int(actual == expected)
            if actual != expected:
                sentiment_misses.append(
                    {"prompt": prompt, "expected": expected, "actual": actual}
                )

    ordered_confusion = [
        {"expected": expected, "actual": actual, "count": count}
        for (expected, actual), count in sorted(
            confusion.items(), key=lambda item: (-item[1], item[0])
        )
        if expected != actual
    ]
    sorted_margins = sorted(margins)
    single_gate_correct = sum(
        int(train.predict(prompt, iw, ib, sw, sb, cw, cb)["composition"] == 0)
        for prompts in SINGLE_INTENT_CASES.values()
        for prompt in prompts
    )
    return {
        "suite": "TinyAI independent benchmark v1",
        "trainingLeakagePolicy": "Benchmark prompts are not copied into the training corpus.",
        "singleIntent": {
            "total": total,
            "correct": correct,
            "accuracy": correct / total,
            "top2Accuracy": top2_correct / total,
            "perIntent": dict(sorted(per_intent.items())),
            "margin": {
                "min": sorted_margins[0],
                "p25": sorted_margins[len(sorted_margins) // 4],
                "median": sorted_margins[len(sorted_margins) // 2],
                "p75": sorted_margins[(3 * len(sorted_margins)) // 4],
                "max": sorted_margins[-1],
            },
            "confusion": ordered_confusion,
            "misses": misses,
        },
        "multiIntent": {
            "total": len(MULTI_INTENT_CASES),
            "primaryTop1": primary_top1 / len(MULTI_INTENT_CASES),
            "pairInTop2": multi_top2 / len(MULTI_INTENT_CASES),
            "pairInTop3": multi_top3 / len(MULTI_INTENT_CASES),
            "compositionGateRecall": multi_gate / len(MULTI_INTENT_CASES),
            "composedPairAccuracy": composed_pair / len(MULTI_INTENT_CASES),
            "results": multi_results,
        },
        "composition": {
            "singleTopicTotal": total,
            "singleTopicSpecificity": single_gate_correct / total,
            "multiTopicTotal": len(MULTI_INTENT_CASES),
            "multiTopicRecall": multi_gate / len(MULTI_INTENT_CASES),
            "balancedAccuracy": (
                single_gate_correct / total + multi_gate / len(MULTI_INTENT_CASES)
            ) / 2,
        },
        "sentiment": {
            "total": sentiment_total,
            "correct": sentiment_correct,
            "accuracy": sentiment_correct / sentiment_total,
            "misses": sentiment_misses,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=train.BUILD / "benchmark.json",
        help="JSON report path",
    )
    args = parser.parse_args()
    result = evaluate()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        json.dumps(
            {
                "singleIntent": {
                    key: result["singleIntent"][key]
                    for key in ("total", "correct", "accuracy", "top2Accuracy")
                },
                "multiIntent": {
                    key: result["multiIntent"][key]
                    for key in (
                        "total",
                        "primaryTop1",
                        "pairInTop2",
                        "pairInTop3",
                        "compositionGateRecall",
                        "composedPairAccuracy",
                    )
                },
                "composition": result["composition"],
                "sentiment": {
                    key: result["sentiment"][key]
                    for key in ("total", "correct", "accuracy")
                },
                "report": str(args.output),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
