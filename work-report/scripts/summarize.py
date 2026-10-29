#!/usr/bin/env python3
"""把 collect.sh 采到的 commit 数据算成规模统计段（stdout），并给出仓库排序（写 order 文件）。

存在的理由：提交次数、覆盖天数、新增行数都是纯计数，模型从上百条记录里数会错，
而周报的主线段要求带规模数字。这里算完、模型照抄。
用法：summarize.py <data.tsv> <order-out> <daily|weekly>
data.tsv 每行：仓库 \t "MM-DD HH:MM" \t diffstat \t 状态词 \t commit 标题
"""
import re
import sys
from collections import defaultdict


def parse_prefix(title):
    """conventional commit 的 scope 优先，其次 type，都没有就归「无前缀」。"""
    m = re.match(r'^([A-Za-z]+)\(([^)]+)\)!?\s*:', title)
    if m:
        return m.group(2).strip()
    m = re.match(r'^([A-Za-z]+)!?\s*:', title)
    if m:
        return m.group(1).strip()
    return '无前缀'


def fmt_days(days):
    ds = sorted(days)
    if len(ds) > 4:
        return f'{ds[0]}~{ds[-1]}'
    return ','.join(ds)


def main():
    data_path, order_path, period = sys.argv[1], sys.argv[2], sys.argv[3]
    rows = []
    with open(data_path, encoding='utf-8') as f:
        for ln in f:
            parts = ln.rstrip('\n').split('\t')
            if len(parts) < 5:
                continue
            repo, tstr, stat, word, title = parts[0], parts[1], parts[2], parts[3], '\t'.join(parts[4:])
            m = re.search(r'(\d+) insertions?\(\+\)', stat)
            ins = int(m.group(1)) if m else 0
            rows.append({'repo': repo, 'day': tstr.split()[0], 'ins': ins,
                         'word': word, 'prefix': parse_prefix(title)})
    if not rows:
        open(order_path, 'w').close()
        return

    def blank():
        return {'n': 0, 'ins': 0, 'days': set(), 'words': defaultdict(int)}

    by_repo = defaultdict(blank)
    by_topic = defaultdict(blank)
    for r in rows:
        for bucket in (by_repo[r['repo']], by_topic[(r['repo'], r['prefix'])]):
            bucket['n'] += 1
            bucket['ins'] += r['ins']
            bucket['days'].add(r['day'])
            bucket['words'][r['word']] += 1

    # 工作量排序：提交次数为主，改动规模次之。明细分组与主线顺序都照这个来。
    repo_order = sorted(by_repo, key=lambda k: (-by_repo[k]['n'], -by_repo[k]['ins'], k))
    with open(order_path, 'w', encoding='utf-8') as f:
        for r in repo_order:
            f.write(r + '\n')

    label = '本周' if period == 'weekly' else '今天'
    out = []
    out.append(f'## 规模统计（脚本已算好，{label}的提交次数、覆盖天数、新增行数直接引用，不要自己数）')
    out.append('')
    out.append('### 仓库（已按工作量排序，报告的分组顺序照这个写）')
    out.append('')
    out.append('| 仓库 | 提交 | 新增行 | 覆盖天数 | 日期 |')
    out.append('|---|---|---|---|---|')
    for k in repo_order:
        v = by_repo[k]
        out.append(f'| {k} | {v["n"]} | {v["ins"]} | {len(v["days"])} | {fmt_days(v["days"])} |')
    out.append('')
    out.append('### 主题（按 commit 前缀归并。前缀是代码里的 scope，只用来分组和数数，不要当模块名写进报告）')
    out.append('')
    out.append('| 仓库 | 前缀 | 提交 | 新增行 | 天数 | 日期 | 状态 |')
    out.append('|---|---|---|---|---|---|---|')
    topic_order = sorted(by_topic, key=lambda k: (repo_order.index(k[0]), -by_topic[k]['n'], -by_topic[k]['ins']))
    for k in topic_order:
        v = by_topic[k]
        words = '，'.join(f'{w.strip("【】")}×{c}' for w, c in
                          sorted(v['words'].items(), key=lambda x: -x[1]))
        out.append(f'| {k[0]} | {k[1]} | {v["n"]} | {v["ins"]} | {len(v["days"])} | '
                   f'{fmt_days(v["days"])} | {words} |')
    out.append('')
    all_days = {r['day'] for r in rows}
    out.append(f'合计 {len(rows)} 次提交，{len(by_repo)} 个仓库，覆盖 {len(all_days)} 天'
               f'（{fmt_days(all_days)}）。')
    if period == 'weekly':
        out.append('一条主线跨多个前缀时，提交数把这几行相加、天数按日期并集数，不要估。')
    out.append('')
    print('\n'.join(out))


if __name__ == '__main__':
    main()
