-- =====================================================================
-- 04_bonus.sql : 보너스 과제
-- 실행 : sqlite3 library.db < 04_bonus.sql  (01 → 02 → 03 실행 후)
--   B1. 같은 요구를 JOIN / 서브쿼리 두 방식으로 풀고 비교
--   B2. 데이터 정합성 깨뜨려 보기 (FK 에러 재현과 해결)
--   B3. 미니 리포트 : 이 DB로 뽑을 수 있는 핵심 지표 3개
-- =====================================================================

PRAGMA foreign_keys = ON;   -- [SQLite 전용] FK 검사 활성화


-- =====================================================================
-- B1. 조인 1개를 두 방식으로 풀기
-- 요구 : "IT/컴퓨터 카테고리 도서를 한 번이라도 빌린 회원 목록"
-- =====================================================================

-- [B1-1] JOIN 방식
-- 설명: rental-book-category-member를 연결한 뒤 같은 회원이 여러 번 나오지 않도록 DISTINCT 처리한다.
SELECT DISTINCT m.member_id, m.name
FROM member m
INNER JOIN rental   r ON m.member_id   = r.member_id
INNER JOIN book     b ON r.book_id     = b.book_id
INNER JOIN category c ON b.category_id = c.category_id
WHERE c.name = 'IT/컴퓨터'
ORDER BY m.member_id;

-- [B1-2] 서브쿼리 방식
-- 설명: 안쪽에서 'IT/컴퓨터 도서를 빌린 member_id 목록'을 먼저 만들고, 바깥에서 그 목록에 속한 회원만 고른다.
SELECT m.member_id, m.name
FROM member m
WHERE m.member_id IN (
    SELECT r.member_id
    FROM rental r
    WHERE r.book_id IN (
        SELECT b.book_id
        FROM book b
        WHERE b.category_id = (SELECT category_id FROM category WHERE name = 'IT/컴퓨터')
    )
)
ORDER BY m.member_id;

-- 비교 정리
--  - 결과 : 두 쿼리 결과는 같다 (김민준, 강시우, 정하은).
--  - JOIN : 여러 테이블의 컬럼(도서명, 대여일 등)을 결과에 함께 보여줄 수 있다.
--           대신 1:N 관계 때문에 같은 회원이 여러 행으로 늘어나므로 DISTINCT가 필요하다.
--  - 서브쿼리 : "조건 판단"에만 다른 테이블을 쓰므로 중복이 생기지 않고, 읽는 순서가 요구사항 문장과 비슷하다.
--           대신 안쪽 테이블의 컬럼을 결과에 꺼낼 수 없다.
--  - 성능 : 최신 옵티마이저는 IN 서브쿼리를 조인으로 바꿔 실행하는 경우가 많아 소규모 데이터에선 차이가 거의 없다.
--           결과에 여러 테이블 정보가 필요하면 JOIN, "존재 여부"만 필요하면 서브쿼리(IN/EXISTS)가 자연스럽다.


-- =====================================================================
-- B2. 데이터 정합성 깨뜨려 보기
-- =====================================================================

-- [B2-1] 존재하지 않는 회원으로 대여 기록 입력 (실패 예상)
-- 설명: member 테이블에 없는 member_id = 999 로 rental을 INSERT 하면 FK 위반으로 막히는지 확인한다.
INSERT INTO rental (rental_id, member_id, book_id, rented_at, due_date, status)
VALUES (21, 999, 3, '2026-10-29', '2026-11-12', 'RENTED');

-- [B2-2] 존재하지 않는 카테고리로 도서 입력 (실패 예상)
-- 설명: category 테이블에 없는 category_id = 50 으로 book을 INSERT 하면 막히는지 확인한다.
INSERT INTO book (book_id, category_id, title, author, publisher, isbn, published_year, price, total_copies)
VALUES (16, 50, '데이터베이스 개론', '홍길동', '예시출판', '978-89-0000-0016', 2024, 30000, 1);

-- [B2-3] 대여 기록이 있는 회원 삭제 (실패 예상)
-- 설명: 자식(rental, review)이 참조 중인 부모(member 1번)를 지우면 '고아 데이터'가 생기므로 막히는지 확인한다.
DELETE FROM member WHERE member_id = 1;

-- [B2-4] 해결 방법 : 부모 데이터를 먼저 만들고, 올바른 키로 자식 데이터를 입력
-- 설명: 회원(13번)을 먼저 INSERT 한 뒤 그 회원 번호로 rental을 INSERT 하면 성공하는지 확인한다.
INSERT INTO member (member_id, name, email, phone, joined_at, status)
VALUES (13, '서준호', 'junho.seo@example.com', '010-1234-0013', '2026-10-29', 'ACTIVE');

