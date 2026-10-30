"""
run_all.py : SQL 파일을 순서대로 실행하고 쿼리별 실행 결과를 results/ 폴더에 텍스트로 저장한다.
(백엔드 프레임워크가 아니라, sqlite3 CLI가 없는 환경에서 결과 캡처를 자동화하는 보조 스크립트)

실행 : python3 run_all.py
"""
import re
import sqlite3
import unicodedata
from pathlib import Path

BASE = Path(__file__).resolve().parent
DB_PATH = BASE / "library.db"
RESULT_DIR = BASE / "results"
MARKER = re.compile(r"^-- \[(?P<id>[A-Z]\d+(?:-\d+)?)\]\s*(?P<title>.*)$")


def width(s: str) -> int:
    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in s)


def pad(s: str, w: int) -> str:
    return s + " " * (w - width(s))


def fmt_table(cols, rows) -> str:
    cells = [["NULL" if v is None else str(v) for v in row] for row in rows]
    widths = [max([width(c)] + [width(r[i]) for r in cells]) for i, c in enumerate(cols)]
    line = "+" + "+".join("-" * (w + 2) for w in widths) + "+"
    out = [line, "| " + " | ".join(pad(c, w) for c, w in zip(cols, widths)) + " |", line]
    out += ["| " + " | ".join(pad(v, w) for v, w in zip(r, widths)) + " |" for r in cells]
    out.append(line)
    out.append(f"({len(rows)} rows)")
    return "\n".join(out)


def split_statements(sql: str):
    """주석만 있는 조각은 버리고, 완성된 SQL 문 단위로 나눈다."""
    stmts, buf = [], ""
    for line in sql.splitlines(keepends=True):
        buf += line
        if sqlite3.complete_statement(buf):
            code = "\n".join(l for l in buf.splitlines() if not l.strip().startswith("--")).strip()
            if code:
                stmts.append(buf.strip())
            buf = ""
    return stmts


def split_blocks(text: str):
    """'-- [Q01] 제목' 마커 기준으로 (id, title, 원문) 블록 목록을 만든다. 마커 이전 부분은 id=None."""
    blocks, cur = [], {"id": None, "title": "", "lines": []}
    for line in text.splitlines():
        m = MARKER.match(line)
        if m:
            blocks.append(cur)
            cur = {"id": m["id"], "title": m["title"].strip(), "lines": [line]}
        else:
            cur["lines"].append(line)
    blocks.append(cur)
    for b in blocks:
        # 블록 끝의 구분용 주석(다음 섹션 머리말)은 결과 파일에서 제외
        lines = b["lines"]
        while lines and (not lines[-1].strip() or re.match(r"^-- (=+|\d+\.|B\d\.)", lines[-1])
                         or lines[-1].startswith("-- 요구")):
            lines.pop()
        b["sql"] = "\n".join(lines)
    return blocks


def run_stmt(conn, stmt):
    try:
        cur = conn.execute(stmt)
        if cur.description:
            cols = [d[0] for d in cur.description]
            return fmt_table(cols, cur.fetchall())
        conn.commit()
        if cur.rowcount >= 0 and re.match(r"^\s*(--.*\n\s*)*(UPDATE|DELETE|INSERT)", stmt, re.I):
            return f"OK — {cur.rowcount} row(s) affected"
        return "OK"
    except sqlite3.Error as e:
        return f"ERROR: {e}"


def main():
    if DB_PATH.exists():
        DB_PATH.unlink()
    RESULT_DIR.mkdir(exist_ok=True)
    for old in RESULT_DIR.glob("*.txt"):
        old.unlink()

    conn = sqlite3.connect(DB_PATH)
    summary = []

    # 1) 스키마 + 데이터 : 통째로 실행
    for name in ("01_schema.sql", "02_insert_data.sql"):
        conn.executescript((BASE / name).read_text(encoding="utf-8"))
        conn.execute("PRAGMA foreign_keys = ON")

    # 테이블별 행 수 / FK 설정 확인
    lines = ["[00] 스키마·샘플 데이터 적재 확인", "설명: 01_schema.sql, 02_insert_data.sql 실행 후 테이블별 행 수와 FK 설정을 확인한다.", ""]
    lines.append("-- 테이블별 행 수")
    lines.append(run_stmt(conn, """
        SELECT 'category' AS table_name, COUNT(*) AS row_count FROM category UNION ALL
        SELECT 'member', COUNT(*) FROM member UNION ALL
        SELECT 'book',   COUNT(*) FROM book   UNION ALL
        SELECT 'rental', COUNT(*) FROM rental UNION ALL
        SELECT 'review', COUNT(*) FROM review"""))
    lines.append("\n-- FK 활성화 여부 (PRAGMA foreign_keys, 1 = ON)")
    lines.append(run_stmt(conn, "PRAGMA foreign_keys"))
    for t in ("book", "rental", "review"):
        lines.append(f"\n-- {t} 테이블의 FK 목록 (PRAGMA foreign_key_list)")
        lines.append(run_stmt(conn, f"SELECT \"table\" AS parent_table, \"from\" AS fk_column, \"to\" AS parent_pk "
                                    f"FROM pragma_foreign_key_list('{t}')"))
    (RESULT_DIR / "00_schema_and_data_check.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    summary.append("\n".join(lines))

    # 2) 쿼리 / 보너스 : 블록 단위 실행 + 결과 저장
    for name in ("03_queries.sql", "04_bonus.sql"):
        for b in split_blocks((BASE / name).read_text(encoding="utf-8")):
            outputs = []
            for stmt in split_statements(b["sql"]):
                res = run_stmt(conn, stmt)
                if b["id"]:
                    code = "\n".join(l for l in stmt.splitlines() if not l.strip().startswith("--")).strip()
                    outputs.append(f"sqlite> {code}\n{res}")
            if not b["id"]:
                continue
            body = f"{b['sql'].strip()}\n\n----- 실행 결과 -----\n\n" + "\n\n".join(outputs) + "\n"
            safe = re.sub(r"[^\w가-힣]+", "_", b["title"]).strip("_")[:24]
            (RESULT_DIR / f"{b['id']}_{safe}.txt").write_text(body, encoding="utf-8")
            summary.append(body)

    sep = "\n\n" + "=" * 80 + "\n\n"
    (RESULT_DIR / "ALL_RESULTS.txt").write_text(sep.join(summary), encoding="utf-8")
    conn.close()
    print(f"done: {len(list(RESULT_DIR.glob('*.txt')))} files in {RESULT_DIR}")


if __name__ == "__main__":
    main()
