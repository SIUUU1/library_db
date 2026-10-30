-- =====================================================================
-- 01_schema.sql : 도서 대여 서비스 스키마 생성 스크립트
-- DB   : SQLite 3 (표준 SQL 위주로 작성, DB 전용 문법은 주석으로 표시)
-- 실행 : sqlite3 library.db < 01_schema.sql
--
-- 테이블 구성 (5개)
--   category  : 도서 카테고리
--   member    : 회원
--   book      : 도서            (category 1 : N book)
--   rental    : 대여 기록        (member 1 : N rental, book 1 : N rental)
--   review    : 도서 리뷰        (member 1 : N review, book 1 : N review)
-- =====================================================================

-- [SQLite 전용] SQLite는 FK 검사가 기본으로 꺼져 있다.
-- 접속(커넥션)마다 켜야 FK가 실제로 동작한다. (MySQL/PostgreSQL은 불필요)
PRAGMA foreign_keys = ON;

-- 재실행할 수 있도록 자식 테이블부터 삭제
DROP TABLE IF EXISTS review;
DROP TABLE IF EXISTS rental;
DROP TABLE IF EXISTS book;
DROP TABLE IF EXISTS member;
DROP TABLE IF EXISTS category;

-- ---------------------------------------------------------------------
-- 1) category : 도서 카테고리 (부모 테이블)
-- ---------------------------------------------------------------------
CREATE TABLE category (
    category_id   INTEGER      PRIMARY KEY,          -- [SQLite] INTEGER PRIMARY KEY는 자동 증가(rowid)
    name          VARCHAR(50)  NOT NULL UNIQUE,      -- 같은 이름의 카테고리 중복 금지
    description   VARCHAR(200)
);

-- ---------------------------------------------------------------------
-- 2) member : 회원 (부모 테이블)
-- ---------------------------------------------------------------------
CREATE TABLE member (
    member_id     INTEGER      PRIMARY KEY,
    name          VARCHAR(50)  NOT NULL,
    email         VARCHAR(100) NOT NULL UNIQUE,      -- 로그인 ID 역할 → 중복 금지
    phone         VARCHAR(20),
    joined_at     DATE         NOT NULL,
    status        VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE'
                  CHECK (status IN ('ACTIVE', 'SUSPENDED'))
);

-- ---------------------------------------------------------------------
-- 3) book : 도서  (category 1 : N book)
-- ---------------------------------------------------------------------
CREATE TABLE book (
    book_id         INTEGER      PRIMARY KEY,
    category_id     INTEGER      NOT NULL,
    title           VARCHAR(200) NOT NULL,
    author          VARCHAR(100) NOT NULL,
    publisher       VARCHAR(100),
    isbn            VARCHAR(20)  NOT NULL UNIQUE,    -- 도서 고유 번호
    published_year  INTEGER,
    price           INTEGER      NOT NULL CHECK (price >= 0),
    total_copies    INTEGER      NOT NULL DEFAULT 1 CHECK (total_copies >= 0),
    FOREIGN KEY (category_id) REFERENCES category (category_id)
);

-- ---------------------------------------------------------------------
-- 4) rental : 대여 기록  (member 1 : N rental, book 1 : N rental)
--    status : RENTED(대여 중) / RETURNED(반납 완료) / OVERDUE(연체)
-- ---------------------------------------------------------------------
CREATE TABLE rental (
    rental_id     INTEGER      PRIMARY KEY,
    member_id     INTEGER      NOT NULL,
    book_id       INTEGER      NOT NULL,
    rented_at     DATE         NOT NULL,
    due_date      DATE         NOT NULL,
    returned_at   DATE,                                -- 미반납이면 NULL
    status        VARCHAR(20)  NOT NULL DEFAULT 'RENTED'
                  CHECK (status IN ('RENTED', 'RETURNED', 'OVERDUE')),
    CHECK (due_date >= rented_at),
    FOREIGN KEY (member_id) REFERENCES member (member_id),
    FOREIGN KEY (book_id)   REFERENCES book (book_id)
);

-- ---------------------------------------------------------------------
-- 5) review : 도서 리뷰  (member 1 : N review, book 1 : N review)
-- ---------------------------------------------------------------------
CREATE TABLE review (
    review_id     INTEGER      PRIMARY KEY,
    member_id     INTEGER      NOT NULL,
    book_id       INTEGER      NOT NULL,
    rating        INTEGER      NOT NULL CHECK (rating BETWEEN 1 AND 5),
    content       VARCHAR(500),
    created_at    DATE         NOT NULL,
    UNIQUE (member_id, book_id),                       -- 한 회원은 같은 책에 리뷰 1개만
    FOREIGN KEY (member_id) REFERENCES member (member_id),
    FOREIGN KEY (book_id)   REFERENCES book (book_id)
);
