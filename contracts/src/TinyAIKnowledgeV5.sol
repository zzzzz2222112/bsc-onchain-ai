// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Immutable fact renderer for TinyAI v5.
/// @dev This module never invents an open-world answer. It either returns one to three
///      authored facts for a supported topic or a polite, explicit knowledge boundary.
contract TinyAIKnowledgeV5 {
    bytes32 public constant KNOWLEDGE_HASH =
        keccak256("TinyAI-v5|v3-trained-router|entity-cues-v1|immutable-facts-v1|evidence-composer|polite-unknown");

    uint8 private constant TOPIC_UNKNOWN = 0;
    uint8 private constant TOPIC_IDENTITY = 1;
    uint8 private constant TOPIC_ONCHAIN = 2;
    uint8 private constant TOPIC_BSC = 3;
    uint8 private constant TOPIC_HUMAN = 4;
    uint8 private constant TOPIC_GAS = 5;
    uint8 private constant TOPIC_WALLET = 6;
    uint8 private constant TOPIC_CONTRACT = 7;
    uint8 private constant TOPIC_TOKEN = 8;
    uint8 private constant TOPIC_DEFI = 9;
    uint8 private constant TOPIC_NFT = 10;
    uint8 private constant TOPIC_TRANSACTION = 11;
    uint8 private constant TOPIC_PRIVACY = 12;
    uint8 private constant TOPIC_GOVERNANCE = 13;
    uint8 private constant TOPIC_PLANNING = 14;
    uint8 private constant TOPIC_MARKET = 15;
    uint8 private constant TOPIC_DIALOGUE = 16;

    uint64 private constant CUE_AI = uint64(1) << 0;
    uint64 private constant CUE_SCALE = uint64(1) << 1;
    uint64 private constant CUE_ADMIN = uint64(1) << 2;
    uint64 private constant CUE_MINT = uint64(1) << 3;
    uint64 private constant CUE_PROXY = uint64(1) << 4;
    uint64 private constant CUE_BLACKLIST = uint64(1) << 5;
    uint64 private constant CUE_LIQUIDITY = uint64(1) << 6;
    uint64 private constant CUE_SIGNATURE = uint64(1) << 7;
    uint64 private constant CUE_PRIVATE_KEY = uint64(1) << 8;
    uint64 private constant CUE_LIVE = uint64(1) << 9;
    uint64 private constant CUE_PRICE = uint64(1) << 10;
    uint64 private constant CUE_SECURITY = uint64(1) << 11;

    struct Retrieval {
        string response;
        string evidence;
        uint16[3] factIds;
        uint8 factCount;
        bool unknown;
    }

    function answer(bool chinese, uint8 topic, uint8, uint64 cues, bool negated, string calldata baseResponse)
        external
        pure
        returns (Retrieval memory result)
    {
        if (topic == TOPIC_UNKNOWN) return _unknown(chinese);
        if (topic == TOPIC_DIALOGUE) {
            result.response = baseResponse;
            result.evidence = chinese
                ? unicode"[9001] 回答来自 v3 训练分类器选中的不可变链上对话词库。"
                : "[9001] The response comes from the immutable on-chain dialogue lexicon selected by the trained v3 classifier.";
            result.factIds[0] = 9001;
            result.factCount = 1;
            return result;
        }

        string memory first;
        string memory second;
        string memory third;
        uint16 firstId;
        uint16 secondId;
        uint16 thirdId;

        if (topic == TOPIC_IDENTITY) {
            firstId = 1101;
            secondId = 1102;
            thirdId = 1103;
            first = chinese
                ? unicode"TinyAI v5 复用 v3 的量化稀疏分类器，再用检索到的链上事实组织回答。"
                : "TinyAI v5 reuses the quantized sparse v3 classifier and composes answers from retrieved on-chain facts.";
            second = chinese
                ? unicode"训练和知识编写发生在链下；部署后的分类、检索、组合、记忆和输出由 EVM 执行。"
                : "Training and knowledge authoring happen off-chain; deployed classification, retrieval, composition, memory, and output execute in the EVM.";
            third = chinese
                ? unicode"它不是通用大模型，也不会在不知道时偷偷连接服务器补答案。"
                : "It is not a general LLM and does not secretly call a server when knowledge is missing.";
        } else if (topic == TOPIC_ONCHAIN) {
            firstId = 1201;
            secondId = 1202;
            thirdId = 1203;
            first = chinese
                ? unicode"真链上推理要求模型数据或知识、执行逻辑和最终输出都能由合约调用复现。"
                : "True on-chain inference requires contract-reproducible model or knowledge data, execution logic, and final output.";
            second = chinese
                ? unicode"对同一合约地址、输入和历史状态执行 eth_call，任何正确节点都应返回相同字节。"
                : "An eth_call with the same contract, input, and history should return identical bytes from every correct node.";
            third = chinese
                ? unicode"把链下答案或它的哈希写上链只能证明记录存在，不能证明推理发生在链上。"
                : "Posting an off-chain answer or its hash proves a record exists, not that inference happened on-chain.";
        } else if (topic == TOPIC_BSC) {
            firstId = 1301;
            secondId = 1302;
            thirdId = 1303;
            first = chinese
                ? unicode"BSC（BNB Smart Chain）是一条兼容 EVM 的区块链，可以运行 Solidity 智能合约。"
                : "BSC, or BNB Smart Chain, is an EVM-compatible blockchain that runs Solidity smart contracts.";
            second = chinese
                ? unicode"用户使用 BNB 支付 Gas；Gas 费用取决于执行工作量和当时的 Gas 价格。"
                : "Users pay gas in BNB; the fee depends on execution work and the current gas price.";
            third = chinese
                ? unicode"它与以太坊工具生态相近，但验证者、治理和链上状态由 BNB Chain 自己维护。"
                : "It resembles Ethereum's tooling ecosystem, while validators, governance, and state belong to BNB Chain.";
        } else if (topic == TOPIC_HUMAN) {
            firstId = 1401;
            secondId = 1402;
            thirdId = 1403;
            first = chinese
                ? unicode"人类是智人这一生物物种的个体，具有身体、神经系统和有限寿命。"
                : "Humans are individuals of the species Homo sapiens, with bodies, nervous systems, and finite lifespans.";
            second = chinese
                ? unicode"人类也通过语言、合作、制度和文化形成社会，并把知识跨代积累。"
                : "Humans also form societies through language, cooperation, institutions, and culture, accumulating knowledge across generations.";
            third = chinese
                ? unicode"我可以陈述这些公开知识，但不能据此声称自己拥有人类意识或生活经验。"
                : "I can state this public knowledge but cannot claim human consciousness or lived experience.";
        } else if (topic == TOPIC_GAS) {
            firstId = 1501;
            secondId = 1502;
            first = chinese
                ? unicode"Gas 是 EVM 对计算、存储和调用工作量的计量，不是智力单位。"
                : "Gas measures EVM computation, storage, and calls; it is not a unit of intelligence.";
            second = chinese
                ? unicode"交易费用大致等于 Gas Used 乘以有效 Gas Price，具体数值随代码路径和网络状态变化。"
                : "Transaction cost is roughly gas used times effective gas price and varies with code path and network state.";
            if ((cues & CUE_AI) != 0 || (cues & CUE_SCALE) != 0) {
                thirdId = 1503;
                third = chinese
                    ? unicode"增加 Gas 只有在算法用它检索更多事实、比较候选或复核结论时才可能提升质量；原算法不变不会自动变聪明。"
                    : "More gas can improve quality only when the algorithm uses it to retrieve facts, compare candidates, or verify conclusions; unchanged logic does not become smarter.";
            } else {
                thirdId = 1504;
                third = chinese
                    ? unicode"估算值不是最终扣费保证；状态变化、冷暖访问和不同分支都会改变实际消耗。"
                    : "An estimate is not a final-fee guarantee; state changes, warm or cold access, and branches can alter actual usage.";
            }
        } else if (topic == TOPIC_WALLET) {
            firstId = 1601;
            secondId = 1602;
            thirdId = 1603;
            first = chinese
                ? unicode"钱包真正控制的是私钥；谁能产生有效签名，谁就能控制对应地址的资产和权限。"
                : "A wallet ultimately controls private keys; whoever can create a valid signature controls the address's assets and permissions.";
            second = (cues & CUE_SIGNATURE) != 0
                ? (chinese
                        ? unicode"签名前应核对网络、目标合约、调用函数、资产、数量、接收方和授权额度。"
                        : "Before signing, verify the network, contract, function, asset, amount, recipient, and allowance.")
                : (chinese
                        ? unicode"助记词和私钥不应发送给任何网站、客服、机器人或所谓恢复工具。"
                        : "Never send a seed phrase or private key to a website, support agent, bot, or recovery tool.");
            third = (cues & CUE_PRIVATE_KEY) != 0
                ? (chinese
                        ? unicode"私钥丢失且没有备份通常无法由链或项目方恢复；私钥泄露则应尽快迁移资产并撤销授权。"
                        : "A lost unbacked key usually cannot be recovered by the chain or project; a leaked key requires asset migration and approval revocation.")
                : (chinese
                        ? unicode"连接钱包本身通常只暴露地址；真正产生资产后果的是后续签名和广播，必须分开判断。"
                        : "Connecting usually exposes an address; later signatures and broadcasts create asset consequences and must be evaluated separately.");
        } else if (topic == TOPIC_CONTRACT) {
            firstId = 1701;
            secondId = 1702;
            thirdId = 1703;
            if ((cues & CUE_MINT) != 0 && (cues & CUE_ADMIN) != 0 && !negated) {
                first = chinese
                    ? unicode"合约同时允许增发且管理员仍掌握该权限，意味着供应上限可以被改变，存在明确的供应风险。"
                    : "If minting exists and an administrator retains that power, the supply cap can change and creates explicit supply risk.";
            } else if ((cues & CUE_PROXY) != 0 && (cues & CUE_ADMIN) != 0 && !negated) {
                first = chinese
                    ? unicode"代理合约由管理员升级实现时，未来业务规则仍可改变；代理本身不是后门，但升级权是重要信任点。"
                    : "An admin-upgradeable proxy can change future rules; a proxy is not automatically a backdoor, but upgrade authority is a major trust point.";
            } else {
                first = chinese
                    ? unicode"判断合约不能只看源码整洁度，还要核对实际部署字节码、代理实现和当前权限。"
                    : "Contract review must cover deployed bytecode, proxy implementation, and current authority rather than source cleanliness alone.";
            }
            second = (cues & CUE_BLACKLIST) != 0 && !negated
                ? (chinese
                        ? unicode"黑名单或暂停权限可能限制特定地址转账，需要确认谁能调用、是否有时间锁以及历史调用记录。"
                        : "Blacklist or pause authority can restrict transfers; inspect the caller, timelock, and historical calls.")
                : (chinese
                        ? unicode"权限检查应覆盖 owner、角色、升级管理员、暂停、增发、费率修改和任意资产转移。"
                        : "Authority review should cover owner, roles, upgrade admin, pause, mint, fee changes, and arbitrary asset movement.");
            third = (cues & CUE_SECURITY) != 0
                ? (chinese
                        ? unicode"安全结论还需要结合实时状态、资金流、流动性、LP 控制和真实卖出路径；单看一个函数不能下结论。"
                        : "A safety conclusion also needs live state, fund flow, liquidity, LP control, and a real sell route; one function is insufficient.")
                : (chinese
                        ? unicode"源码事实、链上状态和项目承诺应分别标注，不能把宣传描述当成合约保证。"
                        : "Source facts, live state, and project claims must be separated; marketing language is not a contract guarantee.");
        } else if (topic == TOPIC_TOKEN) {
            firstId = 1801;
            secondId = 1802;
            thirdId = 1803;
            first = chinese
                ? unicode"代币是合约账本中的可转移单位；标准只定义接口，不自动赋予价值或安全性。"
                : "A token is a transferable unit in a contract ledger; its standard defines interfaces, not value or safety.";
            second = chinese
                ? unicode"评估代币应分别检查增发、冻结、黑名单、税费、持仓集中度、流动性和 LP 控制。"
                : "Evaluate minting, freezes, blacklists, taxes, holder concentration, liquidity, and LP control separately.";
            third = chinese
                ? unicode"聊天收费可以制造使用需求，但价格仍取决于真实需求、供给和市场；销毁不能替代产品价值。"
                : "Chat fees can create usage demand, while price still depends on demand, supply, and markets; burning cannot replace product value.";
        } else if (topic == TOPIC_DEFI) {
            firstId = 1901;
            secondId = 1902;
            thirdId = 1903;
            first = chinese
                ? unicode"AMM 根据池中资产余额和公式报价；流动性越薄，同样交易通常产生越大的价格冲击。"
                : "An AMM prices trades from pool balances and a formula; thinner liquidity usually produces greater price impact.";
            second = chinese
                ? unicode"LP 份额代表池中资产权益，风险包括无常损失、合约漏洞、Hook、管理员和撤池权限。"
                : "LP shares represent pool ownership and carry impermanent-loss, contract, hook, admin, and withdrawal risks.";
            third = (cues & CUE_LIQUIDITY) != 0
                ? (chinese
                        ? unicode"网页显示的美元流动性不能单独证明可卖出，必须检查真实储备、路由、税费和小额卖出模拟。"
                        : "Displayed dollar liquidity does not prove sellability; inspect reserves, routing, taxes, and a small sell simulation.")
                : (chinese
                        ? unicode"DeFi 的可组合性也会传播依赖风险，一个预言机、抵押品或路由失败可能影响整条路径。"
                        : "DeFi composability propagates dependency risk; one oracle, collateral, or router failure can affect the full path.");
        } else if (topic == TOPIC_NFT) {
            firstId = 2001;
            secondId = 2002;
            thirdId = 2003;
            first = chinese
                ? unicode"NFT 是带唯一 tokenId 的链上资产；所有权通常在链上，媒体和元数据可能只保存外部链接。"
                : "An NFT is an on-chain asset with a unique token ID; ownership is usually on-chain while media may be an external link.";
            second = chinese
                ? unicode"铸造前要核对合约、价格、授权和实际收到的资产，免费 mint 也可能请求危险签名。"
                : "Before minting, verify the contract, price, approval, and received asset; a free mint can still request a dangerous signature.";
            third = chinese
                ? unicode"能否卖出取决于真实买方、市场深度和合约限制，地板价不保证你的成交价。"
                : "Sellability depends on buyers, market depth, and contract restrictions; a floor price does not guarantee execution.";
        } else if (topic == TOPIC_TRANSACTION) {
            firstId = 2101;
            secondId = 2102;
            thirdId = 2103;
            first = chinese
                ? unicode"交易从签名、广播、进入节点内存池到打包确认是不同阶段，页面显示已发送不等于链上成功。"
                : "Signing, broadcasting, mempool admission, and confirmation are separate stages; a sent UI state does not prove chain success.";
            second = chinese
                ? unicode"排查失败应查看交易哈希、receipt 状态、revert 数据、nonce、Gas 和当时合约状态。"
                : "Debug failures with the transaction hash, receipt status, revert data, nonce, gas, and contract state at execution time.";
            third = chinese
                ? unicode"超时或暂时查不到不能直接当作失败；还要检查替换交易、节点延迟和可能的重组。"
                : "A timeout or missing lookup is not definitive failure; check replacements, node delay, and possible reorgs.";
        } else if (topic == TOPIC_PRIVACY) {
            firstId = 2201;
            secondId = 2202;
            thirdId = 2203;
            first = chinese
                ? unicode"公开链上的地址、交易、事件和合约存储通常永久可查询，聊天内容也不应视为私密。"
                : "Addresses, transactions, events, and storage on public chains are normally permanent and queryable; chat content is not private.";
            second = chinese
                ? unicode"内容加密不等于身份匿名，也不等于隐藏时间、金额、通信关系等元数据。"
                : "Content encryption is not identity anonymity and does not hide timing, amounts, or relationship metadata.";
            third = chinese
                ? unicode"不要把姓名、密码、私钥、助记词、验证码或其他敏感信息写入提示词或交易 calldata。"
                : "Never put names, passwords, keys, seed phrases, one-time codes, or other sensitive data in prompts or calldata.";
        } else if (topic == TOPIC_GOVERNANCE) {
            firstId = 2301;
            secondId = 2302;
            thirdId = 2303;
            first = chinese
                ? unicode"治理的核心不是是否叫 DAO，而是谁能提案、投票、执行以及在什么延迟后改变系统。"
                : "Governance is defined by who can propose, vote, execute, and change the system after what delay, not by the DAO label.";
            second = chinese
                ? unicode"多签降低单钥风险，但签名人集中、门槛过低或设备相关仍可能形成单点控制。"
                : "A multisig reduces single-key risk, while concentrated signers, low thresholds, or related devices can preserve central control.";
            third = chinese
                ? unicode"应核对角色地址、时间锁、紧急权限、升级路径和真实历史操作，而不是只看治理页面。"
                : "Inspect role addresses, timelocks, emergency powers, upgrade paths, and historical actions rather than only a governance page.";
        } else if (topic == TOPIC_PLANNING) {
            firstId = 2401;
            secondId = 2402;
            thirdId = 2403;
            first = chinese
                ? unicode"可靠计划应先明确目标、约束、成功标准和不能触碰的安全边界。"
                : "A reliable plan starts with goals, constraints, success criteria, and non-negotiable safety boundaries.";
            second = chinese
                ? unicode"先验证最不确定、失败成本最低的环节，再逐步扩大范围，比同时改变多个变量更容易定位问题。"
                : "Validate the cheapest uncertain step first and expand gradually instead of changing many variables at once.";
            third = chinese
                ? unicode"每个阶段都应有可复核证据、失败回退和停止条件；完成动作不等于实现结果。"
                : "Each stage needs evidence, rollback, and stop conditions; completing an action does not prove the outcome.";
        } else if (topic == TOPIC_MARKET) {
            firstId = 2501;
            secondId = 2502;
            thirdId = 2503;
            first = (cues & (CUE_LIVE | CUE_PRICE)) != 0
                ? (chinese
                        ? unicode"我没有价格预言机或互联网访问，不能可靠提供当前价格、实时市值或未来涨跌。"
                        : "I have no price oracle or internet access and cannot reliably provide current price, live market cap, or future direction.")
                : (chinese
                        ? unicode"市场结果来自供需、流动性、持仓结构和参与者行为，链上模型不能保证价格方向。"
                        : "Market outcomes depend on supply, demand, liquidity, holders, and behavior; an on-chain model cannot guarantee direction.");
            second = chinese
                ? unicode"提示词中的价格只是用户输入，合约无法证明它是真实、最新或来自哪个市场。"
                : "A price inside the prompt is user input; the contract cannot prove it is true, current, or tied to a specific market.";
            third = chinese
                ? unicode"买入前仍需检查合约权限、真实流动性、持仓集中度、资金流和实际卖出路径。"
                : "Before buying, inspect contract authority, real liquidity, holder concentration, fund flow, and an actual sell route.";
        } else {
            return _unknown(chinese);
        }

        return _known(chinese, first, second, third, firstId, secondId, thirdId);
    }

    function _known(
        bool chinese,
        string memory first,
        string memory second,
        string memory third,
        uint16 firstId,
        uint16 secondId,
        uint16 thirdId
    ) private pure returns (Retrieval memory result) {
        result.response = chinese
            ? string.concat(unicode"结论：", first, unicode"\n\n依据：", second, unicode"\n\n边界：", third)
            : string.concat("Conclusion: ", first, "\n\nEvidence: ", second, "\n\nBoundary: ", third);
        result.evidence = string.concat(
            "[", _id(firstId), "] ", first, "\n[", _id(secondId), "] ", second, "\n[", _id(thirdId), "] ", third
        );
        result.factIds = [firstId, secondId, thirdId];
        result.factCount = 3;
    }

    function _unknown(bool chinese) private pure returns (Retrieval memory result) {
        result.unknown = true;
        result.response = chinese
            ? unicode"这个问题挺有意思，但我目前的链上知识里还没有足够相关的事实。为了不误导你，我先不勉强下结论。你可以换一种说法，或者补充具体对象、场景和最想确认的重点；如果知识模块将来加入这个主题，新版本才能更可靠地回答。"
            : "That is an interesting question, but my current on-chain knowledge does not contain enough relevant facts. I would rather avoid a misleading guess. Try rephrasing it or add the concrete object, situation, and point you want verified; a future knowledge version would be needed for a reliable answer.";
        result.evidence = chinese
            ? unicode"没有检索到达到回答门槛的链上事实。"
            : "No on-chain fact cleared the retrieval threshold.";
    }

    function _id(uint16 value) private pure returns (string memory) {
        bytes memory output = new bytes(4);
        // Every decimal digit is bounded to 0..9 for the four-digit fact IDs used by this knowledge module.
        // forge-lint: disable-next-line(unsafe-typecast)
        output[0] = bytes1(uint8(48 + value / 1000));
        // forge-lint: disable-next-line(unsafe-typecast)
        output[1] = bytes1(uint8(48 + value / 100 % 10));
        // forge-lint: disable-next-line(unsafe-typecast)
        output[2] = bytes1(uint8(48 + value / 10 % 10));
        // forge-lint: disable-next-line(unsafe-typecast)
        output[3] = bytes1(uint8(48 + value % 10));
        return string(output);
    }
}
