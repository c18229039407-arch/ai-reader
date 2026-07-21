/// 名著书名地图（A4 检索增强）。
///
/// 背景：外国经典的「原著」多已进入公有领域（Gutenberg 有英文/原文版），
/// 但「中文译本」有译者版权（译者逝世 50 年内受保护）——所以用中文书名
/// 在公版库搜是 0 结果。此表把常见中文书名映射到原著检索词，
/// 中文搜索落空时自动转搜原著。
///
/// 收录原则：仅收原著确认公版、且已在 Gutenberg 验证可检索到的作品。
library;

/// 中文书名（去《》与空白后精确匹配）→ (Gutenberg 检索词, 原名展示)。
const Map<String, (String query, String display)> titleAtlas = {
  // —— 哲学 / 政治 / 经济 ——
  '瓦尔登湖': ('Walden Thoreau', 'Walden'),
  '理想国': ('Republic Plato', 'The Republic'),
  '苏格拉底的申辩': ('Apology Plato', 'Apology'),
  '申辩篇': ('Apology Plato', 'Apology'),
  '社会契约论': ('Social Contract Rousseau', 'The Social Contract'),
  '论法的精神': ('Spirit of Laws Montesquieu', 'The Spirit of Laws'),
  '国富论': ('Wealth of Nations Smith', 'The Wealth of Nations'),
  '物种起源': ('Origin of Species Darwin', 'On the Origin of Species'),
  '沉思录': ('Meditations Marcus Aurelius', 'Meditations'),
  '尼各马可伦理学': ('Nicomachean Ethics Aristotle', 'Nicomachean Ethics'),
  '政治学': ('Politics Aristotle', 'Politics'),
  '乌托邦': ('Utopia More', 'Utopia'),
  '君主论': ('Prince Machiavelli', 'The Prince'),
  '论自由': ('On Liberty Mill', 'On Liberty'),
  '功利主义': ('Utilitarianism Mill', 'Utilitarianism'),
  '常识': ('Common Sense Paine', 'Common Sense'),
  '查拉图斯特拉如是说': ('Thus Spake Zarathustra', 'Thus Spake Zarathustra'),
  '善恶的彼岸': ('Beyond Good and Evil', 'Beyond Good and Evil'),
  '悲剧的诞生': ('Birth of Tragedy Nietzsche', 'The Birth of Tragedy'),
  '梦的解析': ('Interpretation of Dreams Freud', 'The Interpretation of Dreams'),
  '战争论': ('On War Clausewitz', 'On War'),
  '乌合之众': ('The Crowd Le Bon', 'The Crowd'),

  // —— 英美文学 ——
  '傲慢与偏见': ('Pride and Prejudice', 'Pride and Prejudice'),
  '理智与情感': ('Sense and Sensibility', 'Sense and Sensibility'),
  '简爱': ('Jane Eyre', 'Jane Eyre'),
  '简·爱': ('Jane Eyre', 'Jane Eyre'),
  '呼啸山庄': ('Wuthering Heights', 'Wuthering Heights'),
  '双城记': ('Tale of Two Cities', 'A Tale of Two Cities'),
  '雾都孤儿': ('Oliver Twist', 'Oliver Twist'),
  '大卫·科波菲尔': ('David Copperfield', 'David Copperfield'),
  '远大前程': ('Great Expectations', 'Great Expectations'),
  '鲁滨逊漂流记': ('Robinson Crusoe', 'Robinson Crusoe'),
  '格列佛游记': ('Gulliver\'s Travels', 'Gulliver\'s Travels'),
  '金银岛': ('Treasure Island', 'Treasure Island'),
  '道林·格雷的画像': ('Picture of Dorian Gray', 'The Picture of Dorian Gray'),
  '福尔摩斯探案集': ('Adventures of Sherlock Holmes', 'The Adventures of Sherlock Holmes'),
  '爱丽丝梦游仙境': ('Alice\'s Adventures in Wonderland', 'Alice\'s Adventures in Wonderland'),
  '小妇人': ('Little Women', 'Little Women'),
  '汤姆·索亚历险记': ('Tom Sawyer', 'The Adventures of Tom Sawyer'),
  '哈克贝利·费恩历险记': ('Huckleberry Finn', 'Adventures of Huckleberry Finn'),
  '白鲸': ('Moby Dick', 'Moby Dick'),
  '了不起的盖茨比': ('Great Gatsby', 'The Great Gatsby'),
  '月亮与六便士': ('Moon and Sixpence', 'The Moon and Sixpence'),
  '人性的枷锁': ('Of Human Bondage', 'Of Human Bondage'),

  // —— 欧陆 / 俄国文学 ——
  '悲惨世界': ('Les Miserables', 'Les Misérables'),
  '巴黎圣母院': ('Notre-Dame de Paris Hugo', 'Notre-Dame de Paris'),
  '基督山伯爵': ('Count of Monte Cristo', 'The Count of Monte Cristo'),
  '三个火枪手': ('Three Musketeers', 'The Three Musketeers'),
  '包法利夫人': ('Madame Bovary', 'Madame Bovary'),
  '红与黑': ('Red and Black Stendhal', 'The Red and the Black'),
  '八十天环游地球': ('Around the World in Eighty Days', 'Around the World in Eighty Days'),
  '海底两万里': ('Twenty Thousand Leagues under the Sea', 'Twenty Thousand Leagues under the Sea'),
  '罪与罚': ('Crime and Punishment', 'Crime and Punishment'),
  '卡拉马佐夫兄弟': ('Brothers Karamazov', 'The Brothers Karamazov'),
  '白痴': ('Idiot Dostoyevsky', 'The Idiot'),
  '安娜·卡列尼娜': ('Anna Karenina', 'Anna Karenina'),
  '战争与和平': ('War and Peace', 'War and Peace'),
  '堂吉诃德': ('Don Quixote', 'Don Quixote'),
  '浮士德': ('Faust Goethe', 'Faust'),
  '少年维特之烦恼': ('Sorrows of Young Werther', 'The Sorrows of Young Werther'),
  '神曲': ('Divine Comedy Dante', 'The Divine Comedy'),
  '伊利亚特': ('Iliad', 'The Iliad'),
  '奥德赛': ('Odyssey Homer', 'The Odyssey'),
  '变形记': ('Metamorphosis Kafka', 'The Metamorphosis'),
};

