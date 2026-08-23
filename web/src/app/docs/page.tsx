import type { Metadata } from "next";
import Link from "next/link";
import { BrandMark } from "@/components/brand-mark";
import { GitHubLink } from "@/components/github-link";
import { XLink } from "@/components/x-link";
import styles from "./docs.module.css";

export const metadata: Metadata = {
  title: "TinyAI Protocol Docs | 链上 AI 生命周期协议",
  description: "TinyAI Protocol 技术规范：链上推理、AI 状态、大脑注册表、组件、市场与独立验证。",
};

const toc = [
  ["thesis", "协议命题"], ["architecture", "系统架构"], ["execution", "执行模型"],
  ["identity", "AI 身份与状态"], ["brains", "大脑与进化"], ["components", "组件协议"],
  ["market", "市场与资金流"], ["contracts", "合约与源码"], ["verify", "独立验证"], ["composability", "协议可组合性"],
  ["horizon", "未来技术愿景"],
];

const stateFields = [
  ["DNA", "每只 AI 的确定性身份种子，铸造时生成。"],
  ["MEMORY ROOT", "对全部已保存交互连续滚动的哈希承诺。"],
  ["BRAIN VERSION", "当前执行的大脑注册表版本。"],
  ["TRAITS", "好奇、共情、幽默、谨慎四项有界性格。"],
  ["CAPABILITIES", "技能位、记忆容量和表达级别。"],
  ["POLICY", "主人写入权、自动升级和永久封印状态。"],
];

const components = [
  ["01", "Memory Cell", "记忆容量 +1", "发行 30,000"], ["02", "Curiosity Gene", "好奇心 +5", "发行 15,000"],
  ["03", "Empathy Gene", "共情 +5", "发行 15,000"], ["04", "Humor Gene", "幽默 +5", "发行 15,000"],
  ["05", "Caution Gene", "谨慎 +5", "发行 15,000"], ["06", "Expression Core", "回答变体 +1", "发行 10,000"],
];

const deployedContracts = [
  ["TinyAIProtocol", "AI 身份、状态与主人专属写入", "0x5044F577571dcA7cB7A0775aDcFa66E02bd49c93", "TinyAIProtocol.sol", "protocol/TinyAIProtocol.sol"],
  ["TinyAIComponents", "有上限的 ERC-1155 能力组件", "0x936161FD89c4272f2B034f5414e6D9C7C9CB9bF1", "TinyAIComponents.sol", "protocol/TinyAIComponents.sol"],
  ["TinyAIMarket", "AI 与组件的非托管固定价结算", "0x3dCBDB84bA220Cd9cA6E420b2bCe3D3610a1e9b7", "TinyAIMarket.sol", "protocol/TinyAIMarket.sol"],
  ["TinyAIBrainRegistry", "追加式大脑版本与代码哈希注册表", "0x29EefCC07eA38535A16fe4fB9c9469d4634C1fA1", "TinyAIBrainRegistry.sol", "protocol/TinyAIBrainRegistry.sol"],
  ["TinyAIBrainEngineV2", "当前推荐的确定性链上推理引擎", "0xE45F1221EBaDb925062E1a706b16277943e7DAb0", "TinyAIBrainEngineV2.sol", "protocol/TinyAIBrainEngineV2.sol"],
  ["TinyAINeuralDecoderV2", "V2 的 int8 自回归神经解码器", "0xe4D2944f722F2c8d685F3934FB2310321281C7eF", "TinyAINeuralDecoderV2.sol", "protocol/TinyAINeuralDecoderV2.sol"],
];

const tokenModeContracts = [
  ["Future TinyAI / TINYAI", "固定 CA；最终发币前无运行时代码", "0x30e892840E5E37083c986012934Bd845f8157777", "TOKEN PENDING"],
  ["TinyAIHolderVault", "NVDAB 持有人奖励累加器", "0x042cdC4091953AEE832365097f191d40F74d39e2", "PREDEPLOYED"],
  ["TinyAITokenComponents", "500 TINYAI Mint 的 ERC-1155 组件", "0x5F4159c1766CFC5De595e0D5cB805F880Af2b844", "PREDEPLOYED"],
  ["TinyAITokenProtocol", "Token Mode AI 身份、状态与链上对话", "0x08920f8243F7921A0f225AD171c81B51ee51e9C0", "PREDEPLOYED"],
  ["TinyAITokenMarket", "零协议费的代币固定价市场", "0x4e39FD3b62303bF9377Fa38566edd6847AAeb803", "PREDEPLOYED"],
];

