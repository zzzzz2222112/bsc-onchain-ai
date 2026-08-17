#!/usr/bin/env python3
"""Exposed v3 diagnostic suite for TinyAI sparse models.

The first sparse model failed this suite. Subsequent ontology changes therefore
invalidate its original post-freeze status; it is now regression-only.
"""

from __future__ import annotations

import json

import train_sparse


CASES: dict[str, tuple[str, ...]] = {
    "greeting": ("链里的小家伙，露个面呗", "早，今天还能陪我唠两句不", "hey little contract dweller, you up?", "dropping by to say hi to the tiny brain"),
    "identity": ("此刻究竟是什么程序在回我", "你给自己下个定义", "what sort of entity produces these replies", "identify the model behind this address"),
    "capabilities": ("哪些活交给你靠谱，哪些不行", "说说你够得着的任务边界", "where does your competence run out", "list the jobs this tiny system can reliably handle"),
    "onchain_truth": ("网站关门后节点还能吐出同样文字吗", "怎样排除回答是中心化接口塞回来的", "can a second RPC independently recompute this output", "which part of the answer is executed under consensus"),
    "market_price": ("此时 BNB 换美元的汇率是多少", "看看这币短线还有没有上冲空间", "fetch the most recent market valuation", "would today's chart justify an entry"),
    "security_risk": ("项目控制人能不能把用户资产卡死", "买进去以后有没有可能无法退出", "could privileged code confiscate deposits", "what would reveal a sell-blocking honeypot"),
    "contract_explain": ("调用代理时究竟读的是谁的状态", "链上日志为什么不能像变量那样回读", "where is an upgradeable implementation pointer kept", "explain why EVM bytecode cannot open a web URL"),
    "tokenomics": ("提问所收的币应该怎样进入经济循环", "减少流通量是否必然提升价格", "design where paid chat tokens should end up", "does capped issuance create useful demand by itself"),
    "defi": ("池里资金太少为何一买就把价格顶飞", "做市份额除了无常损失还怕什么", "what risks sit behind an advertised staking yield", "how can the team pulling liquidity hurt traders"),
    "nft": ("链上编号还在但媒体没了会怎样", "挂着最低售价为何依旧成交不了", "what danger comes with an unlimited collection approval", "is creator royalty evidence that a collectible has value"),
    "wallet": ("恢复钱包的那串单词能不能交给客服", "连接应用后对方立即拥有哪些权限", "what should I inspect before authorizing a permit", "how should signing keys be backed up safely"),
    "transaction": ("转出去迟迟没进区块该咋处理", "已经确认的付款还能反悔吗", "what does a failed receipt status actually prove", "how do two submissions with the same nonce interact"),
    "gas": ("消耗八十万单位再乘费率怎么算钱", "为什么跑这个小脑比普通转账费计算", "separate the roles of fee rate and execution limit", "how can packed model data lower inference cost"),
    "code_help": ("怎样写一个必须 revert 的权限测试", "部署前配置漏项该从哪里查", "show how an ABI lets a frontend encode a call", "help diagnose a Solidity stack-depth compiler failure"),
    "comparison": ("这种小分类脑和离线语言模型谁强在哪", "为了全网可复算牺牲智力值不值", "contrast this with an oracle relaying cloud AI", "is choosing a canned reply still meaningfully artificial intelligence"),
    "planning": ("把原型走到 BSC 正式版拆成几个关口", "模型、合约、网页和代币先后怎么排", "propose milestones before a safe public launch", "what is the leanest credible rollout sequence"),
    "brainstorm": ("想个不依赖币价的链上角色玩法", "怎样让别的游戏读取这只宠物的成长", "invent a reason for users to revisit this brain", "suggest a composable use beyond paying for messages"),
    "humor": ("别科普了，来点链圈包袱", "拿我那笔离谱手续费开个玩笑", "tell a dumb joke about block confirmations", "give me some nerd comedy while the nonce waits"),
    "positive_emotion": ("折腾这么久终于全跑通，爽死了", "看到合约真的回话我特别兴奋", "I am delighted that every check turned green", "shipping this prototype feels fantastic"),
    "negative_emotion": ("同一个坑掉进去三次，我真崩了", "怕误签把钱弄丢，心里特别慌", "debugging this failure all night has worn me out", "the stolen funds left me feeling hopeless"),
    "thanks": ("这回彻底懂了，谢你", "提醒得及时，差点就签错了", "much appreciated, that explanation cleared it up", "thanks, your warning prevented a bad mistake"),
    "goodbye": ("我先撤，明天再接着弄", "困了收工，下回见", "calling it a night, catch you later", "I am logging off now; we can resume another day"),
    "privacy": ("即便正文加密，观察者还能关联付款地址吗", "公开输入日后有没有办法抹除", "does a fresh address truly hide the chat relationship", "what conversation metadata remains visible to chain watchers"),
    "memory": ("两次提问之间究竟留下了什么状态", "你保存的是原句还是一个压缩痕迹", "what information persists for this wallet across visits", "can the rolling context recover my earlier wording"),
    "governance": ("谁有资格停掉服务或换一套脑子", "不可升级版本出漏洞后该怎么迁移", "can the deployer silently swap the published weights", "how should users learn that a successor model exists"),
    "followup": ("沿着刚才那件事继续讲", "上一点再往深处解释", "go deeper on what you just described", "what comes next for that earlier topic"),
    "unknown": ("告诉我明早广州会不会打雷", "替我判断这份劳动合同能不能打赢官司", "report tonight's football result", "write out an entire newly published novel"),
}


