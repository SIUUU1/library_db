"""
make_screenshots.py : 쿼리를 다시 실행해 "실행 결과 화면"을 PNG로 캡처한다.

동작 : 01~02로 DB를 새로 만든 뒤 03/04의 쿼리를 순서대로 실행하고,
       쿼리별 실행 결과를 HTML로 그린 다음 헤드리스 Chrome으로 스크린샷을 찍는다.
       (결과 텍스트는 run_all.py, 결과 이미지는 이 스크립트가 만든다)

실행 : python3 make_screenshots.py
출력 : results/screenshots/Q01.png ~ Q19.png, B1-1.png ~ B3-3.png
"""
import html
import re
import shutil
import sqlite3
import subprocess
import tempfile
from pathlib import Path

import run_all  # 블록/문장 분리 로직 재사용

BASE = Path(__file__).resolve().parent
DB_PATH = BASE / "shots.db"
SHOT_DIR = BASE / "results" / "screenshots"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

CSS = """
* { box-sizing: border-box; }
body { margin: 0; padding: 28px; background: #eef1f5;
       font-family: -apple-system, "Apple SD Gothic Neo", "Helvetica Neue", sans-serif; }
.card { background: #fff; border-radius: 10px; overflow: hidden;
        box-shadow: 0 1px 3px rgba(0,0,0,.18); }
.titlebar { background: #2f3b4c; color: #fff; padding: 11px 16px; font-size: 14px; font-weight: 600; }
.titlebar .file { float: right; font-weight: 400; opacity: .72; font-size: 12.5px; }
.sql { background: #1e2633; color: #d8e0ea; margin: 0; padding: 14px 16px;
       font-family: Menlo, "SF Mono", monospace; font-size: 12.5px; line-height: 1.55;
       white-space: pre; overflow: hidden; }
.sql .c { color: #7f93aa; }
.stmt { padding: 11px 16px 4px; font-family: Menlo, monospace; font-size: 12px; color: #4a5768; }
.stmt b { color: #2f3b4c; }
table { border-collapse: collapse; width: calc(100% - 32px); margin: 8px 16px 2px;
        font-size: 13px; font-variant-numeric: tabular-nums; }
th { background: #f3f5f8; color: #2f3b4c; text-align: left; font-weight: 600;
     padding: 7px 11px; border: 1px solid #d5dbe3; white-space: nowrap; }
td { padding: 6px 11px; border: 1px solid #e2e7ee; white-space: nowrap; }
tr:nth-child(even) td { background: #fafbfd; }
td.null { color: #9aa6b5; font-style: italic; }
.rows { padding: 4px 16px 14px; color: #6b7889; font-size: 12px; }
.ok { margin: 8px 16px 14px; padding: 8px 12px; border-radius: 6px; font-size: 13px;
      background: #e8f5ec; color: #1d6b38; border: 1px solid #c3e4cf; }
.err { margin: 8px 16px 14px; padding: 8px 12px; border-radius: 6px; font-size: 13px;
       background: #fdecec; color: #a32020; border: 1px solid #f3c6c6;
       font-family: Menlo, monospace; }
"""


def color_sql(sql: str) -> str:
    out = []
    for line in sql.splitlines():
        esc = html.escape(line)
        out.append(f'<span class="c">{esc}</span>' if line.strip().startswith("--") else esc)
    return "\n".join(out)


def run(conn, stmt):
    """(종류, 내용) 반환 — ('table', (cols, rows)) / ('ok', 메시지) / ('err', 메시지)"""
    try:
        cur = conn.execute(stmt)
        if cur.description:
            return "table", ([d[0] for d in cur.description], cur.fetchall())
        conn.commit()
        if cur.rowcount >= 0 and re.match(r"^\s*(UPDATE|DELETE|INSERT)", stmt, re.I):
            return "ok", f"OK — {cur.rowcount} row(s) affected"
        return "ok", "OK"
    except sqlite3.Error as e:
        return "err", f"ERROR: {e}"


def render(block, source, results):
    """쿼리 1개 블록을 HTML 문서 문자열과 예상 높이(px)로 만든다."""
    title = f'{block["id"]} · {block["title"]}'
    body = [f'<div class="card"><div class="titlebar">{html.escape(title)}'
            f'<span class="file">{source}</span></div>'
            f'<pre class="sql">{color_sql(block["sql"].strip())}</pre>']
    height = 28 * 2 + 42 + len(block["sql"].strip().splitlines()) * 20 + 30

    for stmt, (kind, payload) in results:
        # 주석 줄을 뺀 실제 SQL의 첫 줄만 'sqlite>' 뒤에 보여 준다
        code = [l for l in stmt.splitlines() if not l.strip().startswith("--")]
        head = code[0][:110] + (" …" if len(code) > 1 else "")
        body.append(f'<div class="stmt"><b>sqlite&gt;</b> {html.escape(head)}</div>')
        height += 30
        if kind == "table":
            cols, rows = payload
            body.append("<table><tr>" + "".join(f"<th>{html.escape(c)}</th>" for c in cols) + "</tr>")
            for r in rows:
                cells = "".join(
                    '<td class="null">NULL</td>' if v is None else f"<td>{html.escape(str(v))}</td>"
                    for v in r)
                body.append(f"<tr>{cells}</tr>")
            body.append(f'</table><div class="rows">({len(rows)} rows)</div>')
            height += 40 + len(rows) * 29 + 26
        else:
            body.append(f'<div class="{kind}">{html.escape(payload)}</div>')
            height += 50
    body.append("</div>")
    doc = (f'<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8">'
           f"<style>{CSS}</style></head><body>" + "".join(body) + "</body></html>")
    return doc, height


def main():
    if not Path(CHROME).exists():
        raise SystemExit(f"Chrome을 찾을 수 없습니다: {CHROME}")
    if DB_PATH.exists():
        DB_PATH.unlink()
    if SHOT_DIR.exists():
        shutil.rmtree(SHOT_DIR)
    SHOT_DIR.mkdir(parents=True)

    conn = sqlite3.connect(DB_PATH)
    for name in ("01_schema.sql", "02_insert_data.sql"):
        conn.executescript((BASE / name).read_text(encoding="utf-8"))
        conn.execute("PRAGMA foreign_keys = ON")

    tmp = Path(tempfile.mkdtemp())
    count = 0
    for source in ("03_queries.sql", "04_bonus.sql"):
        for block in run_all.split_blocks((BASE / source).read_text(encoding="utf-8")):
            results = [(s, run(conn, s)) for s in run_all.split_statements(block["sql"])]
            if not block["id"]:
                continue
            doc, height = render(block, source, results)
            page = tmp / f'{block["id"]}.html'
            page.write_text(doc, encoding="utf-8")
            subprocess.run(
                [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                 "--force-device-scale-factor=2",
                 f"--window-size=1180,{min(height, 4000)}",
                 f'--screenshot={SHOT_DIR / (block["id"] + ".png")}', page.as_uri()],
                check=True, capture_output=True)
            count += 1
    conn.close()
    DB_PATH.unlink()
    shutil.rmtree(tmp)
    print(f"done: {count} screenshots in {SHOT_DIR}")


if __name__ == "__main__":
    main()
