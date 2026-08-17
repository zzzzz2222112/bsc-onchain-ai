// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Immutable known-domain renderer and universal prompt compositor for TinyAI v4.1.
/// @dev Kept separate from the reasoner so both runtime bytecodes remain below EIP-170.
contract TinyAIKnowledgeV4 {
    bytes32 public constant KNOWLEDGE_HASH =
        keccak256("TinyAI-v4.1|universal-router|facts-v1|forward-rules-v1|candidate-verifier|prompt-compositor");

    uint8 private constant DEEP_DEPTH = 1;

    uint8 private constant DOMAIN_UNKNOWN = 0;
    uint8 private constant DOMAIN_IDENTITY = 1;
    uint8 private constant DOMAIN_AI = 2;
    uint8 private constant DOMAIN_HUMAN = 3;
    uint8 private constant DOMAIN_BSC = 4;
    uint8 private constant DOMAIN_BLOCKCHAIN = 5;
    uint8 private constant DOMAIN_GAS = 6;
    uint8 private constant DOMAIN_WALLET = 7;
    uint8 private constant DOMAIN_TOKEN = 8;

    uint8 private constant QUERY_UNKNOWN = 0;
    uint8 private constant QUERY_GREETING = 1;
    uint8 private constant QUERY_DEFINE = 2;
    uint8 private constant QUERY_WHY = 3;
    uint8 private constant QUERY_HOW = 4;
    uint8 private constant QUERY_COMPARE = 5;
    uint8 private constant QUERY_RISK = 6;

    uint64 private constant CONCLUSION_GAS_NOT_INTELLIGENCE = uint64(1) << 4;
    uint64 private constant CONCLUSION_ONCHAIN_VERIFIABLE = uint64(1) << 6;
    uint64 private constant CONCLUSION_SUPPLY_RISK = uint64(1) << 7;
    uint64 private constant CONCLUSION_UPGRADE_RISK = uint64(1) << 8;
    uint64 private constant CONCLUSION_SPECULATIVE_ANSWER = uint64(1) << 13;

    function render(
        bool chinese,
        uint8 domain,
        uint8 queryType,
        uint8 depth,
        uint64 conclusions,
        string calldata prompt,
        bytes32 promptHash
    ) external pure returns (string memory response) {
        if ((conclusions & CONCLUSION_SPECULATIVE_ANSWER) != 0 || domain == DOMAIN_UNKNOWN) {
            response = _renderUniversal(chinese, queryType, prompt, uint8(uint256(promptHash)) & 3);
        } else if ((conclusions & CONCLUSION_GAS_NOT_INTELLIGENCE) != 0) {
            response = chinese
                ? unicode"Gas 是计算预算，不是智商倍率。预算提高十倍，只有在它被用于更多检索、候选推导和结果复核时才会变聪明；算法不变时，消耗十倍 Gas 也不会自动得到十倍能力。"
                : "Gas is a compute budget, not an intelligence multiplier. Ten times the budget helps only when the architecture spends it on retrieval, derivation, and verification; unchanged logic does not become ten times smarter.";
        } else if ((conclusions & CONCLUSION_SUPPLY_RISK) != 0) {
            response = chinese
                ? unicode"这个条件组合存在供应风险：合约允许增发，同时管理员仍能调用该能力。结论不是一定会作恶，而是供应上限不能只靠口头承诺；还要检查权限归属、时间锁和真实调用记录。"
                : "This combination creates supply risk: minting exists and an administrator can still invoke it. That does not prove abuse, but the supply cap depends on authority, timelocks, and actual calls rather than code immutability.";
        } else if ((conclusions & CONCLUSION_UPGRADE_RISK) != 0) {
            response = chinese
                ? unicode"代理本身不是后门，但管理员可升级实现意味着规则仍能改变。需要继续检查升级管理员、时间锁、实现地址和历史升级事件。"
                : "A proxy is not automatically a backdoor, but an administrator-controlled implementation can change the rules. Inspect the upgrade authority, timelock, implementation, and upgrade history.";
        } else if (domain == DOMAIN_BSC) {
            response = chinese
                ? unicode"BSC（BNB Smart Chain）是一条兼容 EVM 的区块链，使用 BNB 支付 Gas，并能运行 Solidity 智能合约。它与以太坊工具生态相近，但验证者、治理和链上状态属于 BNB Chain 自己。"
                : "BSC, or BNB Smart Chain, is an EVM-compatible blockchain. It uses BNB for gas and runs Solidity smart contracts while maintaining its own validators, governance, and chain state.";
        } else if (domain == DOMAIN_HUMAN) {
            response = chinese
                ? unicode"人类既是生物个体，也是会使用语言、建立社会关系、积累文化并反思自身行为的群体。我能陈述这些结构化事实，但不能声称自己拥有人的意识或生活经验。"
                : "Humans are biological individuals and social beings who use language, build relationships, accumulate culture, and reflect on their actions. I can reason over those facts but do not claim human consciousness or lived experience.";
        } else if (domain == DOMAIN_WALLET) {
            response = chinese
                ? unicode"钱包安全的根控制点是私钥和签名。不要泄露助记词；签名前核对链、目标合约、资产、数量和授权额度；不理解的无限授权应拒绝。"
                : "Wallet security is rooted in private-key custody and informed signatures. Never reveal a seed phrase, and verify the chain, contract, asset, amount, and allowance before signing.";
        } else if (domain == DOMAIN_GAS) {
            response = chinese
                ? unicode"Gas 衡量 EVM 执行工作量，最终费用约等于 Gas Used × Gas Price。更多 Gas 允许更多步骤，但结果质量仍取决于这些步骤执行了什么算法。"
                : "Gas measures EVM work, and the fee is approximately gas used times gas price. A larger budget permits more steps, but quality still depends on the algorithm those steps execute.";
        } else if (domain == DOMAIN_BLOCKCHAIN) {
            response = chinese
                ? unicode"区块链把交易按共识排序，并让多个节点重放同一状态转换。它擅长公开验证和减少单点控制，但不会自动保证资产有价值、合约无漏洞或数据真实。"
                : "A blockchain orders transactions by consensus and lets nodes replay the same state transitions. It improves public verification and reduces single-point control, but does not guarantee value, bug-free contracts, or truthful inputs.";
        } else if (domain == DOMAIN_TOKEN) {
            response = chinese
                ? unicode"代币是合约记录的可转移单位。判断它是否可靠，需要分别检查增发权限、冻结或黑名单、税费、持仓、流动性、LP 控制和真实卖出路径。"
                : "A token is a transferable unit tracked by a contract. Evaluate mint authority, freezes or blacklists, taxes, holders, liquidity, LP control, and an actual sell route separately.";
        } else if (domain == DOMAIN_IDENTITY || domain == DOMAIN_AI) {
            if ((conclusions & CONCLUSION_ONCHAIN_VERIFIABLE) != 0) {
                response = chinese
                    ? unicode"我是 TinyAI v4 的有界链上推理原型。语言解析、事实读取、规则推导、结论验证、回答渲染和记忆都在 EVM 内执行；训练与知识编写发生在链下，这是明确边界。"
                    : "I am the bounded TinyAI v4 on-chain reasoner. Parsing, fact loading, rule derivation, verification, rendering, and memory execute in the EVM; training and knowledge authoring remain off-chain.";
            } else {
                response = chinese
                    ? unicode"我是 TinyAI v4：不是链上 ChatGPT，而是一台有界推理机。我会先识别问题，再加载事实、应用规则、验证结论，并公开一条可重放的思考轨迹。"
                    : "I am TinyAI v4: not an on-chain ChatGPT, but a bounded reasoning machine that routes a question, loads facts, applies rules, verifies conclusions, and exposes a replayable trace.";
            }
        } else {
            response = chinese
                ? unicode"我识别到了问题主题，但当前知识规则不足以形成可靠结论，因此不会用无关句子冒充答案。"
                : "I recognized the topic, but the current knowledge rules are insufficient for a reliable conclusion, so I will not substitute an unrelated answer.";
        }

        if (depth == DEEP_DEPTH) {
            response = string.concat(
                response,
                chinese
                    ? unicode"\n\n深度模式已经在链上执行事实加载、规则闭包和结论验证；轨迹哈希可用于逐步复核这次推导。"
                    : "\n\nDeep mode executed fact loading, rule closure, and conclusion verification on-chain; the trace hash commits to every bounded step."
            );
        }
    }

    function _renderUniversal(bool chinese, uint8 queryType, string calldata prompt, uint8 variant)
        private
        pure
        returns (string memory)
    {
        if (chinese) {
            string memory chineseLead = string.concat(
                unicode"关于“",
                prompt,
                unicode"”，我的链上知识没有直接事实；下面是低置信度推测："
            );
            if (queryType == QUERY_GREETING) {
                return string.concat(
                    unicode"你好。你提到“",
                    prompt,
                    unicode"”。我可以继续尝试分析任何主题，但陌生领域的回答可能不准确。 "
                );
            }
            if (queryType == QUERY_WHY) {
                if (variant == 0) {
                    return string.concat(
                        chineseLead,
                        unicode"它更可能由多个条件共同造成，而不是单一原因。先区分直接机制、背景条件和结果之间是否真的存在因果关系。 "
                    );
                }
                if (variant == 1) {
                    return string.concat(
                        chineseLead,
                        unicode"一个合理解释通常要同时考虑起因、过程和反馈；只看到结果就倒推原因，容易把相关性误当成因果。 "
                    );
                }
                if (variant == 2) {
                    return string.concat(
                        chineseLead,
                        unicode"原因可能分成结构因素和偶发因素。可以先找在不同场景都重复出现的部分，再检查反例。 "
                    );
                }
                return string.concat(
                    chineseLead,
                    unicode"我倾向于把它看成多因素问题：资源、规则、环境和时间顺序都可能改变结果，需要外部证据确认主因。 "
                );
            }
            if (queryType == QUERY_HOW) {
                if (variant == 0) {
                    return string.concat(
                        chineseLead,
                        unicode"先明确想得到的结果和不能违反的限制，再做最小可逆尝试，记录结果，最后根据证据扩大或撤回。 "
                    );
                }
                if (variant == 1) {
                    return string.concat(
                        chineseLead,
                        unicode"可以拆成目标、输入、步骤、验证四部分；优先处理最不确定且失败成本最低的一步。 "
                    );
                }
                if (variant == 2) {
                    return string.concat(
                        chineseLead,
                        unicode"先找一个可重复的小例子，确认机制确实成立，再增加规模。不要一开始就把多个变量同时改变。 "
                    );
                }
                return string.concat(
                    chineseLead,
                    unicode"建议先收集现状，列出两到三个方案，用成本、风险和可验证性排序，然后小范围执行最优方案。 "
                );
            }
            if (queryType == QUERY_COMPARE) {
                if (variant == 0) {
                    return string.concat(
                        chineseLead,
                        unicode"比较时应固定同一目标，再分别看成本、效果、风险和可逆性；某个维度更大，不代表整体一定更好。 "
                    );
                }
                if (variant == 1) {
                    return string.concat(
                        chineseLead,
                        unicode"两者可能适合不同条件。先确定你更重视速度、质量、价格还是控制权，再做结论。 "
                    );
                }
                if (variant == 2) {
                    return string.concat(
                        chineseLead,
                        unicode"不要只比表面数字；还要比较计算方法、样本范围和失败时的后果。 "
                    );
                }
                return string.concat(
                    chineseLead,
                    unicode"更合理的做法是建立同一组评价标准并逐项打分，同时保留未知项，而不是直接选一个绝对赢家。 "
                );
            }
            if (queryType == QUERY_RISK) {
                if (variant == 0) {
                    return string.concat(
                        chineseLead,
                        unicode"先看最坏情况下谁会损失什么、谁能改变规则，以及损失是否可逆；在证据不足时不要把‘还没出事’当成安全。 "
                    );
                }
                if (variant == 1) {
                    return string.concat(
                        chineseLead,
                        unicode"风险通常来自权限、依赖、激励和操作失误。应分别检查发生概率、影响范围和补救成本。 "
                    );
                }
                if (variant == 2) {
                    return string.concat(
                        chineseLead,
                        unicode"可以先排除单点故障和不可逆动作，再用小额或隔离环境验证；无法验证的承诺应按未知风险处理。 "
                    );
                }
                return string.concat(
                    chineseLead,
                    unicode"安全结论需要具体对象和当前证据。保守做法是限制暴露、保留退出路径，并持续复核状态变化。 "
                );
            }
            if (queryType == QUERY_DEFINE) {
                if (variant == 0) {
                    return string.concat(
                        chineseLead,
                        unicode"它可以先被理解为由对象、规则和作用范围组成的概念；准确含义仍取决于你使用它的上下文。 "
                    );
                }
                if (variant == 1) {
                    return string.concat(
                        chineseLead,
                        unicode"要解释它，最好先说明它是什么、解决什么问题、如何运作，以及它不包含什么。 "
                    );
                }
                if (variant == 2) {
                    return string.concat(
                        chineseLead,
                        unicode"这个词可能有多个定义。应先限定领域和时间，再寻找能被验证的共同特征。 "
                    );
                }
                return string.concat(
                    chineseLead,
                    unicode"我会先把它当作一个待定义对象：确认边界、组成部分和可观察行为后，才适合下更具体的结论。 "
                );
            }
            if (variant == 0) {
                return string.concat(
                    chineseLead,
                    unicode"可以先把问题拆成已知事实、未知条件和想要的结果；目前我只能给出结构性判断，不能保证事实正确。 "
                );
            }
            if (variant == 1) {
                return string.concat(
                    chineseLead,
                    unicode"我倾向于先检查定义和前提是否成立，再讨论可能结果；缺少上下文时，任何肯定答案都可能是幻觉。 "
                );
            }
            if (variant == 2) {
                return string.concat(
                    chineseLead,
                    unicode"一个稳妥起点是列出可验证证据和反例，然后逐步缩小结论范围。我的回答只提供这个推理方向。 "
                );
            }
            return string.concat(
                chineseLead,
                unicode"这个问题可能跨越我的知识边界。我仍会给出分析框架，但具体事实需要外部资料或更完整上下文复核。 "
            );
        }

        string memory lead = string.concat(
            "For your question, \"",
            prompt,
            "\", my on-chain knowledge has no direct fact. This is a low-confidence hypothesis: "
        );
        if (queryType == QUERY_GREETING) {
            return string.concat(
                "Hello. You said \"", prompt, "\". I can attempt any topic, but unfamiliar answers may be inaccurate."
            );
        }
        if (queryType == QUERY_WHY) {
            if (variant == 0) {
                return string.concat(
                    lead,
                    "multiple conditions are more likely than one isolated cause. Separate mechanism, background conditions, and observed outcome."
                );
            }
            if (variant == 1) {
                return string.concat(
                    lead,
                    "a useful explanation should cover cause, process, and feedback instead of treating correlation as causation."
                );
            }
            if (variant == 2) {
                return string.concat(
                    lead,
                    "structural and accidental factors may interact. Look for repeated patterns and counterexamples."
                );
            }
            return string.concat(
                lead,
                "resources, rules, environment, and timing may all change the result; external evidence is needed to identify the main cause."
            );
        }
        if (queryType == QUERY_HOW) {
            if (variant == 0) {
                return string.concat(
                    lead,
                    "define the desired result and constraints, run the smallest reversible experiment, record evidence, then expand or undo it."
                );
            }
            if (variant == 1) {
                return string.concat(
                    lead,
                    "split the work into goal, inputs, steps, and verification, starting with the cheapest uncertain step."
                );
            }
            if (variant == 2) {
                return string.concat(
                    lead,
                    "build one repeatable small example before increasing scale, and avoid changing several variables at once."
                );
            }
            return string.concat(
                lead,
                "collect the current state, compare a few options by cost, risk, and verifiability, then test the strongest option narrowly."
            );
        }
        if (queryType == QUERY_COMPARE) {
            if (variant == 0) {
                return string.concat(
                    lead,
                    "hold the goal constant and compare cost, effect, risk, and reversibility; a larger number on one axis is not an overall win."
                );
            }
            if (variant == 1) {
                return string.concat(
                    lead,
                    "the alternatives may fit different conditions. Decide whether speed, quality, price, or control matters most."
                );
            }
            if (variant == 2) {
                return string.concat(
                    lead, "compare methods, sample scope, and failure consequences rather than surface numbers alone."
                );
            }
            return string.concat(
                lead, "use one shared scorecard and preserve unknowns instead of declaring an absolute winner."
            );
        }
        if (queryType == QUERY_RISK) {
            if (variant == 0) {
                return string.concat(
                    lead,
                    "identify who loses what in the worst case, who can change the rules, and whether the loss is reversible."
                );
            }
            if (variant == 1) {
                return string.concat(
                    lead,
                    "risk often comes from authority, dependencies, incentives, and operator error; assess probability, impact, and recovery cost separately."
                );
            }
            if (variant == 2) {
                return string.concat(
                    lead,
                    "remove single points of failure and irreversible actions first, then test in an isolated or low-value setting."
                );
            }
            return string.concat(
                lead,
                "limit exposure, preserve an exit route, and re-check changing evidence instead of treating no past failure as proof of safety."
            );
        }
        if (queryType == QUERY_DEFINE) {
            if (variant == 0) {
                return string.concat(
                    lead,
                    "treat it as a concept with an object, rules, and scope; the exact meaning still depends on context."
                );
            }
            if (variant == 1) {
                return string.concat(
                    lead, "explain what it is, which problem it addresses, how it operates, and what it excludes."
                );
            }
            if (variant == 2) {
                return string.concat(
                    lead,
                    "the term may have several definitions, so constrain the field and time before identifying verifiable common properties."
                );
            }
            return string.concat(
                lead,
                "first establish boundaries, components, and observable behavior before making a more specific claim."
            );
        }
        if (variant == 0) {
            return string.concat(
                lead,
                "separate known facts, unknown conditions, and the desired result. I can offer structure here, not factual certainty."
            );
        }
        if (variant == 1) {
            return string.concat(
                lead,
                "check whether the definition and premises hold before predicting results; without context, certainty would be hallucination."
            );
        }
        if (variant == 2) {
            return
                string.concat(lead, "list verifiable evidence and counterexamples, then narrow the claim step by step.");
        }
        return string.concat(
            lead,
            "the topic may exceed my knowledge boundary. I can still provide an analysis frame, but external evidence must verify concrete facts."
        );
    }
}
