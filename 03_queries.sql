-- =====================================================================
-- 03_queries.sql : 핵심 SQL 쿼리 19개
-- 실행 : sqlite3 library.db < 03_queries.sql  (01 → 02 실행 후)
-- 기준일 : 2026-10-29 (오늘)
--
-- 범주별 구성
--   기본 조회   : Q01 ~ Q05  (WHERE, ORDER BY, LIMIT, LIKE, BETWEEN)
--   조인       : Q06 ~ Q09  (INNER JOIN 3개, LEFT JOIN 1개)
--   집계       : Q10 ~ Q13  (COUNT, SUM, AVG + GROUP BY, HAVING)
--   서브쿼리   : Q14 ~ Q15
--   수정/삭제  : Q16 ~ Q18  (UPDATE 2개, DELETE 1개)
--   인덱스     : Q19        (CREATE INDEX + 적용 이유)
--
-- ※ 수정/삭제 쿼리(Q16~Q18)는 데이터를 바꾸므로 조회 쿼리 뒤에 둔다.
-- ※ 각 블록의 '-- [Qnn]' 줄 다음 줄이 "무엇을 확인하는 쿼리인지" 한 줄 설명이다.
-- =====================================================================

PRAGMA foreign_keys = ON;   -- [SQLite 전용] FK 검사 활성화


-- =====================================================================
-- 1. 기본 조회
-- =====================================================================

-- [Q01] 2015년 이후 출간 도서
-- 설명: WHERE 조건으로 2015년 이후 출간된 도서만 골라 최신 출간순으로 확인한다.
SELECT book_id, title, author, published_year
FROM book
WHERE published_year >= 2015
ORDER BY published_year DESC, title;

-- [Q02] 가격이 높은 도서 TOP 5
-- 설명: ORDER BY + LIMIT로 정가가 가장 비싼 도서 5권을 확인한다.
SELECT title, author, price
FROM book
ORDER BY price DESC
LIMIT 5;

-- [Q03] 반납 예정일이 임박한 미반납 대여
-- 설명: 아직 반납되지 않은(returned_at IS NULL) 대여 건을 반납 예정일이 빠른 순으로 확인한다.
SELECT rental_id, member_id, book_id, rented_at, due_date, status
FROM rental
WHERE returned_at IS NULL
ORDER BY due_date ASC;

-- [Q04] 제목·저자 키워드 검색
-- 설명: LIKE로 제목에 'SQL' 또는 '코드'가 들어가거나 저자가 '한강'인 도서를 검색한다.
SELECT book_id, title, author
FROM book
WHERE title LIKE '%SQL%'
   OR title LIKE '%코드%'
   OR author = '한강'
ORDER BY book_id;

-- [Q05] 최근 30일 대여 기록
-- 설명: 기준일(2026-10-29)로부터 최근 30일(2026-09-29 ~ 2026-10-29) 동안의 대여 기록을 확인한다.
--       ※ 날짜를 'YYYY-MM-DD' 문자열로 저장해 표준 BETWEEN 비교로 작성했다.
--         오늘 날짜를 자동으로 쓰려면 SQLite: date('now','-30 days') / MySQL: CURDATE() - INTERVAL 30 DAY
SELECT rental_id, member_id, book_id, rented_at, status
FROM rental
WHERE rented_at BETWEEN '2026-09-29' AND '2026-10-29'
ORDER BY rented_at DESC;


-- =====================================================================
-- 2. 조인
-- =====================================================================

-- [Q06] (INNER JOIN) 현재 대여 중인 책 목록
-- 설명: rental-member-book 3개 테이블을 INNER JOIN 해 '누가 어떤 책을 언제까지 빌렸는지' 확인한다.
SELECT r.rental_id,
       m.name   AS member_name,
       b.title  AS book_title,
       r.rented_at,
       r.due_date,
       r.status
FROM rental r
INNER JOIN member m ON r.member_id = m.member_id
INNER JOIN book   b ON r.book_id   = b.book_id
WHERE r.returned_at IS NULL
ORDER BY r.due_date;