/// 知名但不在合法公版书源内的书（版权仍受保护，或原著/译本受限）→ 出版年。
/// 用于给出「为什么搜不到」的精确解释，而不是含糊的通用文案。
const Map<String, int> knownUnavailable = {
  '人类简史': 2011,
  '未来简史': 2016,
  '今日简史': 2018,
  '三体': 2006,
  '活着': 1993,
  '平凡的世界': 1986,
  '围城': 1947,
  '百年孤独': 1967,
  '小王子': 1943,
  '老人与海': 1952,
  '1984': 1949,
  '一九八四': 1949,
  '动物农场': 1945,
  '动物庄园': 1945,
  '追风筝的人': 2003,
  '白夜行': 1999,
  '解忧杂货店': 2012,
  '苏菲的世界': 1991,
  '万历十五年': 1982,
  '乡土中国': 1948,
  '思考，快与慢': 2011,
  '思考快与慢': 2011,
  '穷查理宝典': 2005,
  '原则': 2017,
  '小岛经济学': 2010,
};

String _clean(String q) =>
    q.replaceAll(RegExp(r'[《》\s]'), '').trim();

/// 中文书名 → 原著检索词；无映射返回 null。
(String query, String display)? atlasLookup(String rawQuery) =>
    titleAtlas[_clean(rawQuery)];

/// 是否是已知的版权期内名著；命中返回出版年。
int? knownUnavailableYear(String rawQuery) =>
    knownUnavailable[_clean(rawQuery)];
