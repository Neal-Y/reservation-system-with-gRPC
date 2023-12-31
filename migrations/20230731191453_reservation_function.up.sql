-- 這是一個使用者查詢的function
-- if resource_id is null, find all reservations within during for the user
-- if both are null, find all reservations within during
-- if both set, find all reservations within during for the resource and user

-- note:
-- 所以這個rsvp.query函數中我定義了引數列表:
--     uid text,
--     rid text,
--     during TSTZRANGE,
--     status rsvp.reservation_status,
--     page integer DEFAULT 1,
--     is_desc bool DEFAULT FALSE,
--     page_size integer DEFAULT 10
-- 他將會回傳一個rsvp.reservations table 並且從$$  到  $$，中間都是我該如何處理這段函數的邏輯。
-- DECLARE: 顧名思義，宣告等等BEGIN END裡面會用到的變數(_只是一個表示私有的意思，只是習慣)
-- 接著BEGIN END這個區塊就是表示主要的邏輯，我會先做一些判斷，例如page_size如果小於10或是大於100，我就將他設定為10，page如果小於1，我就將他設定為1，判斷進來的參數是合理的。
-- 動態查詢的部分，在查詢語句中由於我使用"format"以及有其他條件想要做篩選所以使用%S(String)%L(Literal)去佔位
-- 後面的參數和CASE END中去替換，最後將結果放在_sql並且透過RETURN QUERY EXECUTE _sql來回傳查詢的結果。
-- 補充：CASE END主要是將一些判斷式寫在SQL中。
-- 例如我想要判斷uid和rid是否為null，如果都是null，我就回傳TRUE，如果只有uid是null，我就回傳resource_id = ' || quote_literal(rid)
-- 如果只有rid是null，我就回傳user_id = ' || quote_literal(uid)，如果都不是null，我就回傳user_id = ' || quote_literal(uid) || ' AND resource_id = ' || quote_literal(rid)。


-- 中間有個highlight使用||並且使用quote_literal()可以將字串加上單引號轉成字面量常量(literal)，這是為了避免SQL Injection的問題。

CREATE OR REPLACE FUNCTION rsvp.query(
    uid text,
    rid text,
    _start timestamp with time zone,
    _end timestamp with time zone,
    status rsvp.reservation_status DEFAULT 'pending',
    is_desc bool DEFAULT FALSE
) RETURNS TABLE (LIKE rsvp.reservations) AS $$
DECLARE
    _during tstzrange;
    _sql text;
BEGIN
    _during := tstzrange(
        COALESCE(_start, '-infinity'),
        COALESCE(_end, 'infinity'),
        '[)'
    );

    -- if page_size is not between 10 and 100, set it to 10
    -- IF page_size < 10 OR page_size > 100 THEN
    --     page_size := 10;
    -- END IF;
    -- -- if page is less than 1, set it to 1
    -- IF page < 1 THEN
    --     page := 1;
    -- END IF;

    -- format the query based on parameters
    _sql := format(
        'SELECT * FROM rsvp.reservations WHERE %L @> timespan AND status = %L AND %s ORDER BY lower(timespan) %s',
        _during,
        status,
        CASE
            WHEN uid IS NULL AND rid IS NULL THEN 'TRUE'
            WHEN uid IS NULL THEN 'resource_id = ' || quote_literal(rid)
            WHEN rid IS NULL THEN 'user_id = ' || quote_literal(uid)
            ELSE 'user_id = ' || quote_literal(uid) || ' AND resource_id = ' || quote_literal(rid)
        END,
        CASE
            WHEN is_desc THEN 'DESC'
            ELSE 'ASC'
        END
        -- if page_size is default 10, I want to check the page 3, it will be (3 - 1) * 10 = 20,
        -- in the other words, database will offset the first 20 items.
        -- page_size,
        -- (page - 1) * page_size
    );

    -- log the sql
    RAISE NOTICE '%', _sql;

    -- execute the query
    RETURN QUERY EXECUTE _sql;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION rsvp.filter(
    uid text,
    rid text,
    status rsvp.reservation_status,
    cursor bigint DEFAULT null,
    is_desc bool DEFAULT FALSE,
    page_size bigint DEFAULT 10
) RETURNS TABLE (LIKE rsvp.reservations) AS $$
DECLARE
    _sql text;
BEGIN
    -- if the cursor is null, set it to 0, if is_desc is false, or to 2^64 - 1 if is_desc is true
    -- initialize the cursor
    IF cursor IS NULL OR cursor < 0 THEN
        IF is_desc THEN
            cursor := 9223372036854775807;
        ELSE
            cursor := 0;
        END IF;
    END IF;

    -- if page_size is not between 10 and 100, set it to 10
    IF page_size < 10 OR page_size > 100 THEN
        page_size := 10;
    END IF;

    -- format the query based on parameters
    _sql := format(
        'SELECT * FROM rsvp.reservations WHERE %s AND status = %L AND %s ORDER BY id %s LIMIT %L::integer',
        -- 確保當降序排列時如果id<=cursor代表還有下一頁就是有其他比他小的id沒有的話就塞false給sql語句讓其失敗，而升序則反之
        CASE
            WHEN is_desc THEN 'id <= ' || cursor
            ELSE 'id >= ' || cursor
        END,
        status,
        CASE
            WHEN uid IS NULL AND rid IS NULL THEN 'TRUE'
            WHEN uid IS NULL THEN 'resource_id = ' || quote_literal(rid)
            WHEN rid IS NULL THEN 'user_id = ' || quote_literal(uid)
            ELSE 'user_id = ' || quote_literal(uid) || ' AND resource_id = ' || quote_literal(rid)
        END,
        CASE
            WHEN is_desc THEN 'DESC'
            ELSE 'ASC'
        END,
        -- if page_size is default 10, I want to check the page 3, it will be (3 - 1) * 10 = 20,
        -- in the other words, database will offset the first 20 items.
        page_size + 1
    );

    -- log the sql
    RAISE NOTICE '%', _sql;

    -- execute the query
    RETURN QUERY EXECUTE _sql;
END;
$$ LANGUAGE plpgsql;
