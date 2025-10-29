-- {"query": "3153.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2925} 

/*  Benchmark‑heavy query using CTEs, window functions, outer joins,
    correlated subqueries, set operators and extensive NULL logic  */
WITH
    /* Top‑scoring question per user plus tag explode */
    user_questions AS (
        SELECT
            p.Id                         AS q_id,
            p.Title,
            p.CreationDate,
            p.Score,
            p.ViewCount,
            p.OwnerUserId,
            COALESCE(u.DisplayName,'Anonymous') AS owner_name,
            regexp_split_to_table(p.Tags,'><')  AS tag,
            ROW_NUMBER() OVER (
                PARTITION BY p.OwnerUserId
                ORDER BY p.Score DESC, p.CreationDate DESC
            ) AS rn_user_top
        FROM Posts p
        LEFT JOIN Users u ON u.Id = p.OwnerUserId
        WHERE p.PostTypeId = 1                         -- only questions
    ),

    /* Aggregated tag statistics */
    tag_stats AS (
        SELECT
            t.TagName,
            COUNT(*) FILTER (WHERE q.Score > 0)      AS pos_score_cnt,
            COUNT(*) FILTER (WHERE q.Score <= 0)     AS nonpos_score_cnt,
            ROUND(AVG(q.Score)::numeric,2)           AS avg_score,
            SUM(q.ViewCount)                         AS total_views
        FROM Tags t
        LEFT JOIN LATERAL (
            SELECT *
            FROM user_questions q
            WHERE q.tag = t.TagName
        ) q ON TRUE
        GROUP BY t.TagName
    ),

    /* Badge per user summary */
    user_badges AS (
        SELECT
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1)      AS gold_cnt,
            COUNT(*) FILTER (WHERE b.Class = 2)      AS silver_cnt,
            COUNT(*) FILTER (WHERE b.Class = 3)      AS bronze_cnt,
            MAX(b.Date)                              AS last_badge_date
        FROM Badges b
        GROUP BY b.UserId
    ),

    /* Recent vote aggregates (last 30 days) */
    recent_votes AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS up_votes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS down_votes,
            MAX(v.CreationDate)                        AS last_vote_dt
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
        GROUP BY v.PostId
    ),

    /* Answer statistics per question */
    answer_stats AS (
        SELECT
            p.ParentId                                   AS q_id,
            COUNT(*)                                     AS answer_cnt,
            MAX(p.Score)                                 AS max_answer_score,
            MIN(p.CreationDate)                          AS first_answer_dt,
            MAX(p.CreationDate)                          AS last_answer_dt
        FROM Posts p
        WHERE p.PostTypeId = 2                           -- answers
        GROUP BY p.ParentId
    ),

    /* Closed‑question timeline */
    closed_q AS (
        SELECT
            ph.PostId,
            MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS closed_dt,
            MIN(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS reopened_dt,
            MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END)      AS close_reason_id
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (10,11)            -- closed / reopened
        GROUP BY ph.PostId
    )

SELECT
    uq.q_id,
    uq.Title,
    uq.owner_name,
    uq.Score,
    uq.ViewCount,
    ts.TagName,
    ts.avg_score,
    ts.total_views,
    ub.gold_cnt,
    ub.silver_cnt,
    ub.bronze_cnt,
    rv.up_votes,
    rv.down_votes,
    asw.answer_cnt,
    asw.max_answer_score,
    CASE
        WHEN cq.closed_dt IS NOT NULL
         AND (cq.reopened_dt IS NULL OR cq.reopened_dt < cq.closed_dt) THEN 'Closed'
        ELSE 'Open'
    END                                           AS status,
    COALESCE(crt.Name,'Unknown')                 AS close_reason
FROM user_questions uq
LEFT JOIN tag_stats ts      ON ts.TagName = uq.tag
LEFT JOIN user_badges ub    ON ub.UserId = uq.OwnerUserId
LEFT JOIN recent_votes rv  ON rv.PostId = uq.q_id
LEFT JOIN answer_stats asw ON asw.q_id = uq.q_id
LEFT JOIN closed_q cq      ON cq.PostId = uq.q_id
LEFT JOIN CloseReasonTypes crt
       ON crt.Id = CASE
                     WHEN cq.close_reason_id IS NOT NULL
                     THEN cq.close_reason_id::int
                     ELSE NULL
                  END
WHERE uq.rn_user_top = 1
  AND (uq.Score > 0 OR uq.ViewCount > 1000)
  AND (ub.gold_cnt > 0 OR rv.up_votes > 5)
ORDER BY uq.Score DESC, uq.ViewCount DESC
LIMIT 100

UNION ALL

/*  Recent “orphan” questions (no answers) for stress‑testing INSERT‑heavy paths  */
SELECT
    p.Id,
    p.Title,
    COALESCE(u.DisplayName,'Deleted') AS owner_name,
    p.Score,
    p.ViewCount,
    NULL                               AS TagName,
    NULL                               AS avg_score,
    NULL                               AS total_views,
    0                                  AS gold_cnt,
    0                                  AS silver_cnt,
    0                                  AS bronze_cnt,
    0                                  AS up_votes,
    0                                  AS down_votes,
    0                                  AS answer_cnt,
    0                                  AS max_answer_score,
    'Orphan'                           AS status,
    NULL                               AS close_reason
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
  AND NOT EXISTS (SELECT 1 FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2)
  AND p.CreationDate >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY p.Score DESC
LIMIT 50;