-- [Q07] (INNER JOIN) 도서 목록과 카테고리명
-- 설명: book-category를 INNER JOIN 해 category_id 숫자 대신 카테고리 이름으로 도서 목록을 확인한다.
SELECT b.book_id, b.title, c.name AS category_name, b.price
FROM book b
INNER JOIN category c ON b.category_id = c.category_id
ORDER BY c.category_id, b.book_id;

-- [Q08] (INNER JOIN 4개 테이블) 리뷰 상세 — 작성자·도서·카테고리
-- 설명: review-member-book-category를 연결해 평점 4점 이상 리뷰를 작성자·도서·카테고리와 함께 확인한다.
SELECT rv.review_id,
       m.name     AS reviewer,
       b.title    AS book_title,
       c.name     AS category_name,
       rv.rating,
       rv.created_at
FROM review rv
INNER JOIN member   m ON rv.member_id  = m.member_id
INNER JOIN book     b ON rv.book_id    = b.book_id
INNER JOIN category c ON b.category_id = c.category_id
WHERE rv.rating >= 4
ORDER BY rv.rating DESC, rv.created_at DESC;

-- [Q09] (LEFT JOIN) 한 번도 대여되지 않은 도서 포함 전체 도서의 대여 이력
-- 설명: book을 기준으로 LEFT JOIN 해, 대여 기록이 없는 도서도 rental 쪽이 NULL로 나오는 것을 확인한다.
SELECT b.book_id,
       b.title,
       r.rental_id,
       r.rented_at
FROM book b
LEFT JOIN rental r ON b.book_id = r.book_id
ORDER BY b.book_id, r.rented_at;


-- =====================================================================
-- 3. 집계
-- =====================================================================

-- [Q10] 회원별 대여 횟수 (대여 0회 회원 포함)
-- 설명: LEFT JOIN + COUNT + GROUP BY로 회원마다 몇 번 빌렸는지, 많이 빌린 순으로 확인한다.
SELECT m.member_id,
       m.name,
       COUNT(r.rental_id) AS rental_count       -- COUNT(컬럼)은 NULL을 세지 않으므로 대여 없으면 0
FROM member m
LEFT JOIN rental r ON m.member_id = r.member_id
GROUP BY m.member_id, m.name
ORDER BY rental_count DESC, m.member_id;

-- [Q11] 카테고리별 보유 현황 (도서 수 · 총 보유 권수 · 평균 가격)
-- 설명: COUNT, SUM, AVG + GROUP BY로 카테고리마다 도서 종류 수, 총 보유 권수, 평균 정가를 확인한다.
SELECT c.name                       AS category_name,
       COUNT(b.book_id)             AS book_count,
       COALESCE(SUM(b.total_copies), 0) AS total_copies,
       ROUND(AVG(b.price), 0)       AS avg_price
FROM category c
LEFT JOIN book b ON c.category_id = b.category_id
GROUP BY c.category_id, c.name
ORDER BY book_count DESC, c.category_id;

-- [Q12] 평균 평점 랭킹 (리뷰 2개 이상인 도서)
-- 설명: AVG + GROUP BY + HAVING으로 리뷰가 2개 이상 쌓인 도서만 평균 평점 순위를 확인한다.
SELECT b.title,
       COUNT(rv.review_id)     AS review_count,
       ROUND(AVG(rv.rating), 2) AS avg_rating
FROM review rv
INNER JOIN book b ON rv.book_id = b.book_id
GROUP BY b.book_id, b.title
HAVING COUNT(rv.review_id) >= 2
ORDER BY avg_rating DESC, review_count DESC;

-- [Q13] 월별 대여 건수 추이
-- 설명: 대여일의 'YYYY-MM' 부분으로 GROUP BY 해 월별 대여 건수와 대여된 책 정가 합계를 확인한다.
--       ※ SUBSTR는 SQLite/MySQL/PostgreSQL 공통. (SQLite 전용으로는 strftime('%Y-%m', rented_at)도 가능)
SELECT SUBSTR(r.rented_at, 1, 7) AS rental_month,
       COUNT(*)                  AS rental_count,
       SUM(b.price)              AS total_book_price
