WITH 
usr_metrics AS (
    SELECT 
        u.Id                     AS user_id,
        u.Reputation,
        COALESCE(SUM(CASE b.Class WHEN 1 THEN 1 ELSE 0 END),0) AS gold_badges,
        COALESCE(SUM(CASE b.Class WHEN 2 THEN 1 ELSE 0 END),0) AS silver_badges,
        COALESCE(SUM(CASE b.Class WHEN 3 THEN 1 ELSE 0 END),0) AS bronze_badges,
        MAX(u.LastAccessDate)   AS last_access,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS upvote_given,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS downvote_given
    FROM Users u
    LEFT JOIN Badges b      ON b.UserId = u.Id
    LEFT JOIN Votes  v      ON v.UserId = u.Id
    GROUP BY u.Id, u.Reputation
),

latest_comment AS (
    SELECT 
        c.PostId,
        c.Text AS comment_text,
        c.CreationDate AS comment_date
    FROM Comments c
    WHERE c.CreationDate = (
        SELECT MAX(c2.CreationDate)
        FROM Comments c2
        WHERE c2.PostId = c.PostId
    )
),

question_tags AS (
    SELECT 
        p.Id                        AS post_id,
        UNNEST(STRING_TO_ARRAY(
            TRIM(BOTH '<>' FROM COALESCE(p.Tags, '')), '><'
        ))                         AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),

question_payload AS (
    SELECT
        q.Id                                      AS q_id,
        q.Title,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.OwnerUserId,
        COALESCE(um.reputation,0)                 AS owner_reputation,
        COALESCE(um.gold_badges,0)                AS owner_gold,
        COALESCE(um.silver_badges,0)              AS owner_silver,
        COALESCE(um.bronze_badges,0)              AS owner_bronze,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId
                           ORDER BY q.Score DESC, q.CreationDate DESC) AS user_question_rank,
        (SELECT COUNT(*) 
         FROM PostLinks pl 
         WHERE pl.RelatedPostId = q.Id AND pl.LinkTypeId = 3) AS duplicate_target_cnt,
        (SELECT COUNT(*) 
         FROM PostLinks pl 
         WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3)       AS duplicate_source_cnt,
        lc.comment_text,
        lc.comment_date,
        (q.ViewCount * 0.4 + q.Score * 0.6) 
        + COALESCE(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - q.CreationDate))/86400,0) * -0.1 AS popularity_metric
    FROM Posts q
    LEFT JOIN usr_metrics um   ON um.user_id = q.OwnerUserId
    LEFT JOIN latest_comment lc ON lc.PostId = q.Id
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= DATE_TRUNC('year', CAST('2024-10-01' AS DATE)) - INTERVAL '1 year'
),

answer_payload AS (
    SELECT
        a.Id                                   AS a_id,
        a.ParentId                             AS question_id,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        COALESCE(um.reputation,0)              AS answerer_reputation,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId
                           ORDER BY a.Score DESC, a.CreationDate ASC) AS answer_rank_per_question,
        CASE 
            WHEN a.Score = (
                SELECT MAX(a2.Score) 
                FROM Posts a2 
                WHERE a2.PostTypeId = 2 AND a2.ParentId = a.ParentId
            ) THEN 1 ELSE 0 
        END                                    AS is_top_answer_flag,
        lc.comment_text                        AS latest_answer_comment,
        lc.comment_date
    FROM Posts a
    LEFT JOIN usr_metrics um                ON um.user_id = a.OwnerUserId
    LEFT JOIN latest_comment lc             ON lc.PostId = a.Id
    WHERE a.PostTypeId = 2
      AND a.CreationDate >= DATE_TRUNC('year', CAST('2024-10-01' AS DATE)) - INTERVAL '1 year'
),

combined AS (
SELECT
    'question'                                   AS record_type,
    qp.q_id,
    qp.Title                                      AS title,
    qp.Score,
    qp.ViewCount,
    qp.CreationDate,
    qp.OwnerUserId,
    qp.owner_reputation,
    qp.owner_gold,
    qp.owner_silver,
    qp.owner_bronze,
    qp.user_question_rank,
    qp.duplicate_target_cnt,
    qp.duplicate_source_cnt,
    qp.comment_text                               AS latest_comment,
    qp.comment_date,
    qp.popularity_metric,
    CAST(NULL AS INTEGER)                         AS answer_id,
    CAST(NULL AS INTEGER)                         AS answer_rank_per_question,
    CAST(NULL AS INTEGER)                         AS is_top_answer_flag,
    CAST(NULL AS TEXT)                            AS latest_answer_comment,
    CAST(NULL AS TIMESTAMP)                       AS answer_creation_date
FROM question_payload qp

UNION ALL

SELECT
    'answer'                                     AS record_type,
    ap.question_id                               AS q_id,
    CAST(NULL AS VARCHAR(300))                   AS title,
    ap.Score,
    CAST(NULL AS INTEGER)                        AS view_count,
    ap.CreationDate,
    ap.OwnerUserId,
    ap.answerer_reputation,
    CAST(NULL AS INTEGER)                        AS owner_gold,
    CAST(NULL AS INTEGER)                        AS owner_silver,
    CAST(NULL AS INTEGER)                        AS owner_bronze,
    CAST(NULL AS INTEGER)                        AS user_question_rank,
    CAST(NULL AS INTEGER)                        AS duplicate_target_cnt,
    CAST(NULL AS INTEGER)                        AS duplicate_source_cnt,
    CAST(NULL AS TEXT)                           AS latest_comment,
    CAST(NULL AS TIMESTAMP)                      AS comment_date,
    CAST(NULL AS NUMERIC)                        AS popularity_metric,
    ap.a_id,
    ap.answer_rank_per_question,
    ap.is_top_answer_flag,
    ap.latest_answer_comment,
    ap.comment_date                               AS answer_creation_date
FROM answer_payload ap
)

SELECT *
FROM combined
ORDER BY
    record_type,
    CASE WHEN record_type='question' THEN popularity_metric END DESC,
    CASE WHEN record_type='answer'   THEN Score END DESC;