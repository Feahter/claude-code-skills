#!/usr/bin/env python3
"""草稿自检：把「格式对不对」这件事从人眼挪到脚本。

只报告不修改，也不阻断流程——generate.sh 把结果写进草稿末尾的本地注脚（发送时会被剥离），
人工过目时直接看这几行，不必自己数条数、量字数。
用法：lint-draft.py <draft.md> <daily|weekly>
退出码恒为 0；有问题时每行一条打到 stdout。
"""
import re
import sys

MAX_CHARS = 30
STATES = ('已完成', '跟版中', '今日跟版', '测试中', '开发中', '待提测')
SIGN = '*发送工具*'


def body_of(path):
    """与 send.sh 相同的正文口径：去掉首行标题，在末尾 --- 处截断。"""
    lines = open(path, encoding='utf-8').read().splitlines()
    if lines and lines[0].startswith('#'):
        lines = lines[1:]
    for i in range(len(lines) - 1, -1, -1):
        if lines[i].strip() == '---':
            lines = lines[:i]
            break
    return '\n'.join(lines).strip()


def main():
    path, period = sys.argv[1], sys.argv[2]
    body = body_of(path)
    problems = []

    if body.startswith('>') and '归纳失败' in body[:200]:
        print('归纳失败回退成原始素材，未做格式自检')
        return

    weekly = period == 'weekly'
    detail_body = body
    if weekly:
        if '*本周主线*' not in body:
            problems.append('缺「*本周主线*」段')
        if '*工作明细*' not in body:
            problems.append('缺「*工作明细*」段')
        if '*本周主线*' in body and '*工作明细*' in body:
            head, detail_body = body.split('*工作明细*', 1)
            head = head.split('*本周主线*', 1)[1]
            mains = [ln.strip() for ln in head.splitlines()
                     if ln.strip() and not ln.strip().startswith('*')]
            if not 3 <= len(mains) <= 5:
                problems.append(f'主线 {len(mains)} 条，要求 3 到 5 条')
            for m in mains:
                if '次提交' not in m:
                    problems.append(f'主线没带规模（覆盖几天、多少次提交）：{m[:24]}')

    items = [ln.strip() for ln in detail_body.splitlines() if re.match(r'^\d+\.\s', ln.strip())]
    if not items:
        problems.append('没有编号明细条目')
    for it in items:
        text = re.sub(r'^\d+\.\s*', '', it)
        m = re.search(r'【(' + '|'.join(STATES) + r')】(.*)$', text)
        if m:
            state = m.group(1)
            core = text[:m.start()]
            if weekly and state == '今日跟版':
                problems.append(f'周报不写【今日跟版】，应为【跟版中】：{core[:20]}')
            if not weekly and state == '跟版中':
                problems.append(f'日报不写【跟版中】，应为【今日跟版】：{core[:20]}')
        elif re.search(r'\d+%$', text):
            core = re.sub(r'\d+%$', '', text)
        else:
            problems.append(f'句末缺状态标注：{text[:24]}')
            core = text
        if len(core.strip()) > MAX_CHARS:
            problems.append(f'{len(core.strip())} 字，超出 {MAX_CHARS}：{core.strip()[:34]}')

    if not weekly and len(items) > 8:
        problems.append(f'日报 {len(items)} 条，上限 8 条')

    if SIGN not in body:
        problems.append('缺署名行')

    kind = '周报' if weekly else '日报'
    if problems:
        print(f'{kind}格式自检：{len(problems)} 处待人工确认（明细 {len(items)} 条）')
        for p in problems:
            print(f'- {p}')
    else:
        print(f'{kind}格式自检通过（明细 {len(items)} 条）')


if __name__ == '__main__':
    main()
