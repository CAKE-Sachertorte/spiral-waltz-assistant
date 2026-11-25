import fs from 'node:fs';
import vm from 'node:vm';
import crypto from 'node:crypto';
const sourcePath = process.argv[2] ?? '../螺旋圆舞曲攻略器.html';
const source = fs.readFileSync(sourcePath, 'utf8');
const begin = source.indexOf('const PROFILES=');
const end = source.indexOf('const canonicalQuestion=');
if (begin < 0 || end < begin) throw new Error('攻略格式不匹配');
const data = vm.runInNewContext(source.slice(begin, end) + '\n({GROUPS,CHAT_ROWS,QUESTION_GROUPS,QUESTION_TITLE_ALIASES,ANSWER_TEXT_SOURCES})', {}, {timeout: 1000});
const questions = data.QUESTION_GROUPS.flatMap(([, names], group) => names.map(name => ({name, group, answers: {}})));
for (const row of data.ANSWER_TEXT_SOURCES) {
  for (const [title, text] of Object.entries(row.answers)) {
    const q = questions.find(q => q.name === (data.QUESTION_TITLE_ALIASES[title] ?? title));
    if (!q) throw new Error(`未知题目 ${title}`);
    const ordinal = data.CHAT_ROWS[row.character][2][q.group];
    const list = q.answers[ordinal] ??= [];
    if (!list.includes(text)) list.push(text);
  }
}
const characters = data.GROUPS.flatMap(([, rows]) => rows).flatMap(([name, , aliases = []]) => {
  const row = data.CHAT_ROWS[name];
  return row ? [{name, aliases, topics: row[1].split(' '), codes: row[2].split('').map(Number)}] : [];
});
const output = {source: sourcePath.split('/').pop(), sha256: crypto.createHash('sha256').update(source).digest('hex'), characters, questions};
const target = new URL('../Sources/WaltzCore/Resources/guide.json', import.meta.url);
fs.writeFileSync(target, JSON.stringify(output, null, 2) + '\n');
console.log(`导出 ${characters.length} 位角色、${questions.length} 道题：${target.pathname}`);
