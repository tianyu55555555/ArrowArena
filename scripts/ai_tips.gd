class_name AiTips
extends RefCounted
## 公益模块：加载页与科普馆展示的 AI 基础知识、安全防范与负责任使用科普

const LIST: Array[Dictionary] = [
	{
		"tag": "原理科普",
		"title": "什么是 Token（词元）？",
		"body": "大模型并不是按“一个字”读文章，而是把文本切分成 Token。通常 1 个英文单词约 1~1.3 个 Token，1 个常用汉字约 1~2 个 Token。理解 Token 能帮你估算长文档费用和上下文容量。",
	},
	{
		"tag": "安全防范",
		"title": "警惕「AI 幻觉」：别盲信权威语气",
		"body": "大模型本质上在预测“最合理的下一个词”，遇到不熟悉的事实或过期数据时，可能会自信地编造法条、论文或网址。涉及医疗、法律、财务决策，务必通过官方渠道二次核实！",
	},
	{
		"tag": "反诈公益",
		"title": "防范 AI 换脸与拟声诈骗",
		"body": "不法分子只需几秒钟公开视频或语音，就能合成亲友的声音和面孔。视频通话中若涉及借钱、转账，请让对方“用手在脸前晃动”或挂断后主动拨打原手机号核实，切勿轻信！",
	},
	{
		"tag": "隐私保护",
		"title": "别把敏感隐私发给公开聊天机器人",
		"body": "身份证号、银行卡、家庭住址、公司未公开源码或他人的隐私照片，不要直接粘贴到未开启隐私保护的公共 AI 对话框中，养成“先脱敏、再提问”的好习惯。",
	},
	{
		"tag": "高效使用",
		"title": "好提示词（Prompt）的三要素",
		"body": "想让 AI 回答更精准，可以记住「角色 + 背景 + 输出格式」：例如“请以初中物理老师身份，用生活中的例子，分 3 点向我解释浮力原理”。给示例（Few-Shot）效果更佳！",
	},
	{
		"tag": "原理科普",
		"title": "为什么聊久了 AI 会“失忆”？",
		"body": "每个大模型都有「上下文窗口（Context Window）」上限。当对话超过窗口长度时，最早的聊天记录会被截断或压缩。长任务建议分段总结，或新开对话粘贴核心背景。",
	},
	{
		"tag": "原理科普",
		"title": "什么是思维链（Chain-of-Thought）？",
		"body": "让模型在给出答案前先“一步步写出推理过程”，能显著提升数学、编程与逻辑题的准确率。如今许多推理模型（如深度思考模式）已经把这一步内置为自动推理。",
	},
	{
		"tag": "安全防范",
		"title": "辨别 AI 生成的虚假图片与谣言",
		"body": "看到耸人听闻的“现场图”先别急着转发！可以留意画面中手指数量、背景文字是否扭曲、光影方向是否一致，同时查证权威媒体报道，不做虚假信息的二传手。",
	},
	{
		"tag": "学习成长",
		"title": "把 AI 当「私人导师」，而不是代写机器",
		"body": "直接让 AI 写完作业虽然省事，却会跳过真正的思考训练。更好的方式是先写下自己的思路，请 AI 指出漏洞、出变式练习题，让你从“问答案”变成“学方法”。",
	},
	{
		"tag": "原理科普",
		"title": "什么是 RAG（检索增强生成）？",
		"body": "模型训练完成后知识就停留在截止日期。RAG 技术像给 AI 配了一座实时图书馆：回答前先检索最新资料或专属知识库，再结合原文作答，大幅降低胡编乱造。",
	},
	{
		"tag": "原理科普",
		"title": "开源大模型 vs 闭源大模型",
		"body": "闭源模型通常通过云端 API 提供服务，开箱即用；开源（开放权重）模型允许研究者和开发者下载到本地部署、微调与审计，推动了全球 AI 技术的普惠与透明。",
	},
	{
		"tag": "绿色公益",
		"title": "绿色 AI：节约每一次无意义的算力消耗",
		"body": "大模型在数据中心运行需要消耗大量电力与冷却水。简单查词、基础计算用传统工具更省电；提问时把需求一次说清，既省时间，也为低碳环保出一份力。",
	},
	{
		"tag": "原理科普",
		"title": "温度参数（Temperature）决定 AI 有多“天马行空”",
		"body": "Temperature 越低，模型越倾向选择最高概率的词，适合写代码、总结和翻译；Temperature 越高，输出越富创意和多样性，适合写故事与头脑风暴。",
	},
	{
		"tag": "前沿常识",
		"title": "什么是「多模态（Multimodal）」？",
		"body": "早期大模型只懂文字，而多模态模型能同时理解文字、图片、音频甚至视频——比如拍一道几何题让它讲解，或把界面草图转成网页代码。",
	},
	{
		"tag": "安全防范",
		"title": "小心「提示词注入（Prompt Injection）」",
		"body": "当 AI 帮我们总结陌生网页或邮件时，网页里隐藏的恶意指令可能诱骗 AI 泄露信息或执行错误操作。让 AI 连接外部工具时，重要操作务必保留人工确认！",
	},
	{
		"tag": "社会公益",
		"title": "AI 无障碍：让科技温暖更多人",
		"body": "实时语音转文字正帮助听障人士畅快交流，图像描述 AI 帮助视障朋友“看见”路标与菜单。用善意设计 AI 应用，能让数字世界变得更加包容。",
	},
	{
		"tag": "版权素养",
		"title": "尊重原创与清晰标注 AI 辅助内容",
		"body": "使用 AI 协助创作文章、插画或音乐时，应避免直接仿冒在世艺术家的署名作品，并在公益或公开场合诚实标注“AI 辅助生成”，共同维护健康的创作生态。",
	},
	{
		"tag": "原理科普",
		"title": "Transformer：现代大模型的共同基石",
		"body": "2017 年提出的 Transformer 架构引入了「自注意力机制（Self-Attention）」，让 AI 能同时捕捉长句子中相隔很远的词语关联，开启了今天的大语言模型时代。",
	},
]