INSERT INTO rental (rental_id, member_id, book_id, rented_at, due_date, status)
VALUES (21, 13, 3, '2026-10-29', '2026-11-12', 'RENTED');

SELECT r.rental_id, m.name, b.title, r.rented_at, r.due_date, r.status
FROM rental r
INNER JOIN member m ON r.member_id = m.member_id
INNER JOIN book   b ON r.book_id   = b.book_id
WHERE r.rental_id = 21;

-- 정리
--  - 왜 막히나 : FK는 "자식 테이블의 값은 반드시 부모 테이블의 PK에 존재해야 한다"는 규칙이다.
--               없는 회원(999)·없는 카테고리(50)를 가리키면 누구의 대여인지, 어떤 분류인지 알 수 없는 데이터가 되므로 DB가 거부한다.
--               반대로 자식이 참조 중인 부모를 지우면 남은 대여 기록이 존재하지 않는 회원을 가리키게 되므로 삭제도 거부한다.
--  - 어떻게 고치나 : (1) 부모 행을 먼저 INSERT 하고 자식을 INSERT 한다 (입력 순서 = category/member → book → rental/review)
--                   (2) 오타라면 실제 존재하는 키 값으로 고친다.
--                   (3) 회원 삭제가 꼭 필요하면 자식 데이터를 먼저 정리하거나, 실무에선 status='WITHDRAWN' 처럼 상태값으로 비활성화한다.
--  - SQLite 주의 : PRAGMA foreign_keys = ON 을 빠뜨리면 위 입력이 모두 '성공'해 버린다. FK가 실제로 동작하게 하려면 반드시 켠다.


-- =====================================================================
-- B3. 미니 리포트 : 핵심 지표 3개 (최종본)
-- =====================================================================

-- [B3-1] 지표 1. 월별 대여 건수 및 연체 발생 추이
-- 설명: 월별로 대여 건수, 그중 연체된 건수(늦게 반납 + 기한 지난 미반납), 연체율(%)을 확인한다.
SELECT SUBSTR(rented_at, 1, 7) AS rental_month,
       COUNT(*) AS rental_count,
       SUM(CASE WHEN returned_at > due_date
                  OR (returned_at IS NULL AND due_date < '2026-10-29')
                THEN 1 ELSE 0 END) AS overdue_count,
       ROUND(100.0 * SUM(CASE WHEN returned_at > due_date
                                OR (returned_at IS NULL AND due_date < '2026-10-29')
                              THEN 1 ELSE 0 END) / COUNT(*), 1) AS overdue_rate_pct
FROM rental
GROUP BY SUBSTR(rented_at, 1, 7)
ORDER BY rental_month;

-- [B3-2] 지표 2. 인기 도서 TOP 10 (대여 횟수 기준, 동률이면 평균 평점 순)
-- 설명: 대여 횟수와 평균 평점을 함께 집계해 가장 많이 빌려간 도서 10권을 확인한다.
SELECT b.title,
       c.name AS category_name,
       COUNT(r.rental_id) AS rental_count,
       (SELECT ROUND(AVG(rv.rating), 2) FROM review rv WHERE rv.book_id = b.book_id) AS avg_rating
FROM book b
INNER JOIN category c ON b.category_id = c.category_id
LEFT JOIN rental r    ON b.book_id = r.book_id
GROUP BY b.book_id, b.title, c.name
ORDER BY rental_count DESC, avg_rating DESC, b.book_id
LIMIT 10;

-- [B3-3] 지표 3. 연체율이 높은 회원 목록
-- 설명: 회원별 전체 대여 중 연체된 비율을 계산해, 연체 이력이 있는 회원을 연체율 높은 순으로 확인한다.
SELECT m.member_id,
       m.name,
       m.status AS member_status,
       COUNT(r.rental_id) AS rental_count,
       SUM(CASE WHEN r.returned_at > r.due_date
                  OR (r.returned_at IS NULL AND r.due_date < '2026-10-29')
                THEN 1 ELSE 0 END) AS overdue_count,
       ROUND(100.0 * SUM(CASE WHEN r.returned_at > r.due_date
                                OR (r.returned_at IS NULL AND r.due_date < '2026-10-29')
                              THEN 1 ELSE 0 END) / COUNT(r.rental_id), 1) AS overdue_rate_pct
FROM member m
INNER JOIN rental r ON m.member_id = r.member_id
GROUP BY m.member_id, m.name, m.status
HAVING SUM(CASE WHEN r.returned_at > r.due_date
                  OR (r.returned_at IS NULL AND r.due_date < '2026-10-29')
                THEN 1 ELSE 0 END) > 0     -- 표준 SQL은 HAVING에서 별칭을 못 쓰므로 식을 다시 적는다
ORDER BY overdue_rate_pct DESC, overdue_count DESC, m.member_id;