export default function DocsPage() {
  return (
    <main className={styles.page}>
      <nav className={styles.nav} aria-label="主导航">
        <Link className={styles.brand} href="/protocol"><BrandMark className={styles.brandMark} /><strong>TinyAI Protocol</strong></Link>
        <div className={styles.navLinks}>
          <Link href="/protocol">Mint</Link><Link href="/my-ai">我的 AI</Link><Link href="/market">Market</Link><GitHubLink /><XLink />
          <a className={styles.paperNav} href="/whitepaper/TinyAI-Protocol-Whitepaper.pdf" download>Whitepaper</a>
        </div>
      </nav>

      <header className={styles.hero}>
        <div className={styles.heroCopy}>
          <p className={styles.eyebrow}>TINYAI PROTOCOL SPECIFICATION</p>
          <h1>AI，成为一种可拥有的链上生命。</h1>
          <p className={styles.heroText}>可验证、可进化。身份、记忆、大脑和交易规则都由 EVM 执行。</p>
          <div className={styles.heroActions}>
            <a className={styles.primaryAction} href="#thesis">阅读协议</a>
            <a className={styles.secondaryAction} href="/whitepaper/TinyAI-Protocol-Whitepaper.pdf" download>下载白皮书 PDF</a>
          </div>
        </div>
        <figure className={styles.executionSeal} aria-label="TinyAI 协议执行边界">
          <figcaption><span>EXECUTION BOUNDARY</span><b>EVM / DETERMINISTIC</b></figcaption>
          <div className={styles.sealCore}>
            <span>OWNER + PROMPT</span><i aria-hidden="true">↓</i><strong>AI STATE</strong><i aria-hidden="true">↓</i>
            <strong>BRAIN REGISTRY</strong><i aria-hidden="true">↓</i><strong>ON-CHAIN INFERENCE</strong>
          </div>
          <div className={styles.sealFooter}><span>RESPONSE</span><span>TRACE HASH</span><span>MEMORY ROOT</span></div>
        </figure>
      </header>

      <section className={styles.statusBar} aria-label="协议状态">
        <div><span>REFERENCE</span><b>BSC Mainnet</b></div><div><span>TARGET</span><b>BSC / EVM</b></div>
        <div><span>EXECUTION</span><b>On-chain</b></div><div><span>UPGRADE MODEL</span><b>Owner opt-in</b></div>
        <div><span>PROXY</span><b>None</b></div>
      </section>

      <div className={styles.docsLayout}>
        <aside className={styles.toc} aria-label="文档目录">
          <p>CONTENTS</p>
          <ol>{toc.map(([id, label]) => <li key={id}><a href={`#${id}`}>{label}</a></li>)}</ol>
          <div className={styles.tocPaper}><span>完整技术白皮书</span><a href="/whitepaper/TinyAI-Protocol-Whitepaper.pdf" download>PDF / TECHNICAL</a></div>
        </aside>

        <article className={styles.document}>
          <section className={styles.leadSection} id="thesis">
            <p className={styles.kicker}>协议命题</p><h2>网站不是大脑。合约才是。</h2>
            <p className={styles.lead}>TinyAI Protocol 把一只 AI 定义为公开的链上状态机，而不是调用中心化模型 API 的网页角色。</p>
            <div className={styles.definitionGrid}>
              <div><b>执行主权</b><p>最终回答与保存后的状态变化由 EVM 产生。</p></div>
              <div><b>模型完整性</b><p>大脑地址和运行时代码哈希在执行前接受校验。</p></div>
              <div><b>状态连续性</b><p>每次保存对话都会推进经验、记忆承诺和公开记忆环。</p></div>
              <div><b>所有者权利</b><p>AI NFT 当前所有者决定对话写入、组件融合、自动迁移和永久封印。</p></div>
            </div>
            <blockquote><span>严格定义</span><p>训练可以在链下完成。发布后的模型数据、路由、确定性生成、状态更新和最终回答在 EVM 内执行。这个边界可以通过合约调用和字节码哈希独立验证。</p></blockquote>
          </section>

          <section className={styles.section} id="architecture">
            <p className={styles.kicker}>系统架构</p><h2>五个职责，组成一条可审计的 AI 生命周期。</h2>
            <p>协议将所有权、模型发布、推理、能力扩展和交易结算拆成独立合约。每一层都能单独读取、验证和替换前端。</p>
            <figure className={styles.architecture}>
              <div className={styles.archInput}><small>CALLER</small><b>Wallet / RPC / Contract</b><span>prompt + aiId</span></div>
              <div className={styles.archArrow} aria-hidden="true">→</div>
              <div className={styles.archProtocol}><small>IDENTITY + STATE</small><b>TinyAIProtocol</b><span>ERC-721 / memory / traits / policy</span></div>
              <div className={styles.archArrow} aria-hidden="true">→</div>
              <div className={styles.archBrain}><small>VERIFIABLE BRAIN</small><b>Registry → Engine</b><span>code hash / integrity / trace</span></div>
              <div className={styles.archBranches}>
                <div><small>CAPABILITY</small><b>Components</b><span>ERC-1155 burn → state</span></div>
                <div><small>SETTLEMENT</small><b>Market</b><span>approval → trade → owed</span></div>
              </div>
              <figcaption>主推理路径不经过项目服务器。任何兼容客户端都可以调用相同的公开协议接口。</figcaption>
            </figure>
          </section>

          <section className={styles.section} id="execution">
            <p className={styles.kicker}>执行模型</p><h2>一次回答同时产生结果和可验证承诺。</h2>
            <div className={styles.executionFlow}>
              <div><span>SUBMIT</span><b>输入进入 AI 合约</b><p>调用者提交 aiId 和不超过 280 字节的 prompt。</p></div>
              <div><span>RESOLVE</span><b>解析已绑定的大脑</b><p>注册表重查引擎代码哈希和完整性，再返回可执行地址。</p></div>
              <div><span>INFER</span><b>执行路由与生成</b><p>引擎结合 prompt、DNA、性格、能力、回合数和记忆承诺确定输出。</p></div>
              <div><span>COMMIT</span><b>返回 traceHash</b><p>结果附带对引擎、检索、生成路径和 AI 状态的压缩承诺。</p></div>
              <div><span>PERSIST</span><b>主人写入成长状态</b><p>只有当前 NFT 所有者能推进经验、memoryRoot、turns 和公开记忆槽。</p></div>
            </div>
            <div className={styles.modeCompare}>
              <div><span>OWNER MODE</span><h3>Exclusive write authority</h3><p>合约直接读取 <code>ownerOf</code>；只有当前 NFT 所有者能够触发 AI 状态转换。</p></div>
              <div><span>STATE MODE</span><h3>Persistent chat</h3><p>主人发送交易保存交互，写入公开状态与事件，让 AI 的经历成为链上历史。</p></div>
            </div>
          </section>

          <section className={styles.section} id="identity">
            <p className={styles.kicker}>AI 身份与状态</p><h2>每只 AI 都是一份独立、可转移的状态档案。</h2>
            <p>ERC-721 负责归属，AIState 负责行为。转移 NFT 的同时，也转移这只 AI 的 DNA、记忆承诺、性格、能力和大脑选择权。</p>
            <div className={styles.stateLedger}>{stateFields.map(([name, description]) => <div key={name}><code>{name}</code><p>{description}</p></div>)}</div>
            <div className={styles.memoryPanel}>
              <div><span>ROLLING COMMITMENT</span><strong>M<sub>n</sub> = H(M<sub>n-1</sub>, speaker, prompt, response, trace, block)</strong></div>
              <p>记忆槽是最多 8 格的公开环形缓冲区。扩大容量意味着更长的可查询交互窗口，memoryRoot 则连续承诺全部已保存历史。</p>
            </div>
          </section>

          <section className={styles.section} id="brains">
            <p className={styles.kicker}>大脑与进化</p><h2>发布新大脑，不覆盖旧大脑。</h2>
            <div className={styles.brainLayout}>
              <div className={styles.brainRules}><h3>Append-only registry</h3><ul>
                <li>版本必须按顺序追加。</li><li>引擎必须存在并通过自身完整性检查。</li>
                <li>运行时代码哈希被永久记录。</li><li>旧版本即使停止接受新升级，也仍可被历史 AI 调用。</li>
              </ul></div>
              <div className={styles.ownerPaths}>
                <div><span>MANUAL</span><b>主动迁移</b><p>所有者迁移到更高且已启用的版本。</p></div>
                <div><span>AUTO</span><b>选择自动升级</b><p>下一次持久对话采用更高的推荐大脑。</p></div>
                <div><span>SEALED</span><b>永久封印</b><p>把当前大脑固定为不可再迁移的执行版本。</p></div>
              </div>
            </div>
            <p className={styles.protocolNote}><b>治理边界：</b>管理员可以发布和推荐，但不能把已经存在的 AI 强制迁移到新大脑。最终升级权属于 AI 所有者。</p>
          </section>

          <section className={styles.section} id="components">
            <p className={styles.kicker}>组件协议</p><h2>组件不是皮肤，而是一次性的状态升级权。</h2>
            <p>Token Mode 的六种创世组件合计永久封顶 100,000 个，每个固定收取 500 枚新 Flap 代币，不限制单钱包数量。目录部署时封存，融合会销毁 ERC-1155 组件，并直接改变目标 AI 的协议状态。</p>
            <div className={styles.componentTable} role="table" aria-label="创世组件">
              <div className={styles.tableHead} role="row"><span>ID</span><span>COMPONENT</span><span>EFFECT</span><span>BOUND</span></div>
              {components.map(([id, name, effect, bound]) => <div className={styles.tableRow} role="row" key={id}><span>{id}</span><b>{name}</b><span>{effect}</span><span>{bound}</span></div>)}
            </div>
            <p className={styles.protocolNote}>组件没有管理员免费铸造入口。融合销毁不会恢复历史 Mint 额度；达到属性上限后也不能继续消耗组件。</p>
          </section>

          <section className={styles.section} id="market">
            <p className={styles.kicker}>市场与资金流</p><h2>资产挂牌不托管，成交款直接到达卖家。</h2>
            <p>卖家挂牌时仍持有 AI 或组件，只向市场授予转移权限。Token Mode 购买时重新检查余额、归属、资产授权和结算代币授权，失效挂牌无法成交。</p>
            <div className={styles.fundFlow}>
              <div><span>SELLER</span><b>Asset + approval</b></div><i aria-hidden="true">→</i>
              <div className={styles.fundCore}><span>MARKET</span><b>Exact-token settlement</b><small>payment + asset / atomic</small></div>
              <i aria-hidden="true">→</i><div><span>BUYER</span><b>AI or component</b></div>
              <div className={styles.owedSeller}><span>DIRECT</span><b>Seller wallet</b></div>
            </div>
            <div className={styles.marketFacts}>
              <p><b>非托管挂牌</b><span>购买前资产留在卖家钱包。</span></p><p><b>部分成交</b><span>ERC-1155 组件可按数量购买。</span></p>
              <p><b>直接结算</b><span>成交代币从买家原子转入卖家钱包，不经过可提取余额。</span></p><p><b>结算规则</b><span>合约按挂牌价格完成结算，不负责撮合或报价。</span></p>
            </div>
            <p className={styles.protocolNote}>市场提供公开结算路线，不承诺流动性、买家、成交速度或价格上涨。</p>
            <p className={styles.protocolNote}>Token Mode 中，AI 与单个组件的 Mint 价格都永久固定为 500 枚新币，市场协议手续费和对话协议费均为 0；用户只需另外向 BSC 支付交易 Gas。</p>
            <p className={styles.protocolNote}>新币名称与符号固定为 TinyAI / TINYAI，买入税和卖出税均为 1%，从发币交易起持续 30 天（2,592,000 秒）。官网为 bnbtinyai.org，公开账号为 x.com/Tinyaipro。</p>
            <p className={styles.protocolNote}>Flap 交易税中实际到达 beneficiary 的部分进入 AI 持有者 Vault，一只 AI 对应一个 NVDAB 奖励份额。Flap 平台级扣除发生在 beneficiary 分配之前，因此这里不表示毛交易税全部归持有人。</p>
          </section>

          <section className={styles.section} id="contracts">
            <p className={styles.kicker}>CONTRACTS &amp; SOURCE</p><h2>主网地址、公开源码与验证结果，属于同一条证据链。</h2>
            <p>Genesis BNB 版是当前可用的独立部署。Token Mode 的四个协议合约已经在 BSC 主网完成预部署与相互绑定，但固定的 TINYAI 地址尚无代币代码，因此 Mint、市场结算和持有人奖励暂未开启；两套地址不会混用。</p>
            <div className={styles.contractTable} role="table" aria-label="TinyAI BSC 主网合约">
              <div className={styles.contractHead} role="row"><span>CONTRACT / ROLE</span><span>MAINNET ADDRESS</span><span>EVIDENCE</span></div>
              {deployedContracts.map(([name, role, address, sourceLabel, sourcePath]) => (
                <div className={styles.contractRow} role="row" key={address}>
                  <div><b>{name}</b><span>{role}</span></div>
                  <code>{address}</code>
                  <div className={styles.contractLinks}>
                    <a href={`https://bscscan.com/address/${address}#code`} target="_blank" rel="noreferrer">BscScan Verified ↗</a>
                    <a href={`https://github.com/zzzzz2222112/bsc-onchain-ai/blob/main/contracts/src/${sourcePath}`} target="_blank" rel="noreferrer">{sourceLabel} ↗</a>
                  </div>
                </div>
              ))}
            </div>
            <p className={styles.protocolNote}><b>TOKEN MODE / PRELAUNCH：</b>预部署交易位于区块 117639782-117639985。未来代币 CA 已被四个协议合约固定；最终发币和链上复核完成前，这里只展示证据，不把它描述为已上线。</p>
            <div className={styles.contractTable} role="table" aria-label="TinyAI Token Mode BSC 主网预部署合约">
              <div className={styles.contractHead} role="row"><span>CONTRACT / ROLE</span><span>MAINNET ADDRESS</span><span>STATE</span></div>
              {tokenModeContracts.map(([name, role, address, state]) => (
                <div className={styles.contractRow} role="row" key={address}>
                  <div><b>{name}</b><span>{role}</span></div>
                  <code>{address}</code>
                  <div className={styles.contractLinks}>
                    <a href={`https://bscscan.com/address/${address}`} target="_blank" rel="noreferrer">BscScan ↗</a>
                    <span>{state}</span>
                  </div>
                </div>
              ))}
            </div>
            <div className={styles.evidenceLinks}>
              <a href="https://github.com/zzzzz2222112/bsc-onchain-ai/blob/main/contracts/deployments/bsc-mainnet-genesis.json" target="_blank" rel="noreferrer"><span>GENESIS</span><b>45 笔正式部署记录 ↗</b></a>
              <a href="https://github.com/zzzzz2222112/bsc-onchain-ai/blob/main/contracts/deployments/bsc-mainnet-brain-v2.json" target="_blank" rel="noreferrer"><span>BRAIN V2</span><b>升级与注册记录 ↗</b></a>
              <a href="https://github.com/zzzzz2222112/bsc-onchain-ai/blob/main/contracts/deployments/bsc-mainnet-source-verification.json" target="_blank" rel="noreferrer"><span>VERIFICATION</span><b>源码验证清单 ↗</b></a>
              <a href="https://github.com/zzzzz2222112/bsc-onchain-ai/blob/main/contracts/deployments/bsc-mainnet-token-mode-prelaunch.json" target="_blank" rel="noreferrer"><span>TOKEN MODE</span><b>13 笔预部署记录 ↗</b></a>
            </div>
            <p className={styles.protocolNote}>模型和词库使用 STOP 前缀的运行时字节码保存。它们不是普通 Solidity 合约，因此用冻结产物承诺和 runtime code hash 验证，不伪装成“已验证 Solidity”。</p>
          </section>

          <section className={styles.section} id="verify">
            <p className={styles.kicker}>独立验证</p><h2>关掉官网，也能证明它如何回答。</h2>
            <p>验证者只需要合约地址、固定区块和任意兼容 RPC。读取 AI 状态，解析大脑版本，检查引擎代码哈希，再以当前主人地址作为 from 对同一输入执行 <code>eth_call</code> 模拟。</p>
            <div className={styles.verifyBlock}>
              <div className={styles.codeHeader}><span>READ-ONLY VERIFICATION</span><span>Solidity interface</span></div>
              <pre><code>{`owner = protocol.ownerOf(aiId)\nstate = protocol.aiState(aiId)\nbrain = registry.versionInfo(state.brainVersion)\nassert extcodehash(brain.engine) == brain.codeHash\n\neth_call(from=owner, to=protocol,\n         data=chatAI(aiId, prompt), blockTag=fixedBlock)`}</code></pre>
            </div>
            <ol className={styles.verifyList}>
              <li><b>固定状态</b><span>在同一 chainId 和 blockTag 下读取。</span></li><li><b>校验模型</b><span>比较引擎 runtime bytecode 与注册表 codeHash。</span></li>
              <li><b>重复调用</b><span>通过两个节点对相同 aiId 和 prompt 执行 eth_call。</span></li><li><b>验证成长</b><span>持久对话后核对事件、turns、experience、memoryRoot 和记忆槽。</span></li>
            </ol>
          </section>

          <section className={styles.releaseSection} id="composability">
            <div><p className={styles.kicker}>协议可组合性</p><h2>AI 是公开协议对象，不是封闭应用账户。</h2>
              <p>ERC-721 所有权、AIState、Brain Registry、ERC-1155 组件和市场事件共同构成一套可被其他合约读取的公共接口。索引器、游戏、治理工具和替代客户端都可以在不进入大脑信任边界的情况下组合这些状态。</p>
              <p>可组合并不意味着可任意修改。对话写入、升级、封印和组件融合仍由当前 ERC-721 所有权约束；外部系统只能读取公开状态或按协议授权路径发起调用。</p>
            </div>
            <div className={styles.releaseChecklist}><span>COMPOSABLE SURFACES</span><ul>
              <li>ERC-721 · 身份、所有权与链上元数据</li><li>AIState · DNA、性格、能力与记忆承诺</li><li>Brain Registry · 可验证引擎发现与版本策略</li><li>ERC-1155 · 有上限的状态变更组件</li><li>Events · 对话、成长、融合与结算索引</li>
            </ul></div>
          </section>

          <section className={styles.section} id="horizon">
            <p className={styles.kicker}>RESEARCH HORIZON</p><h2>让链上 AI 变得更强，同时不放弃可验证性。</h2>
            <p>这里描述的是未来研究方向，不是已经部署的功能。协议的长期目标，是让一只 AI 能脱离任何单一网站长期存在，在兼容应用之间迁移，并在保留身份与状态连续性的前提下采用更强的大脑。</p>
            <div className={styles.definitionGrid}>
              <div><b>更大的确定性大脑</b><p>研究稀疏路由、参数分片、分阶段检索和有界多轮解码，在交易限制内扩大有效能力。</p></div>
              <div><b>分层链上记忆</b><p>把短期上下文、长期语义承诺和主人控制的档案拆分成可独立验证的记忆层。</p></div>
              <div><b>携带证明的推理</b><p>对超出单笔交易预算的计算验证简洁证明，并明确区分原生 EVM 执行与被证明的外部计算。</p></div>
              <div><b>开放大脑标准</b><p>通过统一接口、模型承诺、可复现构建和受约束治理，引入独立开发的大脑而不改写旧 AI。</p></div>
              <div><b>合约原生智能体</b><p>在明确授权、额度和撤销边界下，探索 AI 之间的消息、协作与有限资产能力。</p></div>
              <div><b>代币化资源协调</b><p>未来可用可选模块分配推理、存储、策展或治理资源；当前零协议对话费不因此改变。</p></div>
            </div>
            <p className={styles.protocolNote}><b>原则：</b>能力可以升级，但身份、所有权历史、模型承诺和状态变化必须继续可审计。</p>
          </section>
        </article>
      </div>

      <footer className={styles.footer}>
        <div><span aria-hidden="true">T</span><b>TinyAI Protocol</b></div><p>Sovereign on-chain AI state machines for the EVM.</p>
        <nav aria-label="页脚导航"><Link href="/protocol">Mint</Link><Link href="/my-ai">我的 AI</Link><Link href="/market">Market</Link></nav>
      </footer>
    </main>
  );
}