SENTIMENT: dict[int, tuple[str, ...]] = {
    0: ("搞砸后我一直很自责", "一想到可能丢币就害怕", "I feel defeated by the repeated errors", "losing access to the account is terrifying", "这次损失让我睡不着", "the whole setback feels miserable", "我已经调试到没力气了", "I regret approving that transaction"),
    1: ("读取模型版本字段", "列出部署所需参数", "estimate the execution units", "describe the storage layout", "继续验证下一个向量", "which address receives the fee", "计算两种配置的差异", "show the contract call result"),
    2: ("这次一次就过，太痛快了", "终于达到预期效果，值得庆祝", "I am thrilled with the working demo", "the successful release made my day", "所有检查都是绿色，真开心", "I am proud of this result", "效果居然比计划还好", "what a wonderful outcome"),
}


MULTI: tuple[tuple[str, tuple[str, str]], ...] = (
    ("先说钱包授权风险，同时估一下手续费", ("wallet", "gas")),
    ("解释 implementation slot，再看 owner 有没有后门", ("contract_explain", "security_risk")),
    ("聊天记录是否匿名，另外跨会话会记住什么", ("privacy", "memory")),
    ("我被这个报错折磨惨了；顺便帮我写失败测试", ("negative_emotion", "code_help")),
    ("compare this tiny model with ChatGPT and show why nodes can verify it", ("comparison", "onchain_truth")),
    ("tell me the NFT approval danger plus whether a buyer must exist", ("nft", "security_risk")),
    ("规划代币收费方式，同时想一个宠物成长循环", ("tokenomics", "brainstorm")),
    ("the payment is pending and I also need to know its gas cost", ("transaction", "gas")),
    ("先排上线里程碑，然后说明合约测试方法", ("planning", "code_help")),
    ("why does thin liquidity cause slippage and can insiders remove the pool", ("defi", "security_risk")),
    ("introduce yourself, plus list the tasks you cannot handle", ("identity", "capabilities")),
    ("查当下行情，同时排查这个代币能不能卖出", ("market_price", "security_risk")),
    ("make me laugh and then remember that topic for next time", ("humor", "memory")),
    ("who controls upgrades, and where is the implementation stored", ("governance", "contract_explain")),
    ("我很开心，另外想听个关于区块的冷笑话", ("positive_emotion", "humor")),
)


def main() -> None:
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
        "suite": "TinyAI exposed sparse v3 diagnostic",
        "policy": "A later ontology change was informed by this failed suite, so it is not independent release evidence.",
        "thresholds": {"singleIntent": 0.80, "singleTop2": 0.90, "sentiment": 0.85, "multiPairTop2": 0.60},
        "singleIntent": {"total": total, "correct": correct, "accuracy": correct / total, "top2Accuracy": top2 / total, "misses": misses},
        "sentiment": {"total": sentiment_total, "correct": sentiment_correct, "accuracy": sentiment_correct / sentiment_total, "misses": sentiment_misses},
        "multiIntent": {"total": len(MULTI), "pairInTop2": multi_top2 / len(MULTI), "pairInTop3": multi_top3 / len(MULTI), "results": multi_results},
    }
    path = train_sparse.BUILD / "release-acceptance-v3.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = {
        "singleIntent": {"total": total, "correct": correct, "accuracy": correct / total, "top2Accuracy": top2 / total, "misses": len(misses)},
        "sentiment": {"total": sentiment_total, "correct": sentiment_correct, "accuracy": sentiment_correct / sentiment_total, "misses": len(sentiment_misses)},
        "multiIntent": {"total": len(MULTI), "pairInTop2": multi_top2 / len(MULTI), "pairInTop3": multi_top3 / len(MULTI)},
        "report": str(path),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