FROM rental r
INNER JOIN book b ON r.book_id = b.book_id
GROUP BY SUBSTR(r.rented_at, 1, 7)
ORDER BY rental_month;


-- =====================================================================
-- 4. 서브쿼리
-- =====================================================================

-- [Q14] 대여 기록이 없는 회원 찾기
-- 설명: NOT IN 서브쿼리로 rental 테이블에 한 번도 등장하지 않은 회원을 확인한다.
SELECT member_id, name, email, joined_at
FROM member
WHERE member_id NOT IN (SELECT member_id FROM rental)
ORDER BY member_id;

-- [Q15] 평균 정가보다 비싼 도서
-- 설명: 스칼라 서브쿼리로 전체 평균 정가를 구하고, 그보다 비싼 도서만 확인한다.
SELECT title,
       price,
       (SELECT ROUND(AVG(price), 0) FROM book) AS overall_avg_price
FROM book
WHERE price > (SELECT AVG(price) FROM book)
ORDER BY price DESC;


-- =====================================================================
-- 5. 데이터 수정 및 삭제
-- =====================================================================

-- [Q16] (UPDATE) 연체 상태로 업데이트
-- 설명: 반납 예정일이 기준일(2026-10-29)보다 지났는데 아직 반납하지 않은 대여 건을 OVERDUE로 바꾼다.
SELECT rental_id, member_id, due_date, status FROM rental WHERE status <> 'RETURNED' ORDER BY rental_id;  -- 변경 전

UPDATE rental
SET status = 'OVERDUE'
WHERE status = 'RENTED'
  AND returned_at IS NULL
  AND due_date < '2026-10-29';

SELECT rental_id, member_id, due_date, status FROM rental WHERE status <> 'RETURNED' ORDER BY rental_id;  -- 변경 후

-- [Q17] (UPDATE) 반납 처리
-- 설명: 17번 대여 건이 오늘 반납되었을 때 반납일과 상태를 함께 갱신한다.
SELECT rental_id, member_id, book_id, due_date, returned_at, status FROM rental WHERE rental_id = 17;  -- 변경 전

UPDATE rental
SET returned_at = '2026-10-29',
    status      = 'RETURNED'
WHERE rental_id = 17;

SELECT rental_id, member_id, book_id, due_date, returned_at, status FROM rental WHERE rental_id = 17;  -- 변경 후

-- [Q18] (DELETE) 리뷰 삭제
-- 설명: 작성자 요청에 따라 13번 리뷰를 삭제하고, 리뷰 건수가 15 → 14로 줄었는지 확인한다.
SELECT COUNT(*) AS review_count_before FROM review;

DELETE FROM review
WHERE review_id = 13;

SELECT COUNT(*) AS review_count_after FROM review;


-- =====================================================================
-- 6. 인덱스
-- =====================================================================

-- [Q19] (CREATE INDEX) 대여 테이블 FK 컬럼에 인덱스 추가
-- 설명: 회원별 대여 조회 성능을 위해 rental.member_id 에 인덱스를 만들고 실제로 쓰이는지 확인한다.
-- 적용 이유: rental.member_id는 JOIN과 '회원별 대여 내역' WHERE 조건에 가장 자주 쓰이는데,
--           SQLite는 FK 컬럼에 인덱스를 자동으로 만들지 않아 전체 스캔이 일어나기 때문이다.
CREATE INDEX idx_rental_member_id ON rental (member_id);

-- 적용 이유: 연체 점검(Q16)처럼 status와 due_date를 함께 조건으로 거는 조회가 반복되기 때문이다.
CREATE INDEX idx_rental_status_due ON rental (status, due_date);

-- [SQLite 전용] EXPLAIN QUERY PLAN : 쿼리가 인덱스를 사용하는지 확인 (MySQL/PostgreSQL은 EXPLAIN)
EXPLAIN QUERY PLAN
SELECT * FROM rental WHERE member_id = 1;