const MODEL_CODEX: Array[Dictionary] = [
	{
		"id": "claude",
		"name": "Claude",
		"company": "Anthropic",
		"founded": "2021 年 · 美国旧金山",
		"founders": "Dario Amodei（达里奥·阿莫代伊）、Daniela Amodei（丹妮拉·阿莫代伊）等原 OpenAI 核心研究成员",
		"ecosystem": "闭源云端服务 · 主打 AI 安全对齐",
		"desc": "Anthropic 提出「宪法 AI（Constitutional AI）」安全训练范式，Claude 系列以长上下文理解、高水准代码工程与自然细腻的中文/英文写作表现著称。",
	},
	{
		"id": "gpt",
		"name": "GPT / ChatGPT",
		"company": "OpenAI",
		"founded": "2015 年 12 月 · 美国旧金山",
		"founders": "Sam Altman、Greg Brockman、Ilya Sutskever、Elon Musk 等联合创立（现任 CEO：Sam Altman）",
		"ecosystem": "闭源旗舰为主（兼有部分开放权重模型）",
		"desc": "推出 GPT（Generative Pre-trained Transformer）系列与现象级应用 ChatGPT，率先把大语言模型、多模态交互与深度推理范式带入大众视野。",
	},
	{
		"id": "grok",
		"name": "Grok",
		"company": "xAI",
		"founded": "2023 年 7 月 · 美国",
		"founders": "Elon Musk（埃隆·马斯克）创立（联合创始团队含 Igor Babuschkin、Jimmy Ba 等）",
		"ecosystem": "云端服务（曾开源早期 Grok-1 权重）",
		"desc": "由马斯克创办的 xAI 研发，深度结合 X 平台实时资讯流，以犀利幽默的「叛逆」对话风格与超大规模 Colossus 算力集群训练能力而闻名。",
	},
	{
		"id": "deepseek",
		"name": "DeepSeek（深度求索）",
		"company": "杭州深度求索（DeepSeek · 幻方量化孵化）",
		"founded": "2023 年 7 月 · 中国杭州",
		"founders": "梁文锋（Liang Wenfeng）",
		"ecosystem": "全面开源开放权重与技术报告（MIT 等友好协议）",
		"desc": "坚持底层架构创新与开放路线：凭借 DeepSeek-V3（MoE + MLA 架构）与开源推理模型 DeepSeek-R1，以极具突破性的训练与推理性价比震撼全球 AI 社区。",
	},
	{
		"id": "qwen",
		"name": "Qwen（通义千问）",
		"company": "阿里巴巴集团 · 阿里云通义实验室",
		"founded": "2023 年推出 · 中国杭州",
		"founders": "阿里巴巴集团（创始人马云等）旗下阿里云团队打造，阿里云 CTO 周靖人等领衔，林俊旸等核心团队推动开源生态",
		"ecosystem": "全尺寸开源家族（0.5B ~ 超大规模）+ 商业云服务",
		"desc": "覆盖文本、代码、数学、视觉与音频全模态的大模型家族，凭借完善尺寸梯度与高频开源迭代，成为全球下载量与衍生模型数名列前茅的开源大模型体系。",
	},
	{
		"id": "gemini",
		"name": "Gemini",
		"company": "Google DeepMind（Google / Alphabet 旗下）",
		"founded": "2023 年由 Google Brain 与 DeepMind 合并推出",
		"founders": "Google 创始人 Larry Page、Sergey Brin；DeepMind 联合创始人兼 CEO Demis Hassabis（2024 诺贝尔化学奖得主）、Shane Legg、Mustafa Suleyman 与 Google 首席科学家 Jeff Dean 等共同推动",
		"ecosystem": "云端原生多模态旗舰（另有 Gemma 开源家族）",
		"desc": "采用原生多模态架构，从底层即可统一理解文本、代码、图像、音频与视频，依托 Google 自研 TPU 集群提供百万级超长上下文窗口。",
	},
]

