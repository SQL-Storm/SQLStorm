-- {"query": "3279.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2282}
WITH
    user_post_agg AS (
        SELECT
            u.Id                                     AS user_id,
            u.DisplayName,
            u.Reputation,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_cnt,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_cnt,
            COALESCE(SUM(p.Score), 0)                 AS total_score,
            MAX(p.CreationDate)                      AS last_post_dt
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    badge_agg2 AS (
        SELECT
            b.UserId                                 AS user_id,
            COUNT(*)                                 AS badge_cnt,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt
        FROM Badges b
        GROUP BY b.UserId
    ),

    badge_gold_names AS (
        SELECT
            b.UserId AS user_id,
            STRING_AGG(DISTINCT b.Name, ', ') AS gold_names
        FROM Badges b
        WHERE b.Class = 1
        GROUP BY b.UserId
    ),

    edit_agg AS (
        SELECT
            ph.UserId                                 AS user_id,
            MAX(ph.CreationDate)                      AS last_edit_dt,
            COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS edit_cnt
        FROM PostHistory ph
        GROUP BY ph.UserId
    ),

    vote_agg AS (
        SELECT
            vt.UserId                                 AS user_id,
            COUNT(CASE WHEN vt.VoteTypeId = 2 THEN 1 END) AS upvotes_given,
            COUNT(CASE WHEN vt.VoteTypeId = 3 THEN 1 END) AS downvotes_given
        FROM Votes vt
        GROUP BY vt.UserId
    ),

    post_tags AS (
        SELECT
            p.OwnerUserId                            AS user_id,
            TRIM(tag) AS tag
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT UNNEST(STRING_TO_ARRAY(SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS tag
        ) s
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    ),

    tag_counts AS (
        SELECT
            user_id,
            tag,
            cnt,
            ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY cnt DESC, tag) AS rn
        FROM (
            SELECT
                user_id,
                tag,
                COUNT(*) AS cnt
            FROM post_tags
            GROUP BY user_id, tag
        ) t
    ),

    top_tags AS (
        SELECT
            user_id,
            STRING_AGG(tag, ', ' ORDER BY cnt DESC, tag) AS top_3_tags
        FROM tag_counts
        WHERE rn <= 3
        GROUP BY user_id
    )

SELECT
    upa.user_id,
    upa.DisplayName,
    upa.Reputation,
    upa.question_cnt,
    upa.answer_cnt,
    upa.total_score,
    COALESCE(bag.badge_cnt, 0)          AS badge_cnt,
    COALESCE(bag.gold_cnt, 0)           AS gold_cnt,
    COALESCE(bag.silver_cnt, 0)         AS silver_cnt,
    COALESCE(bag.bronze_cnt, 0)         AS bronze_cnt,
    gnames.gold_names,
    COALESCE(ed.last_edit_dt, TIMESTAMP '1970-01-01') AS last_edit_dt,
    COALESCE(ed.edit_cnt, 0)            AS edit_cnt,
    COALESCE(vot.upvotes_given, 0)      AS upvotes_given,
    COALESCE(vot.downvotes_given, 0)    AS downvotes_given,
    upa.last_post_dt,
    tt.top_3_tags
FROM user_post_agg upa
LEFT JOIN badge_agg2 bag   ON bag.user_id = upa.user_id
LEFT JOIN badge_gold_names gnames ON gnames.user_id = upa.user_id
LEFT JOIN edit_agg ed     ON ed.user_id = upa.user_id
LEFT JOIN vote_agg vot    ON vot.user_id = upa.user_id
LEFT JOIN top_tags tt     ON tt.user_id = upa.user_id
WHERE
    (upa.Reputation > 1000 OR COALESCE(bag.gold_cnt, 0) > 0)
    AND (upa.total_score IS NULL OR upa.total_score >= 0)
ORDER BY upa.Reputation DESC
LIMIT 100;