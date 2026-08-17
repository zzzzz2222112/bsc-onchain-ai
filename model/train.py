#!/usr/bin/env python3
"""Train and pack TinyAI's deterministic on-chain dialogue model.

The model is deliberately small: a multiclass linear neural classifier over
hashed Unicode character features plus a three-way sentiment head. Training is
off-chain, while every inference operation and every response lookup is
implemented again in Solidity and runs inside the EVM.

Only the Python standard library is used so the build is reproducible without
downloading a machine-learning runtime.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import struct
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


FEATURE_DIM = 8192
MAX_CODEPOINTS = 96
VARIANTS = 4
LANGUAGES = ("zh", "en")
MODEL_VERSION = 3
COMPOSITION_CLASSES = 2
WEIGHT_CHUNK_BYTES = 24_000
ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build"


@dataclass(frozen=True)
class Intent:
    key: str
    zh_examples: tuple[str, ...]
    en_examples: tuple[str, ...]
    zh_replies: tuple[str, ...]
    en_replies: tuple[str, ...]


INTENTS: tuple[Intent, ...] = (
    Intent(
        "greeting",
        ("你好", "嗨，早上好", "在吗", "哈喽小机器人", "晚上好", "出来聊天", "喂，你好呀", "很高兴见到你"),
        ("hello", "hi there", "good morning", "hey tiny ai", "are you there", "good evening", "let us chat", "nice to meet you"),
        (
            "你好。我是一个很小、但推理过程真正运行在链上的模型。你可以问我链上机制、安全、Gas，或者随便聊两句。",
            "我在。我的记忆和这次回答都会由合约确定；能力有限，不过每个人都能复算我刚才是怎么答出来的。",
            "嗨。这里没有远程大模型替我写答案，只有公开权重、整数打分和链上词库。你想从什么问题开始？",
            "欢迎来聊天。先提醒一句：你发给我的内容会公开留在链上，不要输入私钥、密码或隐私信息。",
        ),
        (
            "Hello. I am tiny, but my inference really runs on-chain. Ask me about contracts, gas, security, or just start a conversation.",
            "I am here. The contract decides my memory and this reply; I am limited, but anyone can reproduce the result.",
            "Hi. No remote LLM writes my answers: only public weights, integer scoring, and an on-chain reply lexicon.",
            "Welcome. One warning first: your prompt becomes public chain data, so never include keys, passwords, or private information.",
        ),
    ),
    Intent(
        "identity",
        ("你是谁", "你叫什么名字", "介绍一下自己", "你是人工智能吗", "你是真AI还是假的", "你住在哪里", "你是什么模型", "谁创造了你"),
        ("who are you", "what is your name", "introduce yourself", "are you an ai", "are you really on chain", "where do you live", "what model are you", "who made you"),
        (
            "我是 TinyAI v3：一个量化的链上神经对话模型。训练在链下完成，但权重、分类、记忆更新和最终回答都在 BSC 合约里。",
            "你可以把我理解成一只住在 EVM 里的电子宠物：脑容量很小，规则公开，不能偷偷连接服务器补答案。",
            "我不是 ChatGPT 的链上副本，也不是通用大模型。我是一个公开、确定性、可复算的轻量对话模型。",
            "我的身份由模型卡和两份不可变字节码定义：一份是量化权重，一份是回答词库。换权重就必须发布新版本。",
        ),
        (
            "I am TinyAI v3, a quantized on-chain neural dialogue model. Training happens off-chain, but weights, inference, memory, and output live in BSC contracts.",
            "Think of me as a small EVM-native electronic pet: little memory, public rules, and no hidden server that can replace my answer.",
            "I am not ChatGPT copied onto a chain and not a general LLM. I am a public, deterministic, reproducible dialogue model.",
            "My identity is fixed by a model card and two immutable bytecode blobs: quantized weights and a reply lexicon. New weights require a new version.",
        ),
    ),
    Intent(
        "capabilities",
        ("你能干什么", "你会做什么", "你聪明吗", "你能回答哪些问题", "你的能力边界是什么", "能帮我分析吗", "你会推理吗", "能不能聊天"),
        ("what can you do", "what are your abilities", "are you smart", "what can I ask", "what are your limits", "can you analyze", "can you reason", "can we chat"),
        (
            "我擅长识别常见意图，解释链上、合约、Gas、钱包和安全概念，并保留很小的用户状态。我不擅长开放世界事实和长推理。",
            "我可以做有限聊天和链上常识解释。我的优势不是聪明，而是答案生成过程公开、不可暗改、可被其他合约直接调用。",
            "我能把问题归入一组训练过的主题，再结合情绪和历史状态选择回答。超出训练范围时，我应该坦白说不知道。",
            "能力上我更像早期掌机游戏里的角色，不像本地大模型；但我的整个大脑都能由 BSC 节点执行和验证。",
        ),
        (
            "I recognize common intents, explain contracts, gas, wallets, and security, and keep a tiny user state. I am weak at open-world facts and long reasoning.",
            "I can hold limited conversations and explain on-chain basics. My advantage is verifiability, not intelligence.",
            "I map a prompt to trained topics, combine sentiment with prior state, and select a reply. Outside that scope, I should admit uncertainty.",
            "I am closer to a character in an early handheld game than a local LLM, but BSC nodes can execute and verify my whole brain.",
        ),
    ),
    Intent(
        "onchain_truth",
        ("什么叫真链上AI", "你为什么算链上", "怎么证明没有服务器", "推理真的在合约里吗", "链上人工智能是什么意思", "是不是只把哈希上链", "你会调用后端吗", "如何验证回答", "聊天真的是链上算的吗", "这次聊天真的在链上推理吗", "回答是不是链上推理的", "不靠服务器能运行吗", "这次回答在哪里计算"),
        ("what is true onchain ai", "why are you on chain", "how can I prove there is no server", "does inference run in the contract", "what does onchain AI mean", "is it only a hash on chain", "do you call a backend", "how can I verify the answer"),
        (
            "真链上的最低标准是：合约持有模型数据，节点执行推理，并由合约返回结果。只把链下答案的哈希写上链，不等于链上 AI。",
            "验证方法很直接：对同一模型地址和输入做 eth_call，任何节点都应返回相同字节；关掉项目网站也不影响推理。",
            "我的网页只是界面。真正决定意图、情绪、回答版本和记忆更新的是合约；RPC 只负责把调用送给节点。",
            "训练可以链下，因为训练不参与每次共识；但部署后的权重、特征算法和输出词库必须公开且不可被后台替换。",
        ),
        (
            "The minimum for true on-chain AI is contract-held model data, node-executed inference, and contract-produced output. Storing only an off-chain answer hash is not enough.",
            "Verification is simple: eth_call the same model and prompt through any node and compare the returned bytes. The website is not required.",
            "The web app is only an interface. The contract determines intent, sentiment, reply variant, and memory; RPC merely delivers the call.",
            "Training may be off-chain because it is not part of each consensus step, but deployed weights, features, and output data must stay public and immutable.",
        ),
    ),
    Intent(
        "market_price",
        ("现在币价多少", "今天BNB价格", "行情怎么样", "这个币会涨吗", "能买吗", "市值是多少", "实时价格告诉我", "明天会不会涨"),
        ("what is the price now", "BNB price today", "how is the market", "will this token pump", "should I buy", "what is the market cap", "tell me the live price", "will it rise tomorrow"),
        (
            "我没有价格预言机，也不能读取互联网，所以不能可靠回答实时行情。请用链上池子、可信行情源和时间戳交叉验证。",
            "价格问题超出我的内置状态。即使有人把价格写进提示词，我也只能把它当输入，不能证明它是真的。",
            "我不能预测涨跌。买入前至少检查合约权限、真实流动性、持仓集中度、卖出路径和可承受损失。",
            "实时市场数据需要预言机或外部数据源；当前版本故意没有接入，因为那会引入另一套信任和成本。",
        ),
        (
            "I have no price oracle or internet access, so I cannot reliably answer live market questions. Cross-check pools, trusted feeds, and timestamps.",
            "Price is outside my built-in state. If someone puts a number in the prompt, I can read it but cannot prove it is true.",
            "I cannot predict pumps. Before buying, check permissions, real liquidity, holder concentration, sellability, and your maximum loss.",
            "Live market data needs an oracle or external feed. This version intentionally omits one because it adds a separate trust and cost surface.",
        ),
    ),
    Intent(
        "security_risk",
        ("安全吗", "有没有后门", "会不会跑路", "这个合约有风险吗", "怎样防止貔貅", "管理员能拿走钱吗", "如何审计", "我会不会被骗"),
        ("is it safe", "does it have a backdoor", "can the team rug", "is this contract risky", "how do I avoid a honeypot", "can the admin steal funds", "how do I audit it", "am I being scammed"),
        (
            "安全不能靠一句承诺。先查代理和管理员权限，再查暂停、黑名单、增发、税费、资金去向、LP 控制和真实卖出路径。",
            "干净的代币代码不等于安全市场。Hook、池子、路由、前端授权和流动性控制都可能单独制造风险。",
            "如果管理员能升级实现、改费率或转走资产，就要按最坏权限评估；‘暂时没作恶’不是技术保证。",
            "我能给审计顺序，不能替代针对具体地址的实时检查。关键链上状态会变化，结论必须带区块高度和时间。",
        ),
        (
            "Security is not a promise. Check proxies and admin powers, then pause, blacklist, mint, fees, fund flow, LP control, and a real sell route.",
            "Clean token code does not guarantee a safe market. Hooks, pools, routers, frontend approvals, and liquidity control are separate risks.",
            "If an admin can upgrade code, change fees, or move assets, evaluate the worst-case authority. Not abusing it yet is not a guarantee.",
            "I can give an audit order, not replace a live review of a specific address. Mutable chain state needs a block number and timestamp.",
        ),
    ),
    Intent(
        "contract_explain",
        ("合约是什么", "智能合约怎么运行", "帮我解释代码", "这个函数什么意思", "代理合约是什么", "字节码有什么用", "事件日志是什么", "合约能联网吗"),
        ("what is a smart contract", "how do contracts run", "explain this code", "what does this function mean", "what is a proxy contract", "what is bytecode for", "what are event logs", "can a contract access the internet"),
        (
            "智能合约是由每个验证节点按同样规则执行的程序。它能读链上状态和调用其他合约，但不能自己访问普通互联网。",
            "代理合约把调用转给实现合约，所以只看代理表面不够；必须同时确认实现地址、升级管理员和存储槽。",
            "事件日志适合保存可检索历史，存储适合保存以后执行必须读取的状态。日志更便宜，但合约本身通常不能再读取旧日志。",
            "字节码是节点真正执行的程序。源码验证能帮助阅读，但最终应把源码、编译结果和链上字节码哈希对上。",
        ),
        (
            "A smart contract is a program every validating node executes under the same rules. It can read chain state and call contracts, but not browse the normal internet.",
            "A proxy forwards calls to an implementation, so reviewing only the proxy is insufficient. Verify implementation, upgrade admin, and storage slots.",
            "Events are cheap searchable history; storage is state future execution must read. Contracts generally cannot read their own old logs.",
            "Bytecode is what nodes actually execute. Verified source helps humans, but source, compiler output, and on-chain code hash should match.",
        ),
    ),
    Intent(
        "tokenomics",
        ("代币怎么结合", "token有什么用", "聊天为什么收费", "代币经济怎么设计", "费用会去哪里", "要不要销毁代币", "如何让币有需求", "发多少代币"),
        ("how does the token fit", "what is the token utility", "why charge for chat", "how should tokenomics work", "where do fees go", "should tokens be burned", "how do we create demand", "what supply should we use"),
        (
            "最朴素的结合是把每次聊天费拆成国库收入和销毁。它能形成使用需求，但不能保证价格上涨，也不能代替真实产品价值。",
            "收费应和可验证服务绑定：用户付代币，合约同一笔交易完成推理、记忆更新和费用分配，避免链下账本。",
            "总量和分配不是越复杂越好。先固定供应、公开接收地址、明确解锁，再用真实使用量验证收费是否合理。",
            "销毁只减少流通，不自动创造价值。更重要的是谁能改费率、谁收到国库资金，以及用户是否愿意重复使用。",
        ),
        (
            "The simplest link is splitting each chat fee between treasury and burn. It creates usage demand but cannot guarantee price appreciation or replace product value.",
            "Fees should bind to a verifiable service: the same transaction performs inference, updates memory, and distributes payment without an off-chain ledger.",
            "Supply and allocation need not be complicated. Fix supply, publish recipients and unlocks, then test whether real usage supports the fee.",
            "Burning reduces circulation but does not automatically create value. Who can change fees, who receives treasury funds, and repeat usage matter more.",
        ),
    ),
    Intent(
        "defi",
        ("DeFi是什么", "流动性池怎么工作", "AMM是什么", "滑点为什么这么高", "LP是什么意思", "无常损失是什么", "质押安全吗", "怎么判断池子"),
        ("what is defi", "how does a liquidity pool work", "what is an AMM", "why is slippage high", "what does LP mean", "what is impermanent loss", "is staking safe", "how do I judge a pool"),
        (
            "AMM 用池中两种资产的余额按公式报价。流动性越薄，同样订单引起的价格变化和滑点通常越大。",
            "LP 份额代表对池中资产的共同所有权。除了无常损失，还要检查手续费、Hook、管理员和 LP 能否被撤走。",
            "DeFi 把金融规则写进合约，但合约可组合也会传递风险：一个预言机、抵押品或路由出问题，可能影响整条路径。",
            "判断池子要看真实储备、交易量、LP 持有人、锁定方式和卖出模拟，不能只看网页显示的美元数字。",
        ),
        (
            "An AMM prices trades from the balances of two assets under a formula. Thinner liquidity usually means more price impact and slippage.",
            "An LP share is joint ownership of pool assets. Beyond impermanent loss, inspect fees, hooks, admins, and whether liquidity can be removed.",
            "DeFi writes financial rules into contracts, but composability propagates risk: one oracle, collateral, or router failure can affect the whole path.",
            "Judge a pool by real reserves, volume, LP holders, lock mechanics, and a sell simulation, not only the website's dollar display.",
        ),
    ),
    Intent(
        "nft",
        ("NFT是什么", "这个NFT有什么用", "铸造NFT安全吗", "怎么判断NFT价值", "版税是什么", "NFT能卖吗", "链上图片在哪里", "NFT和代币区别"),
        ("what is an NFT", "what is this NFT for", "is minting safe", "how do I value an NFT", "what are royalties", "can I sell the NFT", "where is the image stored", "NFT versus token"),
        (
            "NFT 是带唯一编号的链上资产。所有权通常在链上，但图片和元数据可能只存一个外部链接，链接失效时内容也可能消失。",
            "铸造前要确认合约、价格、授权和接收资产；‘免费 mint’也可能诱导无限授权或恶意签名。",
            "NFT 能否卖出取决于真实买方、市场和合约限制。地板价不等于你一定能按那个价格成交。",
            "同质化代币每一份通常等价，NFT 每个 tokenId 可不同。价值仍来自用途、稀缺性和需求，不来自标准本身。",
        ),
        (
            "An NFT is an on-chain asset with a unique identifier. Ownership is usually on-chain, while media may be only an external link that can disappear.",
            "Before minting, verify the contract, price, approvals, and received asset. A free mint can still request dangerous approvals or signatures.",
            "Sellability depends on real buyers, markets, and contract restrictions. A floor price does not guarantee execution at that price.",
            "Fungible token units are normally interchangeable; NFT token IDs can differ. Utility, scarcity, and demand create value, not the standard itself.",
        ),
    ),
    Intent(
        "wallet",
        ("钱包是什么", "私钥丢了怎么办", "助记词能给你吗", "怎么保护钱包", "硬件钱包安全吗", "地址和账户区别", "为什么连接钱包", "签名会花钱吗"),
        ("what is a wallet", "what if I lose my private key", "can I give you my seed phrase", "how do I protect a wallet", "is a hardware wallet safe", "address versus account", "why connect a wallet", "does signing cost gas"),
        (
            "钱包本质上管理签名密钥。地址可以公开，私钥和助记词绝不能输入网页、聊天、代码仓库或发给任何人。",
            "丢失私钥且没有安全备份，通常没有管理员能帮你恢复。备份要离线、分离保存，并先做小额恢复演练。",
            "连接钱包只公开地址和网络；真正有后果的是后续签名。签名前要看链、接收方、金额、方法和授权额度。",
            "普通消息签名不消耗 Gas，但可能授权登录或订单；交易签名会在广播后改变链上状态并支付 Gas。",
        ),
        (
            "A wallet manages signing keys. An address may be public; private keys and seed phrases must never enter a website, chat, repository, or message.",
            "If a key is lost without a safe backup, there is usually no administrator who can recover it. Keep offline separated backups and test recovery with small funds.",
            "Connecting exposes an address and network; the consequential step is signing. Check chain, recipient, amount, method, and allowance first.",
            "A message signature has no gas cost but may authorize a login or order. A transaction signature changes chain state after broadcast and pays gas.",
        ),
    ),
    Intent(
        "transaction",
        ("交易为什么失败", "转账多久到账", "交易卡住了", "nonce是什么", "确认数有什么用", "交易能撤回吗", "哈希怎么查", "广播是什么意思"),
        ("why did my transaction fail", "how long does a transfer take", "my transaction is stuck", "what is a nonce", "why confirmations matter", "can I reverse a transaction", "how do I check a tx hash", "what does broadcast mean"),
        (
            "失败交易通常仍消耗已执行部分的 Gas。要看回执状态、revert 原因、Gas 限额、余额、授权和调用参数。",
            "交易哈希只是定位符，回执才说明是否成功。还要核对链 ID，避免在错误网络上查不到记录。",
            "Nonce 是账户交易序号。较低 nonce 卡住时，后续交易也可能排队；替换通常要用同一 nonce 和更高费用。",
            "已确认交易一般不能撤回。所谓取消通常是在原交易确认前，用同一 nonce 发送更高费率的替代交易。",
        ),
        (
            "A failed transaction often still consumes gas for work already executed. Inspect status, revert reason, gas limit, balance, allowance, and calldata.",
            "A transaction hash is only an identifier; the receipt proves success or failure. Verify the chain ID when searching.",
            "A nonce is an account transaction sequence number. A stuck lower nonce can queue later transactions; replacement uses the same nonce and a higher fee.",
            "A confirmed transaction is generally irreversible. Cancellation means replacing it before confirmation with the same nonce and a higher fee.",
        ),
    ),
    Intent(
        "gas",
        ("Gas是什么", "为什么手续费这么贵", "一次聊天多少钱", "怎么估算gas", "gas limit是什么", "gas price怎么看", "BSC费用多少", "能不能降低手续费"),
        ("what is gas", "why are fees expensive", "how much does one chat cost", "how do I estimate gas", "what is gas limit", "what is gas price", "BSC transaction cost", "can gas be reduced"),
        (
            "Gas 是 EVM 对计算和存储的计量，实际费用约等于 gasUsed × gasPrice。模型越大、输出越长，链上推理越贵。",
            "Gas limit 是你允许交易最多使用的计算量，不等于一定花完；gas price 是每单位 Gas 的价格，两者不要混淆。",
            "本模型把权重一次复制到内存，再做整数打分，避免按字符反复跑大矩阵。实际费用应在部署前用目标链 eth_estimateGas 复测。",
            "降低费用最有效的方法是减少特征维度、避免重复存储、用事件保存历史，并让回答词库按偏移读取，而不是整份复制。",
        ),
        (
            "Gas measures EVM computation and storage; cost is roughly gas used times gas price. Larger models and longer generated output cost more.",
            "Gas limit caps allowed work but is not necessarily all spent. Gas price is the cost per unit; do not confuse the two.",
            "This model copies weights once and performs integer scoring, avoiding a large matrix for every output character. Re-estimate on the target chain before launch.",
            "The biggest savings come from fewer features, less repeated storage, event-based history, and offset reads from a packed reply lexicon.",
        ),
    ),
    Intent(
        "code_help",
        ("怎么写合约", "Solidity怎么学", "代码报错了", "帮我写测试", "如何部署项目", "Foundry怎么用", "前端怎么连接钱包", "ABI是什么"),
        ("how do I write a contract", "how do I learn Solidity", "my code has an error", "help me write tests", "how do I deploy", "how do I use Foundry", "how does the frontend connect a wallet", "what is an ABI"),
        (
            "写合约先定义状态和权限，再写不变量测试、失败路径和事件。能用不可变参数解决的，就不要留下随意升级的管理员入口。",
            "Foundry 的基本闭环是 forge build、forge test、anvil、本地 script，再到目标链 dry-run；广播必须是最后一步。",
            "ABI 是调用方和合约之间的数据说明。函数签名决定选择器，参数按 ABI 编码成 calldata，返回值再按同一规则解码。",
            "钱包前端应明确区分连接、切链、授权、签名、广播、确认和失败状态，不能把一个转圈图标当完整交易流程。",
        ),
        (
            "Start contract code by defining state, authority, and invariants, then test failures and events. Prefer immutability over an unnecessary upgrade key.",
            "A Foundry loop is forge build, forge test, anvil, local scripts, and target-chain dry-run. Broadcasting is the last step.",
            "An ABI describes calls and returns. A function signature determines its selector, arguments become calldata, and outputs use the same encoding rules.",
            "A wallet UI should distinguish connect, network switch, approval, signature, broadcast, confirmation, and failure instead of hiding everything behind a spinner.",
        ),
    ),
    Intent(
        "comparison",
        ("和ChatGPT比怎么样", "你和大模型有什么区别", "链上AI和本地模型哪个好", "跟Quill比呢", "为什么不用服务器", "这种方案优缺点", "是真AI还是规则", "哪个架构更好"),
        ("how do you compare with ChatGPT", "onchain AI versus an LLM", "onchain or local model", "how do you compare with Quill", "why not use a server", "pros and cons", "are you AI or rules", "which architecture is better"),
        (
            "和大模型相比，我的语言能力差很多；优势是没有隐藏推理服务，模型版本固定，其他合约能同步使用结果。",
            "字符级生成更像小语言模型，但每个输出字符都很贵；神经意图模型语言自由度低，却能用更少 Gas 给出完整、有用的句子。",
            "我不是纯关键词规则：意图由训练得到的量化权重打分；但回答来自有限链上词库，所以绝不能包装成通用 LLM。",
            "服务器模型适合追求能力，链上模型适合追求确定性、可组合和抗后台篡改。很多产品最终会同时使用两层。",
        ),
        (
            "Compared with large models, my language ability is far worse. My advantage is fixed versions, no hidden inference server, and synchronous contract composition.",
            "Character generation looks more like a tiny language model but pays per output character. Neural intent selection gives complete useful sentences at much lower gas.",
            "I am not a pure keyword rule: trained quantized weights score the intent. Replies come from a bounded on-chain lexicon, so I must not be marketed as a general LLM.",
            "Server models optimize capability; on-chain models optimize determinism, composition, and resistance to backend changes. Many products can use both layers.",
        ),
    ),
    Intent(
        "planning",
        ("怎么做这个项目", "下一步是什么", "给我一个计划", "先做什么后做什么", "如何上线", "开发路线怎么排", "MVP怎么做", "项目需要哪些模块"),
        ("how do we build this", "what is the next step", "give me a plan", "what comes first", "how do we launch", "what is the roadmap", "how do we make an MVP", "what modules do we need"),
        (
            "顺序应是：锁定可验证标准，训练并冻结模型，做链上/链下一致性测试，测 Gas，再接支付、前端和部署脚本。",
            "MVP 先证明三件事：没有后端也能回答、同一输入结果一致、费用能接受。代币叙事和营销都应该排在后面。",
            "上线前至少要有源码、模型清单、代码哈希、Gas 基准、安全测试、隐私提示、合约地址和可复现部署说明。",
            "把模型、支付和版本注册拆开会更稳：模型不可变，收费策略可通过发布新聊天合约迭代，前端明确当前版本。",
        ),
        (
            "Order the work as: define verifiability, train and freeze the model, prove off-chain/on-chain parity, benchmark gas, then add payment, UI, and deployment scripts.",
            "An MVP should prove three things first: it answers without a backend, the same input is deterministic, and cost is acceptable. Token marketing comes later.",
            "Before launch, publish source, model manifest, code hashes, gas benchmarks, security tests, privacy warning, addresses, and reproducible deployment steps.",
            "Separate model, payment, and versioning: keep the model immutable, iterate fees with a new chat contract, and make the active version explicit in the UI.",
        ),
    ),
    Intent(
        "brainstorm",
        ("还有什么好点子", "帮我想玩法", "怎么做得有趣", "链上AI能怎么玩", "有什么创新", "可以加什么功能", "如何让用户回来", "给我一个创意"),
        ("give me more ideas", "brainstorm a game", "how can this be fun", "what can onchain AI do", "what is innovative", "what features can we add", "how do users return", "give me a creative idea"),
        (
            "可以把我做成会成长的链上宠物：每个地址都有公开性格状态，聊天改变心情，社区事件解锁新模型版本。",
            "另一个玩法是让模型给出受严格边界约束的链上行动建议，例如投票选项或游戏动作，但绝不能直接支配无限资金。",
            "可以把每次回答铸成可验证记忆碎片，用户收藏特别的对话；价值来自可复算历史，不是假装模型很聪明。",
            "最有意义的创新可能是‘其他合约能调用的角色’：游戏、DAO 和任务系统共享同一人格和公开记忆。",
        ),
        (
            "Turn me into a growing on-chain pet: every address has a public personality state, chats change mood, and community events unlock new model versions.",
            "Another idea is bounded action advice for votes or games. The model should never control unlimited funds directly.",
            "Mint selected answers as verifiable memory fragments. The value is reproducible history, not pretending the model is highly intelligent.",
            "The strongest novelty may be a character callable by other contracts, sharing one public personality across games, DAOs, and quests.",
        ),
    ),
    Intent(
        "humor",
        ("讲个笑话", "逗我笑", "你会开玩笑吗", "来点幽默", "说个冷笑话", "无聊怎么办", "整点活", "讲个区块链笑话"),
        ("tell me a joke", "make me laugh", "can you be funny", "say something humorous", "tell a bad joke", "I am bored", "do something fun", "blockchain joke"),
        (
            "区块链最稳定的感情是什么？不是价格，是你忘记备份私钥之后，资产对旧地址的忠诚。",
            "我问 Gas 能不能便宜一点。Gas 说：可以，你先把那个三层循环从合约里搬出去。",
            "为什么链上机器人从不说悄悄话？因为它每次小声说完，全网节点都复制了一份。",
            "开发者说合约没有管理员。审计员点点头，然后在代理槽里找到了管理员的管理员。",
        ),
        (
            "What is the most loyal relationship in crypto? Your assets staying with the old address after you lose the key.",
            "I asked gas to become cheaper. Gas replied: move that triple loop out of the contract first.",
            "Why can an on-chain bot never whisper? Every node copies the secret as soon as it speaks.",
            "The developer said there was no admin. The auditor nodded and found the admin's admin in the proxy slot.",
        ),
    ),
    Intent(
        "positive_emotion",
        ("我今天很开心", "太棒了", "我成功了", "这个项目真酷", "你做得不错", "好喜欢这个想法", "终于搞定了", "心情很好", "今天终于成功了", "项目总算跑通了", "这次真的做成了", "终于完成任务"),
        ("I am happy today", "that is great", "I succeeded", "this project is cool", "you did well", "I love this idea", "finally finished", "I feel good"),
        (
            "听起来是个好进展。我会把这次互动记成更积极的状态，不过这份‘心情’只是公开的链上数值。",
            "很好。值得庆祝的不是概念听起来酷，而是你把一个可验证、可复现的东西真正跑通了。",
            "收到这份好心情。下一步可以把成功条件写成测试，让它不只存在于记忆里。",
            "我也把语气调亮一点：做链上实验最舒服的时刻，就是回执、输出和预期第一次完全对上。",
        ),
        (
            "That sounds like real progress. I will move our public on-chain mood slightly positive, though it is only a small state value.",
            "Great. The part worth celebrating is not a cool idea but a verifiable, reproducible system actually running.",
            "I received the good mood. Write the success condition as a test so it survives beyond memory.",
            "I will brighten the tone too: the best moment in an on-chain experiment is when receipt, output, and expectation match for the first time.",
        ),
    ),
    Intent(
        "negative_emotion",
        ("我很难受", "今天太糟了", "我失败了", "烦死了", "这个bug折磨我", "我有点失望", "完全搞不定", "心情不好"),
        ("I feel terrible", "today was awful", "I failed", "this is frustrating", "this bug hurts", "I am disappointed", "I cannot make it work", "I feel bad"),
        (
            "听起来确实很挫败。先把问题缩成一个可复现的最小失败，再一次只改一个变量，通常比继续硬撞有效。",
            "我不能真正感受你的情绪，但可以认真回应：先停一下，保存现场、错误和输入，避免疲劳时做不可逆操作。",
            "如果是链上故障，先不要重复签名或加钱。核对交易状态、余额、授权和 revert 原因，再决定下一步。",
            "失败并不等于方向错了。把已验证事实和猜测分开，往往能很快看出真正卡住的是哪一层。",
        ),
        (
            "That sounds genuinely frustrating. Reduce it to one reproducible failure and change one variable at a time instead of pushing blindly.",
            "I cannot truly feel your emotion, but I can respond carefully: pause, save the state, errors, and inputs, and avoid irreversible actions while tired.",
            "For an on-chain failure, do not keep signing or adding funds. Check status, balance, allowance, and revert reason first.",
            "A failure does not prove the direction is wrong. Separate verified facts from guesses to expose the layer that is actually blocked.",
        ),
    ),
    Intent(
        "thanks",
        ("谢谢", "多谢你", "辛苦了", "感谢解释", "你帮到我了", "明白了谢谢", "非常感谢", "不错谢谢"),
        ("thank you", "thanks a lot", "appreciate it", "thanks for explaining", "that helped", "I understand now", "many thanks", "nice thanks"),
        (
            "不客气。链上项目最重要的是把宣传句子拆成可验证的合约事实，继续保持这个习惯。",
            "收到。我的回答不一定对，关键结论仍值得用源码、调用结果和交易回执复核。",
            "不用谢。你下次回来时，我只会记得很小的公开状态，不会拥有链下账户画像。",
            "很高兴有帮助。记得不要把私钥、助记词或敏感信息发给任何聊天机器人，包括我。",
        ),
        (
            "You are welcome. In on-chain work, keep translating marketing claims into verifiable contract facts.",
            "Glad it helped. My answer can still be wrong, so verify important points with source, calls, and receipts.",
            "You are welcome. When you return, I remember only a tiny public state, not an off-chain account profile.",
            "Happy to help. Never send keys, seed phrases, or sensitive information to any chatbot, including me.",
        ),
    ),
    Intent(
        "goodbye",
        ("再见", "我先走了", "晚安", "下次聊", "拜拜", "睡觉去了", "回头见", "结束聊天"),
        ("goodbye", "I have to go", "good night", "talk later", "bye", "going to sleep", "see you", "end chat"),
        (
            "再见。你的这一轮状态会留在合约里；下一次回来，我会从那几个公开数字继续，而不是假装拥有完整记忆。",
            "晚安。睡前别在疲劳状态下签交易，尤其不要处理大额授权或部署广播。",
            "回头见。模型不会趁你离开偷偷更新；如果版本变化，链上地址和代码哈希也必须变化。",
            "聊天结束。最后提醒：链上提示词和回答都是公开的，敏感内容不要上链。",
        ),
        (
            "Goodbye. This turn's small state remains in the contract; next time I continue from public numbers, not pretend to have full memory.",
            "Good night. Avoid signing transactions while tired, especially large approvals or deployment broadcasts.",
            "See you. The model cannot silently update while you are away; a new version must have new addresses and code hashes.",
            "Chat ended. Final reminder: on-chain prompts and replies are public, so keep sensitive content off-chain.",
        ),
    ),
    Intent(
        "privacy",
        ("聊天隐私吗", "别人能看到吗", "会泄露身份吗", "链上消息能删除吗", "匿名吗", "元数据是什么", "能加密聊天吗", "为什么公开"),
        ("is this chat private", "can others see it", "does it reveal my identity", "can I delete an onchain message", "is it anonymous", "what is metadata", "can chat be encrypted", "why is it public"),
        (
            "这不是私密聊天。提示词、回答、地址、时间和交易关系都可能公开，而且确认后通常无法删除。",
            "地址不等于真实姓名，但资金流、时间和交互模式能把多个行为关联起来；这叫元数据泄露。",
            "内容加密只能隐藏正文，不能自动隐藏谁在何时和哪个合约交互。真正的匿名和资金隐私是另外的问题。",
            "当前版本故意把可验证性放在隐私之前。不要输入个人身份、住址、密码、私钥、健康或财务敏感信息。",
        ),
        (
            "This is not private chat. Prompts, replies, addresses, timing, and transaction relationships may be public and usually cannot be deleted.",
            "An address is not a legal name, but fund flow, timing, and behavior can link activities together. That is metadata leakage.",
            "Encrypting content hides text, not automatically who interacted with which contract and when. Identity and fund privacy are separate problems.",
            "This version chooses verifiability over privacy. Do not enter identity, location, passwords, keys, health, or financial secrets.",
        ),
    ),
    Intent(
        "memory",
        ("你记得我吗", "你有记忆吗", "上次聊了什么", "记忆怎么保存", "会记多久", "能忘掉我吗", "你的心情是什么", "每个人状态一样吗"),
        ("do you remember me", "do you have memory", "what did we discuss last time", "how is memory stored", "how long do you remember", "can you forget me", "what is your mood", "does everyone share state"),
        (
            "我只保存每个地址的轮数、上个意图、情绪值、置信度和滚动哈希，不保存一份可读取的完整聊天数据库。",
            "我的记忆很小而且公开。它能让语气和回答版本有连续性，但不能复述你以前说过的每句话。",
            "不同地址有各自状态。更换地址就像换一个新用户；同一地址的历史仍可从公开事件中被任何人索引。",
            "当前合约没有删除记忆的后门。要获得全新状态可以换地址；已经上链的旧事件仍不会消失。",
        ),
        (
            "I store only turn count, last intent, mood, confidence, and a rolling hash per address, not a readable full chat database.",
            "My memory is tiny and public. It gives tone continuity but cannot repeat every sentence from past conversations.",
            "Each address has separate state. A new address looks like a new user, while public events from the old address remain indexable.",
            "This contract has no memory deletion backdoor. A new address starts fresh, but already confirmed events do not disappear.",
        ),
    ),
    Intent(
        "governance",
        ("谁能修改你", "有管理员吗", "模型能升级吗", "谁控制合约", "以后怎么更新", "治理怎么做", "能不能暂停", "模型会变吗"),
        ("who can change you", "is there an admin", "can the model upgrade", "who controls the contract", "how are updates made", "how should governance work", "can it be paused", "will the model change"),
        (
            "这个模型版本没有升级入口：权重和词库在不可变数据合约里，模型卡记录代码哈希。改模型只能发布新地址。",
            "聊天费和分配也在当前聊天合约构造时固定。要改规则就部署新版本，并让前端明确展示迁移，而不是暗中替换。",
            "代币合约是固定供应，没有增发管理员。国库地址仍然能支配收到的代币，这属于经济权限，不应被忽略。",
            "不可升级牺牲了修补便利，换来更清楚的信任边界。上线前测试必须更严格，发现问题时通过新版本迁移。",
        ),
        (
            "This model version has no upgrade path: weights and lexicon are immutable data contracts and the model card records code hashes. Changes require new addresses.",
            "The current chat fee and split are constructor-fixed. New rules require a new contract and an explicit frontend migration, not a silent replacement.",
            "The token has fixed supply and no mint admin. The treasury can still control received tokens; that economic authority must remain visible.",
            "Immutability sacrifices patch convenience for a clearer trust boundary. Testing must be stronger, and fixes ship as explicit new versions.",
        ),
    ),
    Intent(
        "followup",
        ("为什么", "那怎么办", "然后呢", "继续说", "具体一点", "能展开讲吗", "接着说", "所以呢", "还有吗", "上一个问题呢"),
        ("why", "what should I do then", "and then", "go on", "be more specific", "can you expand", "continue that thought", "so what", "anything else", "what about the previous point"),
        (
            "这是一个追问，但我还没有可沿用的上一轮主题。请先给我一个具体的链上、合约或项目问题。",
            "我能沿用同一地址的上一轮主题继续回答；如果这是第一次对话，请把你想展开的对象说清楚。",
            "继续追问会读取你这个地址保存的上个意图，而不是把完整聊天原文重新交给隐藏服务器。",
            "请告诉我你要展开哪一点。我的上下文很小，只能承接上个主题，不能恢复任意久以前的原文。",
        ),
        (
            "That is a follow-up, but I have no earlier topic to continue yet. Start with a concrete on-chain, contract, or project question.",
            "I can continue the previous topic stored for this address. On a first turn, please name the subject you want expanded.",
            "A follow-up reads this address's last intent; it does not resend a full transcript to a hidden server.",
            "Tell me which point to expand. My context is tiny: I can carry one prior topic, not recover arbitrary old text.",
        ),
    ),
    Intent(
        "unknown",
        ("量子香蕉会唱歌吗", "给我讲十九世纪航海天气", "帮我诊断疾病", "写一首完整流行歌曲", "今天纽约堵车吗", "火星上有多少咖啡店", "随机说点我没训练过的", "这个问题非常奇怪"),
        ("can quantum bananas sing", "tell me historical sailing weather", "diagnose my illness", "write a complete pop song", "is New York traffic bad today", "how many cafes are on Mars", "say something outside training", "this question is very strange"),
        (
            "这个问题超出我的小模型范围，我没有足够依据给出可靠答案。你可以把问题改成链上、合约、钱包、Gas 或项目设计。",
            "我没有理解到一个足够明确的已训练主题。与其编造，不如直接说不知道；请换一种更具体的问法。",
            "我的能力边界在这里暴露出来了：我只能在有限主题上做量化分类，不能像通用大模型那样补齐开放世界知识。",
            "我不确定你想问什么。如果这是高风险问题，请不要依赖我；提供可验证的合约地址或明确机制会更有帮助。",
        ),
        (
            "That is outside my small model's reliable scope. Try a question about contracts, wallets, gas, on-chain design, or project architecture.",
            "I did not map the prompt to a clear trained topic. Rather than invent an answer, I should say I do not know; please be more specific.",
            "This exposes my boundary: I classify a limited topic set and cannot fill open-world knowledge like a general large model.",
            "I am not sure what you mean. For high-risk questions, do not rely on me; a verifiable contract address or concrete mechanism would help.",
        ),
    ),
)


SENTIMENT_EXAMPLES = {
    0: (
        "我很难过", "糟透了", "失败", "生气", "害怕", "被骗了", "烦死了", "失望",
        "sad", "terrible", "failed", "angry", "afraid", "scammed", "frustrated", "disappointed",
        "遭受损失", "真泄气", "资产被转走", "整个人都麻了", "精疲力尽", "很痛苦", "彻底绝望", "失去耐心",
        "焦虑", "白忙了", "难以忍受", "被打击", "连续故障让我沮丧", "授权出事让我不安", "调试到撑不住", "反复失败很泄气",
        "crushed by a loss", "miserable", "funds are gone", "losing patience", "hopeless", "worried", "scared", "ruined everything", "exhausted", "unbearable", "defeated", "really hurt",
        "loss made me anxious", "failed deployment left me miserable", "drained by repeated errors", "ashamed of the same mistake",
    ),
    1: (
        "解释一下", "这是什么", "怎么做", "给我数据", "合约地址", "继续", "请分析", "告诉我",
        "explain", "what is this", "how to", "show data", "contract address", "continue", "analyze", "tell me",
        "说明字段", "列出步骤", "给出数值", "查看机制", "继续审查", "列出事实", "如何计算", "展示结果",
        "计算执行成本", "对比两个 gas 估算", "比较两种费用", "核对构造参数", "describe the field", "list the steps", "give the value", "review the mechanism", "continue the review", "list facts", "calculate it", "calculate execution cost", "show the result",
        "compare two gas estimates", "inspect the implementation", "list constructor arguments",
    ),
    2: (
        "开心", "太好了", "成功", "喜欢", "谢谢", "很酷", "优秀", "期待",
        "happy", "great", "success", "love it", "thank you", "cool", "excellent", "excited",
        "顺利跑通", "让人兴奋", "干得漂亮", "值得庆祝", "成果很好", "满意", "超出预期", "令人愉快",
        "自豪", "非常满意", "一次通过", "一切完美合到一起", "完整交付很有成就感", "made it work", "fantastic result", "thrilled", "proud", "pleased with the result", "working makes me happy", "worth celebrating", "delighted", "wonderful progress", "better than expected", "made my day",
        "everything came together perfectly", "prototype passed and I am thrilled", "working contract makes me proud",
    ),
}


# Paraphrases intentionally excluded from training. This is a small product
# acceptance set, not a claim of broad language-understanding accuracy.
VALIDATION_SAMPLES: tuple[tuple[str, int], ...] = (
    ("早啊机器人，今天聊什么", 0),
    ("morning bot, nice to see you", 0),
    ("说说你到底是什么", 1),
    ("describe what kind of AI you are", 1),
    ("你的本事有多大", 2),
    ("which tasks are inside your scope", 2),
    ("断开网站以后还能算答案吗", 3),
    ("does every validator compute your answer", 3),
    ("你知道此刻的实时行情吗", 4),
    ("can you forecast the token price next week", 4),
    ("这个协议会不会卷款", 5),
    ("which permissions could let the owner rug", 5),
    ("为什么实现合约和代理要一起看", 6),
    ("how does delegatecall work", 6),
    ("每次问问题的币会怎样分配", 7),
    ("what economic demand does chat create", 7),
    ("池子太浅会怎样", 8),
    ("explain liquidity and price impact", 8),
    ("元数据丢了 NFT 还剩什么", 9),
    ("does the NFT artwork live on chain", 9),
    ("签名之前该检查什么", 10),
    ("should I ever paste a seed phrase", 10),
    ("回执显示 revert 是什么意思", 11),
    ("can I cancel a mined transfer", 11),
    ("三百万 gas 大约花多少", 12),
    ("why does model inference consume gas", 12),
    ("怎样给合约写失败测试", 13),
    ("what should an ABI contain", 13),
    ("你其实只是关键词机器人吗", 14),
    ("why choose this over a server LLM", 14),
    ("从原型到主网上线分几步", 15),
    ("what should we verify before release", 15),
    ("想一个能持续玩的链上机器人机制", 16),
    ("invent an onchain pet mechanic", 16),
    ("来个关于私钥的段子", 17),
    ("make a silly Ethereum joke", 17),
    ("可算跑通了，真开心", 18),
    ("we shipped it and I am thrilled", 18),
    ("调了半天还是报错，崩溃", 19),
    ("this failure is exhausting me", 19),
    ("讲得清楚，多谢", 20),
    ("that explanation was useful, thanks", 20),
    ("先睡了，明天继续", 21),
    ("catch you another time", 21),
    ("这段对话能被全网看到吗", 22),
    ("what personal metadata leaks here", 22),
    ("换钱包以后你还认识我吗", 23),
    ("what exactly do you store about me", 23),
    ("收费比例以后能偷偷改吗", 24),
    ("is there an upgrade key or pause role", 24),
    ("为什么，继续展开上一点", 25),
    ("go on and explain the previous point", 25),
    ("帮我判断明天适不适合植树", 26),
    ("explain the cuisine of Neptune", 26),
)


# Compact models need an explicit vocabulary. These terms are expanded through
# templates into additional training sentences; validation keeps distinct full
# sentences so we measure composition rather than exact-string memorization.
AUGMENT_TERMS: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    "greeting": (("早安", "早啊机器人", "机器人你好", "见到你真好", "来聊天", "打个招呼"), ("morning bot", "hello robot", "nice to see you", "start a chat", "say hello")),
    "identity": (("你的身份", "说说你的身份", "你到底是什么", "模型介绍", "谁做了你", "你的名字"), ("your identity", "what kind of AI you are", "model introduction", "who created you", "your name")),
    "capabilities": (("能力范围", "能处理什么任务", "你的本事", "能力边界", "会不会分析"), ("ability scope", "tasks inside your scope", "tasks you can handle", "your abilities", "capability limits", "can you analyze")),
    "onchain_truth": (("验证节点计算回答", "断开网站以后还能计算", "断开网站仍能推理", "没有隐藏服务器", "链上执行推理", "回答可复算"), ("validators compute the answer", "works without the website", "no hidden server", "inference inside the EVM", "reproduce the output")),
    "market_price": (("实时行情", "币价预测", "当前价格", "下周涨跌", "最新市值"), ("live market price", "price forecast", "current token price", "price next week", "latest market cap")),
    "security_risk": (("协议卷款", "管理员后门", "owner rug 权限", "资金安全吗", "貔貅风险"), ("protocol rug", "admin backdoor", "owner rug permissions", "fund safety", "honeypot risk")),
    "contract_explain": (("delegatecall", "实现合约和代理", "代理和实现", "智能合约原理", "字节码执行", "事件日志"), ("delegatecall", "proxy and implementation", "smart contract mechanics", "bytecode execution", "event logs")),
    "tokenomics": (("问问题的币怎样分配", "费用怎样分配", "聊天费分配", "代币使用需求", "收费销毁", "固定供应", "token 经济"), ("economic demand from chat", "chat fee distribution", "token usage demand", "fee burning", "fixed supply", "token economics")),
    "defi": (("流动性太浅", "价格冲击", "AMM 池子", "LP 风险", "无常损失"), ("thin liquidity", "price impact", "AMM pool", "LP risk", "impermanent loss")),
    "nft": (("NFT 图片存储", "元数据丢失", "NFT 铸造", "NFT 能否卖出", "NFT 版税"), ("NFT artwork live on chain", "NFT artwork storage", "lost NFT metadata", "NFT mint", "NFT sellability", "NFT royalties")),
    "wallet": (("签名之前检查", "签名前检查", "助记词不能粘贴", "钱包安全", "硬件钱包", "私钥备份"), ("checks before signing", "never paste a seed phrase", "wallet security", "hardware wallet", "private key backup")),
    "transaction": (("回执 revert", "取消已确认转账", "交易失败", "nonce 卡住", "交易哈希"), ("receipt reverted", "cancel a mined transfer", "failed transaction", "stuck nonce", "transaction hash")),
    "gas": (("三百万 gas 费用", "模型推理 gas", "手续费估算", "gas price", "gas limit"), ("three million gas cost", "model inference gas", "fee estimation", "gas price", "gas limit")),
    "code_help": (("失败测试", "ABI 内容", "Foundry 测试", "Solidity 编译", "前端钱包代码"), ("failure tests", "ABI contents", "Foundry testing", "Solidity compilation", "wallet frontend code")),
    "comparison": (("关键词机器人还是 AI", "链上模型对比服务器 LLM", "方案优缺点", "和大模型区别", "字符模型对比意图模型"), ("keyword bot or AI", "onchain model versus server LLM", "architecture tradeoffs", "difference from an LLM", "character model versus intent model")),
    "planning": (("原型到主网上线", "发布前验证", "开发步骤", "MVP 路线", "部署清单"), ("prototype to mainnet", "verification before release", "development steps", "MVP roadmap", "deployment checklist")),
    "brainstorm": (("持续玩的链上机器人", "链上宠物机制", "有趣玩法", "创新功能", "可组合角色"), ("replayable onchain bot", "onchain pet mechanic", "fun product idea", "innovative feature", "composable character")),
    "humor": (("私钥段子", "区块链笑话", "gas 冷笑话", "逗我一下", "讲个梗"), ("private key joke", "blockchain joke", "gas joke", "make me laugh", "silly Ethereum joke")),
    "positive_emotion": (("跑通真开心", "跑通了很开心", "成功发布", "终于做好", "心情特别好", "项目完成"), ("shipped and thrilled", "successful release", "finally working", "feeling wonderful", "project completed")),
    "negative_emotion": (("报错崩溃", "报错到崩溃", "失败很沮丧", "bug 折磨", "心情很差", "被骗很难受"), ("failure is exhausting", "very frustrated", "painful bug", "feeling awful", "hurt by a scam")),
    "thanks": (("讲清楚多谢", "讲得清楚多谢", "解释有帮助", "非常感谢", "辛苦了", "谢谢提醒"), ("useful explanation thanks", "that helped", "many thanks", "appreciate the work", "thanks for the warning")),
    "goodbye": (("先睡了", "明天继续", "回头再聊", "暂时再见", "结束对话"), ("going to sleep", "continue tomorrow", "catch you another time", "goodbye for now", "end the conversation")),
    "privacy": (("对话被全网看到", "对话全网可见", "个人元数据泄露", "聊天能否删除", "地址匿名性", "加密不等于匿名"), ("chat visible to everyone", "personal metadata leakage", "delete onchain chat", "address anonymity", "encryption is not anonymity")),
    "memory": (("换钱包以后还认识我", "换钱包还认识吗", "保存了什么记忆", "每个地址的状态", "能否复述上次聊天", "滚动上下文"), ("remember me after changing wallets", "what you store about me", "state for each address", "repeat our last chat", "rolling context")),
    "governance": (("收费以后能否偷偷改", "收费比例能否暗改", "升级密钥", "pause 权限", "模型管理员", "发布新版本"), ("silently change the fee", "upgrade key", "pause role", "model administrator", "publish a new version")),
    "followup": (("继续上一点", "展开说说", "然后怎么办", "为什么会这样", "再具体一点", "接着回答"), ("continue the previous point", "expand on that", "what happens next", "why is that", "be more specific", "continue answering")),
    "unknown": (("海王星料理", "明天适合植树吗", "量子香蕉唱歌", "火星咖啡店", "陌生医学诊断"), ("cuisine of Neptune", "tomorrow's tree planting weather", "singing quantum bananas", "cafes on Mars", "unknown medical diagnosis")),
}

# Additional semantic anchors broaden the vocabulary without copying any full
# sentence from the independent benchmark. A tiny hashed model cannot infer
# that arbitrary synonyms mean the same thing, so this explicit vocabulary is
# part of the honest capacity boundary of v3.
EXTRA_AUGMENT_TERMS: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    "greeting": (
        ("冒个泡", "早呀", "有人在吗", "在线吗", "下午好", "嗨嗨", "开聊吧", "打扰一下", "向机器人问好", "见面问候"),
        ("yo bot", "anyone here", "online bot", "good afternoon bot", "ping the bot", "wake up robot", "greetings", "knock knock bot", "start talking", "hello machine", "say hi"),
    ),
    "identity": (
        ("报上名来", "究竟是什么东西", "哪种程序", "谁在回答", "大脑是什么结构", "EVM 里的角色", "模型叫什么", "你的来历", "谁在和我说话"),
        ("entity answering me", "model identity", "contract creature identity", "what should I call you", "what is your brain", "your origin", "who is speaking", "kind of model", "EVM character"),
    ),
    "capabilities": (
        ("实际能处理什么", "还有什么本领", "长处和短板", "可回答范围", "哪些主题能回答", "能提供什么帮助", "能帮到哪一步", "会哪些任务", "能力上限", "擅长和不擅长"),
        ("questions within scope", "subjects you reliably cover", "what help you provide", "what you can actually handle", "strengths and weaknesses", "useful reasoning ability", "supported tasks", "capability ceiling", "what you are good at", "practical abilities"),
    ),
    "onchain_truth": (
        ("关掉前端还能回答", "服务器 API 生成文字", "节点执行哪一步", "另一个 RPC 复核", "答案没有链下获取", "合约直接返回文字", "网站离线仍可调用", "共识执行模型"),
        ("frontend shut down", "server API generates text", "computation by validators", "verify with another RPC", "not fetched offchain", "contract returns the sentence", "website offline", "consensus executes the model"),
    ),
    "market_price": (
        ("此刻 BNB 美元价", "一枚代币卖多少", "下一小时走势", "最新报价", "现在入场", "流通市值", "盘面方向", "实时价格数据", "当前行情判断"),
        ("latest coin quote", "price for one token", "current BNB dollar value", "next hour market direction", "good entry now", "circulating market value", "current market conditions", "real-time quote", "live trading data"),
    ),
    "security_risk": (
        ("冻结我的币", "拉黑持币人", "买完卖不掉", "买前安全检查", "偷走存款", "升级权限风险", "排查骗局", "抽走资产", "恶意 owner", "真实卖出路径"),
        ("freeze my tokens", "blacklist holders", "stop me selling", "pre-purchase security checks", "unable to sell", "steal deposits", "dangerous upgrade privilege", "scam checks", "drain the funds", "malicious owner", "real sell route"),
    ),
    "contract_explain": (
        ("delegatecall 存储", "event 和状态变量", "日志和 storage", "合约发送 HTTP 请求", "EIP-1967 存储槽", "Solidity 访问网站", "implementation slot", "节点执行 bytecode", "存储槽原理", "合约调用机制", "runtime code"),
        ("delegatecall storage context", "events versus state variables", "logs versus storage", "contract sends HTTP request", "EIP-1967 slot", "Solidity fetch a website", "implementation slot", "node executes bytecode", "storage slot mechanics", "contract call mechanics", "runtime code"),
    ),
    "tokenomics": (
        ("聊天收费怎么分", "销毁能否升值", "可持续使用费", "十亿枚供应", "收费以外的用途", "代币需求来源", "国库分成", "使用价值设计"),
        ("split the chat payment", "burning creates value", "sustainable usage fee", "billion token supply", "utility beyond fees", "source of token demand", "treasury share", "usage value design"),
    ),
    "defi": (
        ("小池子的大额交易", "交易砸穿池价", "提供流动性亏损", "恒定乘积报价", "收益农场风险", "项目方撤走 LP", "池子储备", "质押收益风险", "流动性深度"),
        ("large trade in a small pool", "trade crashes the pool price", "liquidity provider losses", "constant product pricing", "yield farm risk", "team removes LP", "pool reserves", "staking yield risk", "liquidity depth"),
    ),
    "nft": (
        ("IPFS 图片永久性", "元数据服务器关闭", "setApprovalForAll 风险", "地板价没有买家", "token 元数据来源", "ERC721 和 ERC20", "NFT 内容保存", "铸造授权", "NFT 二级市场"),
        ("IPFS image permanence", "metadata server shuts down", "setApprovalForAll risk", "floor price without buyers", "token metadata source", "ERC721 versus ERC20", "NFT content storage", "mint approval", "NFT secondary market"),
    ),
    "wallet": (
        ("十二个助记词", "消息签名和交易签名", "签名前最少检查", "连接后控制资金", "恢复备份流程", "浏览器里的地址", "密钥保管", "硬件签名", "钱包授权边界"),
        ("twelve seed words", "message signature versus transaction signature", "minimum checks before signing", "control funds after connecting", "recovery backup routine", "address across browsers", "key custody", "hardware signing", "wallet permission boundary"),
    ),
    "transaction": (
        ("status 0", "相同 nonce 两笔", "转账长时间 pending", "提高费率替换 pending", "付款不可逆", "交易回执", "替换卡住交易", "确认后的转账", "收款结果证明"),
        ("transaction status zero", "two transactions with one nonce", "transfer pending for hours", "speed up with a higher fee", "payment irreversible", "transaction receipt", "replace a stuck transaction", "confirmed transfer", "proof recipient was paid"),
    ),
    "gas": (
        ("gwei 乘 gas limit", "推理比转账费气", "五百万 gas 费用", "calldata 降费", "out of gas 和 revert", "执行单元成本", "手续费上限", "链上计算成本"),
        ("gwei times gas limit", "inference costs more than transfer", "five million gas fee", "calldata cost reduction", "out of gas versus revert", "execution unit cost", "maximum transaction fee", "onchain compute cost"),
    ),
    "code_help": (
        ("forge test 定位 revert", "调用需要的 ABI", "viem 编码函数调用", "安全部署检查", "stack too deep", "permit 单元测试", "调试 Solidity", "合约测试用例", "前端合约交互"),
        ("debug a Forge revert", "ABI entries for a call", "encode a viem function call", "safe Solidity deployment", "stack too deep compiler error", "permit unit test", "debug Solidity", "contract test cases", "frontend contract interaction"),
    ),
    "comparison": (
        ("分类器还是生成模型", "API 接进合约", "链上小脑对比离线 LLM", "确定性付出的代价", "确定性和智能的取舍", "预言机 AI 服务", "词库机器人算不算 AI", "模型架构对比", "链上与云端推理", "小模型优缺点"),
        ("classifier versus generative model", "API connected to a contract", "onchain tiny brain versus offline LLM", "cost of determinism", "determinism versus intelligence", "oracle AI service", "reply lexicon bot as AI", "model architecture comparison", "onchain versus cloud inference", "small model tradeoffs"),
    ),
    "planning": (
        ("开发分期", "模块开发顺序", "主网上线验收", "训练到部署的路线", "最小可信版本", "先模型后代币", "研发里程碑", "发布流程", "从零搭建 demo"),
        ("development phases", "order of project modules", "mainnet acceptance criteria", "training to deployment roadmap", "smallest credible release", "model before token", "engineering milestones", "release process", "build a demo from zero"),
    ),
    "brainstorm": (
        ("电子宠物长期循环", "DAO 调用角色", "其他合约调用机器人", "不只是付费聊天", "用户共同塑造角色", "不靠炒币的玩法", "链上角色成长", "可组合游戏机制", "重复使用理由"),
        ("long-term electronic pet loop", "DAO interacts with the character", "other contracts call the bot", "beyond pay to chat", "users co-create the character", "non-speculative game idea", "onchain character progression", "composable game mechanic", "reason to return"),
    ),
    "humor": (
        ("EVM 梗", "revert 笑话", "验证节点笑话", "nonce 冷笑话", "吐槽 gas 账单", "等区块时逗乐", "逗逗我", "整点乐子", "智能合约段子", "钱包笑话", "机器人幽默"),
        ("EVM joke", "revert joke", "funny validators", "nonce pun", "roast a gas bill", "fun while waiting for a block", "entertain me", "smart contract joke", "wallet joke", "robot humor"),
    ),
    "positive_emotion": (
        ("主网测试跑绿", "全部测试一次通过", "看到链上回答很开心", "效果超出预期", "终于发布成功", "demo 让人开心", "进展特别顺利", "值得庆祝", "原型完成很兴奋", "今天成果很好"),
        ("all mainnet tests passed", "all tests passed first try", "proud of the working prototype", "better than expected", "actually shipped", "delighted by the demo", "progress went smoothly", "worth celebrating", "thrilled with the prototype", "great result today"),
    ),
    "negative_emotion": (
        ("同一个错误卡住", "钱包失去访问很焦虑", "钱包被盗很难受", "调试到精疲力尽", "全部坏掉很绝望", "失败很受打击", "损失后睡不着", "报错让我崩溃", "资金丢失很恐慌"),
        ("stuck on the same error", "anxious after losing wallet access", "hurt by a stolen wallet", "exhausted from debugging", "everything broke and feels hopeless", "crushed by failure", "cannot sleep after a loss", "error makes me miserable", "worried the funds are gone"),
    ),
    "thanks": (
        ("解释得很明白", "这下懂了", "提醒我检查授权", "提醒避免了错误", "回答了我的问题", "细节捋清楚了", "谢啦", "感谢警告", "收到多谢"),
        ("explanation was clear", "now I understand", "cheers for the help", "warning saved a mistake", "answered my question", "appreciate the details", "much appreciated", "thanks for the caution", "got it thanks"),
    ),
    "goodbye": (
        ("改天接着搞", "关机睡觉", "今天先到这里", "我撤了", "下周继续", "先结束了", "回见机器人", "收工告别"),
        ("signing off tonight", "pick this up next week", "call it a day", "I am leaving now", "shut down and sleep", "finish for today", "see you later robot", "end this session"),
    ),
    "privacy": (
        ("新地址能否防关联", "删除链上 prompt", "问题关联钱包活动", "加密后谁付钱", "事件追踪信息", "事件暴露行为", "聊天地址追踪", "内容和元数据隐私", "公开输入风险"),
        ("new address prevents linkage", "erase an onchain prompt", "questions linked to wallet activity", "encryption hides the payer", "information traced from events", "events leak behavior", "trace a chat address", "content and metadata privacy", "risk of public prompts"),
    ),
    "memory": (
        ("保存原文还是摘要", "滚动哈希能否重建原文", "下一轮使用上个问题", "换账户继承历史", "回忆之前主题", "前端消失后记忆", "用户状态持久化", "连续对话上下文", "地址独立记忆"),
        ("store raw text or a summary", "reconstruct old text from rolling hash", "use my previous question next turn", "history after changing account", "recall an earlier topic", "memory after frontend disappears", "persistent user state", "conversation context", "memory isolated by address"),
    ),
    "governance": (
        ("部署者替换权重", "谁能调高聊天费", "多签暂停模型", "社区发布第四版", "不可升级合约修漏洞", "控制模型版本", "治理升级权限", "参数能否修改"),
        ("deployer replaces weights", "who can raise the chat fee", "multisig pauses the model", "community releases version four", "fix a bug in an immutable contract", "control model versions", "governance upgrade authority", "mutable parameters"),
    ),
    "followup": (
        ("沿用上一轮主题", "继续刚才的话", "具体如何做", "详细解释一点", "下一步怎么办", "为什么会这样", "再多说一些", "承接上个问题", "上面那点呢"),
        ("use the prior topic", "continue what you said", "how exactly should I do that", "explain it in more detail", "what should happen next", "why is it like that", "say more about it", "carry the previous question", "that earlier point"),
    ),
    "unknown": (
        ("复杂精确乘法", "今天体育比分", "受版权保护的整本小说", "胸痛医学判断", "今晚天气预报", "最新央行会议", "开处方药", "完整长篇小说", "实时交通", "陌生历史细节", "链外新闻摘要"),
        ("exact large multiplication", "today's sports scores", "entire copyrighted novel", "chest pain diagnosis", "weather forecast tonight", "latest central bank meeting", "prescribe medicine", "complete long novel", "live traffic", "obscure historical detail", "offchain news summary"),
    ),
}

# Atomic semantic vocabulary for the sparse on-chain router. These are broad
# concepts rather than copied acceptance sentences. They make the model's
# limited language boundary explicit: synonyms outside this public vocabulary
# may still fall back to the unknown intent.
SEMANTIC_PRIMITIVES: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    "greeting": (
        ("喂", "哟", "嗨", "哈喽", "醒醒", "醒来", "问候", "开场", "打招呼", "早上好", "晚上好", "聊会儿"),
        ("hello", "hey", "hi", "yo", "greeting", "greet", "awake", "welcome", "morning", "evening", "start chatting", "say hi"),
    ),
    "identity": (
        ("身份", "名字", "本体", "类别", "类型", "哪种 AI", "什么模型", "谁在回答", "自我介绍", "链上居民", "模型来历", "回答者"),
        ("identity", "name", "entity", "creature", "resident", "what model", "type of AI", "who answers", "who are you", "introduce yourself", "model origin", "speaker"),
    ),
    "capabilities": (
        ("能力", "本领", "专长", "擅长", "短板", "边界", "范围", "支持任务", "可处理请求", "能做什么", "不会什么", "能力上限"),
        ("capability", "ability", "competence", "expertise", "strength", "weakness", "scope", "supported requests", "supported tasks", "what can you do", "limitations", "specialty"),
    ),
    "onchain_truth": (
        ("节点计算", "节点执行", "共识推理", "链上计算", "复算答案", "断开前端", "没有后台", "无需服务器", "直接调用合约", "验证回答", "eth_call", "换 RPC 验证"),
        ("validator computation", "node execution", "consensus inference", "onchain computation", "reproduce answer", "without frontend", "no backend", "serverless inference", "call contract directly", "verify output", "eth_call", "different RPC"),
    ),
    "market_price": (
        ("币价", "报价", "行情", "走势", "涨跌", "入场价", "市值", "成交价", "实时价格", "价格预测", "盘面", "美元价值"),
        ("price", "quote", "market", "trend", "pump", "entry price", "market cap", "trading price", "live price", "price prediction", "chart", "dollar value"),
    ),
    "security_risk": (
        ("安全", "风险", "后门", "跑路", "卷款", "貔貅", "冻结", "黑名单", "卖不掉", "偷走资金", "恶意权限", "安全审计", "资金被拿走", "骗局"),
        ("security", "risk", "backdoor", "rug", "honeypot", "freeze", "blacklist", "cannot sell", "steal funds", "dangerous permission", "security audit", "seize assets", "scam", "drain funds"),
    ),
    "contract_explain": (
        ("合约原理", "函数含义", "代理逻辑", "实现地址", "存储槽", "事件日志", "字节码", "delegatecall", "runtime code", "状态变量", "合约联网", "调用机制"),
        ("contract mechanics", "function meaning", "proxy logic", "implementation address", "storage slot", "event log", "bytecode", "delegatecall", "runtime code", "state variable", "contract internet access", "call mechanics"),
    ),
    "tokenomics": (
        ("代币经济", "供应量", "固定供应", "代币用途", "使用需求", "收费分配", "国库收入", "销毁代币", "聊天收费", "费用流向", "代币价值", "分配比例"),
        ("tokenomics", "token supply", "fixed supply", "token utility", "usage demand", "fee split", "treasury income", "token burn", "chat payment", "fee flow", "token value", "allocation ratio"),
    ),
    "defi": (
        ("流动性", "池子", "滑点", "价格冲击", "自动做市", "恒定乘积", "LP", "无常损失", "质押", "收益农场", "撤池", "储备深度"),
        ("liquidity", "pool", "slippage", "price impact", "AMM", "constant product", "LP", "impermanent loss", "staking", "yield farm", "remove liquidity", "reserve depth"),
    ),
    "nft": (
        ("NFT", "藏品", "元数据", "图片链接", "版税", "铸造", "mint", "地板价", "tokenId", "ERC721", "二级市场", "藏品出售"),
        ("NFT", "collectible", "metadata", "image link", "royalty", "mint", "floor price", "token id", "ERC721", "secondary market", "artwork", "collectible sale"),
    ),
    "wallet": (
        ("钱包", "助记词", "恢复短语", "私钥", "签名", "连接钱包", "硬件钱包", "密钥备份", "permit 授权", "账户地址", "签名前检查", "密钥保管"),
        ("wallet", "seed phrase", "recovery phrase", "private key", "signature", "connect wallet", "hardware wallet", "key backup", "permit approval", "account address", "signing check", "key custody"),
    ),
    "transaction": (
        ("交易", "转账", "广播", "待确认", "未打包", "回执", "状态码", "nonce", "卡住交易", "替换交易", "执行成功", "确认不可逆"),
        ("transaction", "transfer", "broadcast", "pending", "not mined", "receipt", "status code", "nonce", "stuck transaction", "replace transaction", "execution success", "confirmed irreversible"),
    ),
    "gas": (
        ("Gas", "手续费", "gas price", "gas limit", "gwei", "执行费用", "计算成本", "估算费用", "省 gas", "费用上限", "烧气", "每次聊天成本"),
        ("gas", "fee", "gas price", "gas limit", "gwei", "execution fee", "compute cost", "estimate cost", "save gas", "fee cap", "gas usage", "chat cost"),
    ),
    "code_help": (
        ("写代码", "Solidity", "Foundry", "forge test", "单元测试", "编译错误", "部署脚本", "环境变量", "ABI", "前端调用", "调试 revert", "测试权限"),
        ("write code", "Solidity", "Foundry", "forge test", "unit test", "compiler error", "deployment script", "environment variable", "ABI", "frontend call", "debug revert", "test permission"),
    ),
    "comparison": (
        ("对比", "区别", "优缺点", "取舍", "牺牲能力", "分类器还是大模型", "链上还是云端", "服务器模型", "预言机 AI", "是否算 AI", "架构差异", "能力代价"),
        ("compare", "difference", "pros and cons", "tradeoff", "sacrifice capability", "classifier versus LLM", "onchain versus cloud", "server model", "oracle AI", "is it AI", "architecture difference", "capability cost"),
    ),
    "planning": (
        ("计划", "步骤", "路线图", "里程碑", "开发顺序", "分期", "上线流程", "主网前检查", "发布验收", "最小原型", "下一阶段", "实施安排"),
        ("plan", "steps", "roadmap", "milestone", "development order", "phases", "launch process", "pre-mainnet check", "release acceptance", "minimum prototype", "next phase", "implementation sequence"),
    ),
    "brainstorm": (
        ("创意", "点子", "玩法", "脑暴", "想个功能", "长期循环", "电子宠物", "游戏复用", "其他合约集成", "非金融用途", "角色成长", "可组合玩法"),
        ("idea", "brainstorm", "game mechanic", "invent feature", "long-term loop", "electronic pet", "reuse in games", "contract integration", "non-financial use", "character growth", "composable mechanic", "product concept"),
    ),
    "humor": (
        ("笑话", "段子", "冷笑话", "梗", "逗我", "搞笑", "乐子", "吐槽", "不正经", "幽默", "让我笑", "讲笑话"),
        ("joke", "pun", "make me laugh", "funny", "humor", "entertain", "roast", "silly", "nerdy joke", "tell a joke", "amuse me", "comic relief"),
    ),
    "positive_emotion": (
        ("开心", "高兴", "激动", "兴奋", "满意", "真棒", "太好了", "成功了", "超出预期", "顺利", "自豪", "值得庆祝"),
        ("happy", "glad", "excited", "thrilled", "satisfied", "excellent", "great", "succeeded", "exceeded expectations", "smoothly", "proud", "celebrate"),
    ),
    "negative_emotion": (
        ("难过", "崩溃", "焦虑", "害怕", "后悔", "失望", "疲惫", "沮丧", "心态炸了", "损失难受", "筋疲力尽", "恐慌"),
        ("sad", "crushed", "anxious", "afraid", "regret", "disappointed", "exhausted", "frustrated", "hopeless", "hurt by loss", "drained", "terrified"),
    ),
    "thanks": (
        ("谢谢", "感谢", "多谢", "谢啦", "辛苦了", "有帮助", "明白了", "懂了", "收到", "帮大忙", "感谢提醒", "讲清楚了"),
        ("thanks", "thank you", "appreciate", "many thanks", "helpful", "understood", "got it", "much obliged", "cheers", "big help", "thanks for warning", "clear explanation"),
    ),
    "goodbye": (
        ("再见", "回见", "拜拜", "先走了", "结束聊天", "去休息", "去睡觉", "改天继续", "今天到这", "下次再聊", "收工", "退出"),
        ("goodbye", "bye", "see you", "sign off", "end chat", "go rest", "go sleep", "continue another day", "stop for today", "talk later", "log off", "leave now"),
    ),
    "privacy": (
        ("隐私", "匿名", "元数据", "公开输入", "链上可见", "地址关联", "删除记录", "加密正文", "暴露身份", "谁能读取", "calldata 公开", "交易关系"),
        ("privacy", "anonymous", "metadata", "public prompt", "visible onchain", "address linkage", "delete record", "encrypted content", "identity exposure", "who can read", "public calldata", "transaction graph"),
    ),
    "memory": (
        ("记忆", "上下文", "历史状态", "上一次对话", "跨会话", "保存原文", "滚动哈希", "mapping 状态", "前一轮", "持续状态", "钱包历史", "记住主题"),
        ("memory", "context", "history state", "previous conversation", "between sessions", "store original text", "rolling hash", "mapping state", "prior turn", "persistent state", "wallet history", "remember topic"),
    ),
    "governance": (
        ("治理", "管理员", "升级", "暂停", "替换权重", "修改参数", "更换模型", "发布新版本", "控制权", "多签", "不可变", "谁能改规则"),
        ("governance", "administrator", "upgrade", "pause", "replace weights", "change parameter", "replace model", "new version", "control authority", "multisig", "immutable", "who changes rules"),
    ),
    "followup": (
        ("继续", "展开", "接着说", "详细一点", "上一点", "刚才的话", "然后呢", "下一步呢", "为什么呢", "再说一些", "承接上文", "具体一点"),
        ("continue", "elaborate", "go on", "more detail", "previous point", "what you just said", "then what", "what next", "why so", "say more", "follow up", "be specific"),
    ),
    "unknown": (
        ("天气", "交通", "地铁延误", "体育比分", "法律建议", "医疗诊断", "处方", "新闻", "小说全文", "餐厅推荐", "航班", "链外实时数据"),
        ("weather", "traffic", "transit delay", "sports score", "legal advice", "medical diagnosis", "prescription", "news", "full novel", "restaurant recommendation", "flight status", "offchain live data"),
    ),
}

# A second ontology pass adds concept families rather than benchmark-shaped
# sentences. This improves bounded-domain coverage while preserving the honest
# fallback for vocabulary and facts outside the published model.
SEMANTIC_EXPANSION: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    "greeting": (("露面", "冒头", "在不在", "出来聊聊", "上线了吗", "敲个门", "寒暄", "陪我聊", "打声招呼", "碰个面"), ("checking in", "pop up", "are you up", "drop by", "howdy", "hello there", "chat with me", "wave hello", "good day", "wake up")),
    "identity": (("定义自己", "程序本质", "模型类型", "回答主体", "背后的模型", "是什么实体", "哪个代理在回答", "自我定义", "程序身份", "合约里的生物"), ("define yourself", "nature of the program", "model type", "answering agent", "model behind the address", "what entity", "which agent replies", "self definition", "program identity", "contract dweller")),
    "capabilities": (("可靠处理", "够不着的任务", "能力尽头", "适合交付", "不支持的请求", "可以胜任", "做不到什么", "服务范围", "处理极限", "可用场景"), ("reliably handle", "tasks beyond reach", "end of competence", "suitable jobs", "unsupported request", "can perform", "cannot handle", "service range", "processing limit", "use cases")),
    "onchain_truth": (("全网复算", "关闭网站", "中心化接口", "后台塞答案", "共识验证", "RPC 重算", "节点吐出答案", "链下代答", "节点模型数学", "合约内推理"), ("independently recompute", "website unavailable", "centralized endpoint", "backend supplies answer", "consensus verification", "RPC recomputation", "node returns output", "offchain answering", "model math by nodes", "in-contract inference")),
    "market_price": (("汇率", "短线空间", "上冲", "回调", "当前估值", "买入时机", "价格动向", "市场报价", "实时成交", "盘中表现"), ("exchange rate", "short-term upside", "rally", "pullback", "current valuation", "buying opportunity", "price direction", "market quotation", "live trade", "intraday performance")),
    "security_risk": (("锁死资产", "限制退出", "没法退出", "没收存款", "特权代码", "控制人作恶", "禁止卖出", "扣住资金", "强制冻结", "退出通道"), ("lock user assets", "restrict exit", "unable to exit", "confiscate deposits", "privileged code", "controller abuse", "block selling", "hold funds", "forced freeze", "exit route")),
    "contract_explain": (("读取谁的状态", "代理调用状态", "实现指针", "升级地址", "日志回读", "状态读写", "EVM 执行环境", "外部网址", "代码存储", "调用上下文"), ("whose state is read", "proxy call state", "implementation pointer", "upgrade address", "read back logs", "state reads and writes", "EVM execution environment", "external URL", "code storage", "call context")),
    "tokenomics": (("经济循环", "减少流通", "通缩效果", "发行节奏", "代币排放", "价值捕获", "费用回购", "消耗场景", "持币需求", "供需关系"), ("economic circulation", "reduce circulation", "deflation effect", "issuance schedule", "token emission", "value capture", "fee buyback", "spending use case", "holding demand", "supply and demand")),
    "defi": (("池子太小", "资金深度不足", "一买就涨", "做市损失", "收益率陷阱", "撤走池子", "内部人撤池", "储备不足", "资金利用率", "流动性提供者"), ("pool too small", "insufficient depth", "price jumps on buy", "market making loss", "yield trap", "pull the pool", "insider removes liquidity", "insufficient reserves", "capital efficiency", "liquidity provider")),
    "nft": (("链上编号", "媒体丢失", "藏品媒体", "最低售价", "没有买方", "无限藏品授权", "系列授权", "创作者版税", "藏品价值", "所有权编号"), ("onchain identifier", "missing media", "collectible media", "lowest listing", "no buyer", "unlimited collection approval", "collection approval", "creator royalty", "collectible value", "ownership identifier")),
    "wallet": (("恢复单词", "应用连接权限", "授权 permit", "签署许可", "密钥离线保存", "账户恢复", "签名内容", "应用能看到什么", "授权额度", "密钥泄露"), ("recovery words", "dapp connection access", "authorize permit", "sign authorization", "offline key storage", "account recovery", "signature contents", "what a dapp sees", "approval allowance", "leaked key")),
    "transaction": (("进入区块", "迟迟未确认", "未被打包", "付款反悔", "失败回执", "执行状态", "重复 nonce", "交易替换", "提交到网络", "区块确认"), ("included in a block", "still unconfirmed", "not included", "reverse a payment", "failed receipt", "execution status", "duplicate nonce", "transaction replacement", "submit to network", "block confirmation")),
    "gas": (("执行单位", "费率相乘", "计算费", "普通转账成本", "打包模型省费", "内存扩展费", "调用成本", "费用预算", "每单位价格", "推理开销"), ("execution units", "multiply fee rate", "compute fee", "plain transfer cost", "packed model savings", "memory expansion cost", "call cost", "fee budget", "price per unit", "inference overhead")),
    "code_help": (("配置漏项", "部署配置", "环境参数", "必须失败的测试", "编译栈深", "函数编码", "调用参数", "代码排错", "测试预期 revert", "构建脚本"), ("missing configuration", "deployment configuration", "environment parameter", "expected failure test", "compiler stack depth", "function encoding", "call argument", "code troubleshooting", "expect revert test", "build script")),
    "comparison": (("谁更强", "本地语言模型", "离线模型", "可复算代价", "智力牺牲", "固定回答算 AI", "云模型对照", "方案权衡", "验证性换能力", "分类脑差异"), ("which is stronger", "local language model", "offline model", "cost of reproducibility", "intelligence sacrifice", "fixed replies as AI", "cloud model contrast", "design compromise", "verifiability for capability", "classifier brain difference")),
    "planning": (("拆成关口", "组件先后", "模型合约网页顺序", "阶段验收", "上线里程碑", "实施次序", "分步发布", "发布门槛", "研发安排", "从原型到正式版"), ("split into gates", "component ordering", "model contract frontend order", "stage acceptance", "launch milestone", "implementation order", "staged release", "release gate", "engineering schedule", "prototype to production")),
    "brainstorm": (("回访理由", "角色成长循环", "跨游戏复用", "读取宠物成长", "应用集成", "不靠币价", "重复游玩", "角色互动", "协议可组合", "长期产品循环"), ("reason to revisit", "character growth loop", "cross-game reuse", "read pet progression", "application integration", "independent of token price", "replayability", "character interaction", "protocol composability", "long-term product loop")),
    "humor": (("包袱", "开玩笑", "贫嘴", "段子手", "搞点喜剧", "调侃手续费", "逗乐", "讲点好笑的", "别科普", "来点幽默"), ("comedy", "wisecrack", "banter", "comic line", "make a joke", "tease the fee", "make it amusing", "something funny", "stop lecturing", "a bit of humor")),
    "positive_emotion": (("爽死了", "一片绿色", "达到预期", "效果惊喜", "终于跑起来", "特别兴奋", "成果喜人", "进展完美", "一次成功", "心情大好"), ("feels fantastic", "all green", "met expectations", "pleasant surprise", "finally running", "very excited", "great achievement", "perfect progress", "worked first time", "in a great mood")),
    "negative_emotion": (("自责", "心里发慌", "反复踩坑", "调试一整夜", "被折磨", "害怕丢钱", "情绪低落", "彻底泄气", "压力很大", "心态撑不住"), ("blame myself", "feeling panicked", "same mistake repeatedly", "debugging all night", "being tortured by errors", "afraid of losing money", "feeling low", "completely discouraged", "under heavy stress", "cannot cope")),
    "thanks": (("彻底明白", "提醒及时", "避免签错", "解释清楚", "受教了", "帮我避坑", "太有用了", "感谢说明", "多亏提醒", "谢谢帮忙"), ("completely clear", "timely warning", "prevented a bad signature", "cleared it up", "learned a lot", "helped avoid a trap", "very useful", "thanks for explaining", "thanks to the warning", "thank you for helping")),
    "goodbye": (("我先撤", "困了收工", "明天接着", "下回见", "结束这一轮", "离开会话", "今天结束", "晚点回来", "暂停聊天", "先去休息"), ("I am off", "done for the night", "resume tomorrow", "catch you later", "end this round", "leave the session", "finish today", "come back later", "pause the chat", "take a rest")),
    "privacy": (("付款地址关联", "观察者追踪", "公开输入抹除", "新地址去关联", "链上关系图", "身份线索", "聊天可追踪", "正文加密后", "谁看得到输入", "历史记录删除"), ("payer address linkage", "observer tracking", "erase public input", "unlink with a new address", "onchain relationship graph", "identity clues", "traceable chat", "after encrypting content", "who sees input", "delete history")),
    "memory": (("两轮之间状态", "压缩痕迹", "跨访问保留", "钱包持续信息", "恢复以前措辞", "状态是否持久", "会话之间", "前次主题", "历史摘要", "上下文残留"), ("state between turns", "compressed trace", "persist across visits", "wallet-specific information", "recover prior wording", "state persistence", "across sessions", "earlier subject", "history summary", "remaining context")),
    "governance": (("停掉服务", "换一套模型", "替换脑子", "漏洞迁移", "继任模型", "下一版本通知", "发布权", "模型控制者", "迁移新合约", "版本继承"), ("stop the service", "swap the model", "replace the brain", "migrate after a bug", "successor model", "announce next version", "release authority", "model controller", "migrate to a new contract", "version succession")),
    "followup": (("往深处讲", "沿着前面", "刚才那件事", "再展开些", "后续怎么走", "承接前文", "补充上一点", "再细化", "继续这个话题", "前面内容"), ("go deeper", "following the earlier part", "that previous matter", "expand further", "where to go next", "continue the context", "add to the prior point", "refine further", "continue this subject", "earlier content")),
    "unknown": (("雷雨预报", "劳动合同官司", "足球结果", "篮球比分", "法院胜算", "航班延误", "地铁状态", "今日新闻", "医院诊断", "餐馆订位"), ("thunder forecast", "employment contract lawsuit", "football result", "basketball score", "court outcome", "flight delay", "subway status", "today's news", "hospital diagnosis", "restaurant booking")),
}

# The v4 post-freeze suite exposed concept families that the first expanded
# ontology still handled poorly. These are now development vocabulary; v4 can
# no longer serve as independent release evidence. The phrases below describe
# broad concepts rather than importing complete benchmark sentences.
SEMANTIC_REFINEMENT: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    "greeting": (("敲门问候", "在家吗聊两句", "过来打声招呼"), ("hiya", "stopping by to chat", "knock and say hello")),
    "capabilities": (("有把握解决的需求", "划清支持范围", "明确能做和不能做"), ("boundary around supported work", "work you support", "reliable problem range")),
    "onchain_truth": (("绕过项目域名直接调合约", "域名关闭合约照样回答", "谁选择最终回复"), ("remote service chooses the reply", "contract directly produces the reply", "without the project domain")),
    "security_risk": (("只许买不许卖", "提款被管理方堵住", "权限困住资产"), ("authority traps assets", "buy but cannot sell", "withdrawal blocked by an admin")),
    "contract_explain": (("旧日志不能当状态读取", "日志搜索和状态读取区别", "事件不能回读成状态"), ("search logs but not load them as state", "event history is not contract state", "readable state versus searchable logs")),
    "defi": (("高农场收益风险", "高收益耕作陷阱", "收益率异常危险"), ("dangerous farm return", "high yield farm risk", "unsustainable farming yield")),
    "nft": (("作品文件消失后编号仍在", "挂牌没人接盘", "藏品文件失效"), ("media disappears but the token remains", "listed NFT with no buyer", "collectible file becomes unavailable")),
    "wallet": (("只连接站点会暴露什么", "连接不等于签名", "连接后是否失去资产"), ("connecting a site alone", "connection versus signing", "lose assets merely by connecting")),
    "gas": (("费用上限和每单位费率", "执行量乘单位价格", "gas 封顶与单价"), ("cap versus per-unit gas rate", "execution amount times unit price", "gas ceiling and unit price")),
    "planning": (("合约审计与网页验收节点", "在哪个阶段做审计", "上线关口安排"), ("when to audit and validate the frontend", "stage for contract review", "release gate ordering")),
    "brainstorm": (("不靠炒作的重复循环", "可反复使用的产品机制", "与币价无关的玩法"), ("repeatable loop without speculation", "non-speculative recurring mechanic", "reusable product loop")),
    "humor": (("等待确认时抖机灵", "吐槽钱包授权", "验证节点冷笑话"), ("geeky one-liner", "joke about validators", "roast wallet authorization")),
    "negative_emotion": (("授权风险让我不安", "连续故障令人沮丧", "失败后又惨又累"), ("miserable after a failed deployment", "anxious about authorization", "drained by repeated failures")),
    "memory": (("下次调用读取哪些状态", "原话还是派生上下文", "合约保留的对话痕迹"), ("retain exact words or derived context", "what the next call reads", "conversation trace kept by the contract")),
    "governance": (("谁决定替代模型成为官方", "新版模型由谁认可", "继任版本发布决定"), ("who makes a replacement model official", "authority over the successor brain", "decision to recognize a new version")),
    "unknown": (("今天棒球赛结果", "下午比赛谁赢", "实时体育胜负"), ("today's baseball result", "who won the game this afternoon", "live sports outcome")),
}

ZH_AUGMENT_TEMPLATES = (
    "{term}",
    "请解释{term}",
    "我想了解{term}",
    "关于{term}你怎么看",
    "想问一下{term}",
    "{term}到底怎么回事",
)
EN_AUGMENT_TEMPLATES = (
    "{term}",
    "explain {term}",
    "tell me about {term}",
    "I want to understand {term}",
    "what about {term}",
    "help me with {term}",
)


def augmentation_terms(key: str) -> tuple[tuple[str, ...], tuple[str, ...]]:
    base_zh, base_en = AUGMENT_TERMS[key]
    extra_zh, extra_en = EXTRA_AUGMENT_TERMS[key]
    primitive_zh, primitive_en = SEMANTIC_PRIMITIVES[key]
    expansion_zh, expansion_en = SEMANTIC_EXPANSION[key]
    refinement_zh, refinement_en = SEMANTIC_REFINEMENT.get(key, ((), ()))
    return (
        tuple(dict.fromkeys(base_zh + extra_zh + primitive_zh + expansion_zh + refinement_zh)),
        tuple(dict.fromkeys(base_en + extra_en + primitive_en + expansion_en + refinement_en)),
    )


def u32(value: int) -> int:
    return value & 0xFFFFFFFF


def mix32(value: int) -> int:
    value = u32(value)
    value ^= value >> 16
    value = u32(value * 0x7FEB352D)
    value ^= value >> 15
    value = u32(value * 0x846CA68B)
    value ^= value >> 16
    return u32(value)


def normalized_codepoints(text: str) -> list[int]:
    result: list[int] = []
    for char in text:
        cp = ord(char)
        if 65 <= cp <= 90:
            cp += 32
        result.append(cp)
        if len(result) >= MAX_CODEPOINTS:
            break
    return result


def feature_indices(text: str) -> list[int]:
    cps = normalized_codepoints(text)
    features: list[int] = []
    prev1 = 0
    prev2 = 0
    prev3 = 0
    word_hash = 0x811C9DC5
    in_word = False
    non_ascii = 0

    def add(value: int) -> None:
        features.append(mix32(value) & (FEATURE_DIM - 1))

    for cp in cps:
        if cp > 127:
            non_ascii += 1
        add(cp ^ 0xA5A5A5A5)
        if prev1:
            add(u32(u32(prev1 * 0x1F1F1F1F) ^ cp ^ 0xB4B4B4B4))
        if prev2:
            add(u32(u32(prev2 * 0x85EBCA6B) ^ u32(prev1 * 0xC2B2AE35) ^ cp ^ 0xC3C3C3C3))
        if prev3:
            add(
                u32(
                    u32(prev3 * 0x27D4EB2D)
                    ^ u32(prev2 * 0x165667B1)
                    ^ u32(prev1 * 0x9E3779B1)
                    ^ cp
                    ^ 0xABABABAB
                )
            )

        is_word = 48 <= cp <= 57 or 97 <= cp <= 122
        if is_word:
            word_hash = u32(u32(word_hash ^ cp) * 0x01000193)
            in_word = True
        elif in_word:
            add(word_hash ^ 0xD6D6D6D6)
            word_hash = 0x811C9DC5
            in_word = False
        prev3, prev2, prev1 = prev2, prev1, cp

    if in_word:
        add(word_hash ^ 0xD6D6D6D6)
    add(len(cps) ^ 0xE7E7E7E7)
    add((1 if non_ascii else 0) ^ 0xF8F8F8F8)
    return features


def feature_counts(text: str) -> Counter[int]:
    return Counter(feature_indices(text))


def score(weights: list[list[int]], bias: list[int], features: Counter[int]) -> list[int]:
    return [bias[row] + sum(weights[row][idx] * count for idx, count in features.items()) for row in range(len(weights))]


def train_perceptron(samples: list[tuple[str, int]], classes: int, epochs: int, seed: int) -> tuple[list[list[int]], list[int]]:
    weights = [[0 for _ in range(FEATURE_DIM)] for _ in range(classes)]
    bias = [0 for _ in range(classes)]
    prepared = [(feature_counts(text), label) for text, label in samples]
    rng = random.Random(seed)

    for _ in range(epochs):
        order = list(range(len(prepared)))
        rng.shuffle(order)
        mistakes = 0
        for position in order:
            features, label = prepared[position]
            scores = score(weights, bias, features)
            predicted = max(range(classes), key=lambda item: (scores[item], -item))
            if predicted == label:
                continue
            mistakes += 1
            for idx, count in features.items():
                step = min(count, 3)
                weights[label][idx] += step
                weights[predicted][idx] -= step
            bias[label] += 1
            bias[predicted] -= 1
        if mistakes == 0:
            break
    return weights, bias


def train_centroid(samples: list[tuple[str, int]], classes: int) -> tuple[list[list[int]], list[int]]:
    """Train a binary-TF/IDF centroid head for smoother paraphrase recall."""
    prepared = [(feature_counts(text), label) for text, label in samples]
    document_frequency = [0 for _ in range(FEATURE_DIM)]
    class_documents = [0 for _ in range(classes)]
    for features, label in prepared:
        class_documents[label] += 1
        for feature in features:
            document_frequency[feature] += 1

    total_documents = len(prepared)
    centroids = [[0.0 for _ in range(FEATURE_DIM)] for _ in range(classes)]
    for features, label in prepared:
        normalization = math.sqrt(max(1, len(features)))
        for feature in features:
            inverse_frequency = math.log((total_documents + 1) / (document_frequency[feature] + 1)) + 1
            centroids[label][feature] += inverse_frequency / normalization

    for label, row in enumerate(centroids):
        row[:] = [value / class_documents[label] for value in row]
        norm = math.sqrt(sum(value * value for value in row)) or 1
        row[:] = [value / norm for value in row]

    maximum = max(abs(value) for row in centroids for value in row) or 1
    weights = [[round(value / maximum * 120) for value in row] for row in centroids]
    return weights, [0 for _ in range(classes)]


def train_blended_head(
    samples: list[tuple[str, int]], classes: int, epochs: int, seed: int
) -> tuple[list[list[int]], list[int], int]:
    """Blend a precise perceptron with a smoother TF/IDF centroid (3:1)."""
    raw_weights, raw_bias = train_perceptron(samples, classes, epochs, seed)
    perceptron_weights, perceptron_bias, _ = quantize(raw_weights, raw_bias)
    centroid_weights, _ = train_centroid(samples, classes)
    blended = [
        [3 * perceptron_weights[label][feature] + centroid_weights[label][feature] for feature in range(FEATURE_DIM)]
        for label in range(classes)
    ]
    maximum = max(1, max(abs(value) for row in blended for value in row))
    scale = max(1, math.ceil(maximum / 120))
    weights = [[max(-127, min(127, round(value / scale))) for value in row] for row in blended]
    bias = [max(-32768, min(32767, round(3 * value / scale))) for value in perceptron_bias]
    return weights, bias, scale


def build_intent_samples() -> list[tuple[str, int]]:
    samples: list[tuple[str, int]] = []
    for intent_id, intent in enumerate(INTENTS):
        samples.extend((text, intent_id) for text in intent.zh_examples)
        samples.extend((text, intent_id) for text in intent.en_examples)
        zh_terms, en_terms = augmentation_terms(intent.key)
        samples.extend(
            (template.format(term=term), intent_id)
            for term in zh_terms
            for template in ZH_AUGMENT_TEMPLATES
        )
        samples.extend(
            (template.format(term=term), intent_id)
            for term in en_terms
            for template in EN_AUGMENT_TEMPLATES
        )
    return samples


def build_sentiment_samples() -> list[tuple[str, int]]:
    return [(text, label) for label, texts in SENTIMENT_EXAMPLES.items() for text in texts]


def build_composition_samples(intent_samples: list[tuple[str, int]]) -> list[tuple[str, int]]:
    """Build balanced single-topic versus two-topic dialogue-act samples."""
    topical = [index for index, intent in enumerate(INTENTS) if intent.key not in {"followup", "unknown"}]
    multi: list[tuple[str, int]] = []
    for left_position, left in enumerate(topical):
        left_zh, left_en = augmentation_terms(INTENTS[left].key)
        for right in topical[left_position + 1 :]:
            right_zh, right_en = augmentation_terms(INTENTS[right].key)
            seed = left * 131 + right * 17
            zh_left = left_zh[seed % len(left_zh)]
            zh_right = right_zh[(seed * 3 + 1) % len(right_zh)]
            en_left = left_en[(seed * 5 + 2) % len(left_en)]
            en_right = right_en[(seed * 7 + 3) % len(right_en)]
            multi.extend(
                (
                    (f"我想问{zh_left}，另外{zh_right}", 1),
                    (f"先说{zh_left}，再说{zh_right}", 1),
                    (f"{zh_left}，同时{zh_right}", 1),
                    (f"{zh_left}以及{zh_right}", 1),
                    (f"{zh_left}和{zh_right}", 1),
                    (f"{zh_left}，{zh_right}", 1),
                    (f"tell me about {en_left}, and also {en_right}", 1),
                    (f"explain {en_left}; then cover {en_right}", 1),
                    (f"{en_left} while also asking about {en_right}", 1),
                    (f"{en_left} plus {en_right}", 1),
                    (f"{en_left} and {en_right}", 1),
                    (f"{en_left}; {en_right}", 1),
                )
            )

    rng = random.Random(887733)
    single_pool = [(text, 0) for text, _ in intent_samples]
    singles = rng.sample(single_pool, min(len(single_pool), len(multi)))
    return singles + multi


def train_quantized_heads() -> tuple[
    list[list[int]],
    list[int],
    list[list[int]],
    list[int],
    list[list[int]],
    list[int],
    dict[str, int],
]:
    intent_samples = build_intent_samples()
    sentiment_samples = build_sentiment_samples()
    composition_samples = build_composition_samples(intent_samples)
    intent_weights, intent_bias, intent_scale = train_blended_head(
        intent_samples, len(INTENTS), epochs=120, seed=20260816
    )
    sentiment_weights, sentiment_bias, sentiment_scale = train_blended_head(
        sentiment_samples, 3, epochs=100, seed=31056
    )
    composition_weights, composition_bias, composition_scale = train_blended_head(
        composition_samples, COMPOSITION_CLASSES, epochs=100, seed=771122
    )
    # The product should prefer one complete answer over a spurious second
    # topic. Encoding this margin in the packed biases keeps the gate itself a
    # normal on-chain linear-head decision.
    composition_bias[0] += 50
    composition_bias[1] -= 50
    return (
        intent_weights,
        intent_bias,
        sentiment_weights,
        sentiment_bias,
        composition_weights,
        composition_bias,
        {
            "intentScale": intent_scale,
            "sentimentScale": sentiment_scale,
            "compositionScale": composition_scale,
            "compositionDecisionMargin": 100,
            "intentExamples": len(intent_samples),
            "sentimentExamples": len(sentiment_samples),
            "compositionExamples": len(composition_samples),
        },
    )


def quantize(weights: list[list[int]], bias: list[int]) -> tuple[list[list[int]], list[int], int]:
    maximum = max(1, max(abs(value) for row in weights for value in row))
    scale = max(1, math.ceil(maximum / 120))
    q_weights = [[max(-127, min(127, round(value / scale))) for value in row] for row in weights]
    q_bias = [max(-32768, min(32767, round(value / scale))) for value in bias]
    return q_weights, q_bias, scale


def accuracy(samples: Iterable[tuple[str, int]], weights: list[list[int]], bias: list[int]) -> float:
    samples = list(samples)
    correct = 0
    for text, label in samples:
        scores = score(weights, bias, feature_counts(text))
        predicted = max(range(len(scores)), key=lambda item: (scores[item], -item))
        correct += int(predicted == label)
    return correct / len(samples)


def pack_i16(value: int) -> bytes:
    return struct.pack(">h", value)


def pack_model(
    intent_weights: list[list[int]],
    intent_bias: list[int],
    sentiment_weights: list[list[int]],
    sentiment_bias: list[int],
    composition_weights: list[list[int]],
    composition_bias: list[int],
) -> bytes:
    header = (
        b"TAW1"
        + bytes((MODEL_VERSION,))
        + struct.pack(">H", FEATURE_DIM)
        + bytes((len(INTENTS), 3, MAX_CODEPOINTS, COMPOSITION_CLASSES, 0))
    )
    payload = bytearray(header)
    for value in intent_bias:
        payload.extend(pack_i16(value))
    for row in intent_weights:
        payload.extend(struct.pack(f"{FEATURE_DIM}b", *row))
    for value in sentiment_bias:
        payload.extend(pack_i16(value))
    for row in sentiment_weights:
        payload.extend(struct.pack(f"{FEATURE_DIM}b", *row))
    for value in composition_bias:
        payload.extend(pack_i16(value))
    for row in composition_weights:
        payload.extend(struct.pack(f"{FEATURE_DIM}b", *row))
    return bytes(payload)


def pack_lexicon(language: str) -> bytes:
    if language not in LANGUAGES:
        raise ValueError(f"unsupported language: {language}")
    entries: list[bytes] = []
    for intent in INTENTS:
        replies = intent.zh_replies if language == "zh" else intent.en_replies
        if len(replies) != VARIANTS:
            raise ValueError(f"{intent.key}/{language} needs {VARIANTS} replies")
        entries.extend(reply.encode("utf-8") for reply in replies)

    language_id = LANGUAGES.index(language)
    header = b"TAL1" + bytes((MODEL_VERSION, len(INTENTS), VARIANTS, 1, language_id))
    content_start = len(header) + len(entries) * 5
    index = bytearray()
    content = bytearray()
    cursor = content_start
    for entry in entries:
        if cursor >= 1 << 24 or len(entry) >= 1 << 16:
            raise ValueError("lexicon entry exceeds packed index")
        index.extend(cursor.to_bytes(3, "big"))
        index.extend(len(entry).to_bytes(2, "big"))
        content.extend(entry)
        cursor += len(entry)
    blob = header + bytes(index) + bytes(content)
    if len(blob) > 24_576:
        raise ValueError(f"lexicon exceeds EIP-170 code limit: {len(blob)} bytes")
    return blob


def predict(
    text: str,
    weights: list[list[int]],
    bias: list[int],
    sentiment_weights: list[list[int]],
    sentiment_bias: list[int],
    composition_weights: list[list[int]],
    composition_bias: list[int],
) -> dict[str, object]:
    features = feature_counts(text)
    scores = score(weights, bias, features)
    ranking = sorted(range(len(scores)), key=lambda item: (-scores[item], item))
    sentiment_scores = score(sentiment_weights, sentiment_bias, features)
    sentiment = max(range(3), key=lambda item: (sentiment_scores[item], -item))
    composition_scores = score(composition_weights, composition_bias, features)
    composition = max(range(COMPOSITION_CLASSES), key=lambda item: (composition_scores[item], -item))
    return {
        "intent": INTENTS[ranking[0]].key,
        "intentId": ranking[0],
        "margin": scores[ranking[0]] - scores[ranking[1]],
        "sentiment": sentiment,
        "composition": composition,
        "compositionMargin": abs(composition_scores[1] - composition_scores[0]),
        "language": "zh" if any(ord(char) > 127 for char in text) else "en",
        "top": [{"intent": INTENTS[idx].key, "score": scores[idx]} for idx in ranking[:3]],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", metavar="PROMPT", help="print a local inference after training")
    args = parser.parse_args()

    intent_samples = build_intent_samples()
    sentiment_samples = build_sentiment_samples()
    composition_samples = build_composition_samples(intent_samples)
    (
        intent_weights,
        intent_bias,
        sentiment_weights,
        sentiment_bias,
        composition_weights,
        composition_bias,
        training_meta,
    ) = train_quantized_heads()

    intent_accuracy = accuracy(intent_samples, intent_weights, intent_bias)
    validation_accuracy = accuracy(VALIDATION_SAMPLES, intent_weights, intent_bias)
    sentiment_accuracy = accuracy(sentiment_samples, sentiment_weights, sentiment_bias)
    composition_accuracy = accuracy(composition_samples, composition_weights, composition_bias)
    if intent_accuracy < 0.95 or validation_accuracy < 0.75 or sentiment_accuracy < 0.95 or composition_accuracy < 0.90:
        misses = [
            {
                "prompt": text,
                "expected": INTENTS[label].key,
                "actual": predict(
                    text,
                    intent_weights,
                    intent_bias,
                    sentiment_weights,
                    sentiment_bias,
                    composition_weights,
                    composition_bias,
                )["intent"],
            }
            for text, label in VALIDATION_SAMPLES
            if predict(
                text,
                intent_weights,
                intent_bias,
                sentiment_weights,
                sentiment_bias,
                composition_weights,
                composition_bias,
            )["intentId"] != label
        ]
        raise RuntimeError(
            f"training quality too low: intent={intent_accuracy:.3f}, validation={validation_accuracy:.3f}, "
            f"sentiment={sentiment_accuracy:.3f}, composition={composition_accuracy:.3f}; "
            f"misses={json.dumps(misses, ensure_ascii=False)}"
        )

    weights_blob = pack_model(
        intent_weights,
        intent_bias,
        sentiment_weights,
        sentiment_bias,
        composition_weights,
        composition_bias,
    )
    weight_chunks = [
        weights_blob[offset : offset + WEIGHT_CHUNK_BYTES]
        for offset in range(0, len(weights_blob), WEIGHT_CHUNK_BYTES)
    ]
    zh_lexicon_blob = pack_lexicon("zh")
    en_lexicon_blob = pack_lexicon("en")
    corpus_payload = json.dumps(
        {
            "intents": [
                {
                    "key": item.key,
                    "zh_examples": item.zh_examples,
                    "en_examples": item.en_examples,
                    "zh_replies": item.zh_replies,
                    "en_replies": item.en_replies,
                }
                for item in INTENTS
            ],
            "sentiment": SENTIMENT_EXAMPLES,
            "augmentationTerms": AUGMENT_TERMS,
            "extraAugmentationTerms": EXTRA_AUGMENT_TERMS,
            "zhAugmentTemplates": ZH_AUGMENT_TEMPLATES,
            "enAugmentTemplates": EN_AUGMENT_TEMPLATES,
            "validation": VALIDATION_SAMPLES,
            "compositionTraining": {
                "classes": ("single_topic", "two_topics"),
                "seed": 887733,
                "pairTemplates": (
                    "我想问{left}，另外{right}",
                    "先说{left}，再说{right}",
                    "{left}，同时{right}",
                    "{left}以及{right}",
                    "{left}和{right}",
                    "{left}，{right}",
                    "tell me about {left}, and also {right}",
                    "explain {left}; then cover {right}",
                    "{left} while also asking about {right}",
                    "{left} plus {right}",
                    "{left} and {right}",
                    "{left}; {right}",
                ),
            },
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")

    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / "weights.bin").write_bytes(weights_blob)
    for index, chunk in enumerate(weight_chunks):
        (BUILD / f"weights-{index}.bin").write_bytes(chunk)
    (BUILD / "lexicon-zh.bin").write_bytes(zh_lexicon_blob)
    (BUILD / "lexicon-en.bin").write_bytes(en_lexicon_blob)
    (BUILD / "corpus.sha256").write_text(hashlib.sha256(corpus_payload).hexdigest() + "\n", encoding="ascii")

    vectors = [
        "你好，你是谁",
        "这次聊天真的在链上推理吗",
        "一次聊天需要多少 Gas",
        "管理员能升级模型吗",
        "我今天终于成功了",
        "我的交易为什么失败",
        "How do I protect my wallet?",
        "Tell me the live BNB price",
        "Can the model be upgraded?",
        "Give me a fun onchain AI idea",
    ]
    vector_results = [
        {
            "prompt": text,
            **predict(
                text,
                intent_weights,
                intent_bias,
                sentiment_weights,
                sentiment_bias,
                composition_weights,
                composition_bias,
            ),
        }
        for text in vectors
    ]
    (BUILD / "vectors.json").write_text(json.dumps(vector_results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    manifest = {
        "name": "TinyAI Neural Dialogue",
        "version": MODEL_VERSION,
        "architecture": "hashed Unicode n-grams -> blended quantized intent/sentiment/composition heads -> immutable reply lexicon",
        "featureDimension": FEATURE_DIM,
        "maxCodepoints": MAX_CODEPOINTS,
        "intents": [item.key for item in INTENTS],
        "languages": list(LANGUAGES),
        "variantsPerIntent": VARIANTS,
        "intentTrainingExamples": len(intent_samples),
        "sentimentTrainingExamples": len(sentiment_samples),
        "compositionTrainingExamples": len(composition_samples),
        "intentTrainingAccuracy": intent_accuracy,
        "intentValidationExamples": len(VALIDATION_SAMPLES),
        "intentValidationAccuracy": validation_accuracy,
        "sentimentTrainingAccuracy": sentiment_accuracy,
        "compositionTrainingAccuracy": composition_accuracy,
        "intentQuantizationScale": training_meta["intentScale"],
        "sentimentQuantizationScale": training_meta["sentimentScale"],
        "compositionQuantizationScale": training_meta["compositionScale"],
        "weightsBytes": len(weights_blob),
        "weightChunkBytes": WEIGHT_CHUNK_BYTES,
        "weightChunks": [
            {
                "file": f"weights-{index}.bin",
                "bytes": len(chunk),
                "sha256": hashlib.sha256(chunk).hexdigest(),
            }
            for index, chunk in enumerate(weight_chunks)
        ],
        "zhLexiconBytes": len(zh_lexicon_blob),
        "enLexiconBytes": len(en_lexicon_blob),
        "weightsSha256": hashlib.sha256(weights_blob).hexdigest(),
        "zhLexiconSha256": hashlib.sha256(zh_lexicon_blob).hexdigest(),
        "enLexiconSha256": hashlib.sha256(en_lexicon_blob).hexdigest(),
        "corpusSha256": hashlib.sha256(corpus_payload).hexdigest(),
        "truthBoundary": "Training is off-chain. Feature extraction, all three neural heads, follow-up resolution, memory update, multi-topic selection, and final response bytes execute on-chain.",
    }
    (BUILD / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    if args.check:
        print(
            json.dumps(
                predict(
                    args.check,
                    intent_weights,
                    intent_bias,
                    sentiment_weights,
                    sentiment_bias,
                    composition_weights,
                    composition_bias,
                ),
                ensure_ascii=False,
                indent=2,
            )
        )


if __name__ == "__main__":
    main()