const MONSTER_CODEX: Array[Dictionary] = [
	{
		"kind": "glitch",
		"name": "乱码史莱姆",
		"concept": "脏数据与编码噪声（Data Noise）",
		"desc": "训练语料中混入的乱码、网页标签和损坏字符。虽然单个威胁不大，但成群合围会严重拖垮模型表现——数据清洗永远是 AI 第一步！",
	},
	{
		"kind": "hallucination",
		"name": "幻觉幽灵",
		"concept": "AI 幻觉（Hallucination）",
		"desc": "飘忽蛇形、速度极快。象征大模型在缺乏依据时自信编造假事实的现象：看起来像真的，实则随时会误导你！",
	},
	{
		"kind": "spam_tank",
		"name": "垃圾邮件傀儡",
		"concept": "数据投毒与批量垃圾语料",
		"desc": "厚重的橙红方块机甲，击退抗性高。代表互联网上批量生成的低质内容农场，击破它有概率掉落全图 Token 磁铁。",
	},
	{
		"kind": "prompt_bomb",
		"name": "Prompt 注入炸弹",
		"concept": "提示词注入攻击（Prompt Injection）",
		"desc": "潜伏在网页或文档里的恶意指令，靠近会闪红蓄力自爆！但只要提前识破并远程打爆，就能借它的爆炸连锁清理大片怪物。",
	},
	{
		"kind": "boss",
		"name": "过拟合巨像 / 魔王",
		"concept": "过拟合（Overfitting）",
		"desc": "死记硬背训练题却不会举一反三的庞然大物，拥有高额血量与环形弹幕。击破精英巨像必掉黄金 Token 宝箱，击破终极魔王即可守护检查点同步成功！",
	},
]

static var _last_idx := -1


static func pick_random() -> Dictionary:
	var idx := randi() % LIST.size()
	if LIST.size() > 1 and idx == _last_idx:
		idx = (idx + 1) % LIST.size()
	_last_idx = idx
	return LIST[idx]
