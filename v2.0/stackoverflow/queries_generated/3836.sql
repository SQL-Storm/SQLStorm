-- {"query": "3836.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1814} 

WITH 
-- 1️⃣ User metrics (badge counts by class, total reputation, recent activity)
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

-- 2️⃣ Latest comment per post (correlated sub‑query wrapped in a CTE for reuse)
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

-- 3️⃣ Tag explosion for questions (to allow per‑tag analysis)
question_tags AS (
    SELECT 
        p.Id                        AS post_id,
        UNNEST(STRING_TO_ARRAY(
            TRIM(BOTH '<>' FROM COALESCE(p.Tags, '')), '><'
        ))                         AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1                -- only questions
),

-- 4️⃣ Core question payload with window ranking and duplicate links
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
        -- number of duplicate links where this question is the *target*
        (SELECT COUNT(*) 
         FROM PostLinks pl 
         WHERE pl.RelatedPostId = q.Id AND pl.LinkTypeId = 3) AS duplicate_target_cnt,
        -- number of duplicate links where this question is the *source*
        (SELECT COUNT(*) 
         FROM PostLinks pl 
         WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3)       AS duplicate_source_cnt,
        -- latest comment (may be NULL)
        lc.comment_text,
        lc.comment_date,
        -- calculate a “popularity” score mixing views, score and recent activity
        (q.ViewCount * 0.4 + q.Score * 0.6) 
        + COALESCE(EXTRACT(EPOCH FROM (NOW() - q.CreationDate))/86400,0) * -0.1 AS popularity_metric
    FROM Posts q
    LEFT JOIN usr_metrics um   ON um.user_id = q.OwnerUserId
    LEFT JOIN latest_comment lc ON lc.PostId = q.Id
    WHERE q.PostTypeId = 1               -- only questions
      AND q.CreationDate >= DATE_TRUNC('year', CURRENT_DATE) - INTERVAL '1 year'
),

-- 5️⃣ Answers related to the above questions, with a correlated sub‑query for the highest‑scoring answer per question
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
        -- –‑ correlated sub‑query: is this the top‑scoring answer for its question?
        CASE 
            WHEN a.Score = (
                SELECT MAX(a2.Score) 
                FROM Posts a2 
                WHERE a2.PostTypeId = 2 AND a2.ParentId = a.ParentId
            ) THEN 1 ELSE 0 
        END                                    AS is_top_answer_flag,
        -- latest comment on the answer (may be NULL)
        lc.comment_text                        AS latest_answer_comment,
        lc.comment_date
    FROM Posts a
    LEFT JOIN usr_metrics um                ON um.user_id = a.OwnerUserId
    LEFT JOIN latest_comment lc             ON lc.PostId = a.Id
    WHERE a.PostTypeId = 2                  -- only answers
      AND a.CreationDate >= DATE_TRUNC('year', CURRENT_DATE) - INTERVAL '1 year'
)

-- ==== FINAL COMPOSITE RESULT SET (UNION ALL) ====
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
    NULL::int                                     AS answer_id,
    NULL::int                                     AS answer_rank_per_question,
    NULL::int                                     AS is_top_answer_flag,
    NULL::text                                    AS latest_answer_comment,
    NULL::timestamp                               AS answer_creation_date
FROM question_payload qp

UNION ALL

SELECT
    'answer'                                     AS record_type,
    ap.question_id                               AS q_id,
    NULL::varchar(300)                           AS title,
    ap.Score,
    NULL::int                                    AS view_count,
    ap.CreationDate,
    ap.OwnerUserId,
    ap.answerer_reputation,
    NULL::int                                    AS owner_gold,
    NULL::int                                    AS owner_silver,
    NULL::int                                    AS owner_bronze,
    NULL::int                                    AS user_question_rank,
    NULL::int                                    AS duplicate_target_cnt,
    NULL::int                                    AS duplicate_source_cnt,
    NULL::text                                   AS latest_comment,
    NULL::timestamp                              AS comment_date,
    NULL::numeric                                AS popularity_metric,
    ap.a_id,
    ap.answer_rank_per_question,
    ap.is_top_answer_flag,
    ap.latest_answer_comment,
    ap.comment_date                               AS answer_creation_date
FROM answer_payload ap
ORDER BY
    record_type,
    CASE WHEN record_type='question' THEN qp.popularity_metric END DESC,
    CASE WHEN record_type='answer'   THEN ap.Score END DESC;
