-- {"query": "3935.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1873} 

/*  Benchmark query:  a mix of CTEs, window functions, outer joins,
    correlated subqueries, set operators, complex predicates,
    string manipulation and NULL logic.                                      */

WITH
/* 1. Recent activity (last 90 days) per user */
recent_votes AS (
    SELECT
        v.UserId,
        COUNT(*)                                   AS vote_cnt,
        SUM(CASE WHEN vt.Name = 'UpMod'      THEN 1
                 WHEN vt.Name = 'DownMod'    THEN -1
                 ELSE 0 END)                      AS vote_score,
        MAX(v.CreationDate)                        AS last_vote_dt
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY v.UserId
),

/* 2. Badge aggregates per user */
user_badges AS (
    SELECT
        b.UserId,
        COUNT(*)                                   AS total_badges,
        COUNT(*) FILTER (WHERE b.Class = 1)        AS gold,
        COUNT(*) FILTER (WHERE b.Class = 2)        AS silver,
        COUNT(*) FILTER (WHERE b.Class = 3)        AS bronze,
        BOOL_OR(b.TagBased)                        AS any_tag_based
    FROM Badges b
    GROUP BY b.UserId
),

/* 3. Tag popularity – split Tags string, explode, count usage in last 30 days */
tag_usage AS (
    SELECT
        TRIM(BOTH '><' FROM UNNEST(string_to_array(p.Tags, '><'))) AS tag,
        COUNT(*)                                                   AS usage_cnt
    FROM Posts p
    WHERE p.PostTypeId = 1               -- only questions
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
      AND p.Tags IS NOT NULL
    GROUP BY tag
),

/* 4. Top 10 tags by usage (window function) */
top_tags AS (
    SELECT
        tag,
        usage_cnt,
        ROW_NUMBER() OVER (ORDER BY usage_cnt DESC) AS rn
    FROM tag_usage
    WHERE tag <> ''                     -- guard against empty strings
    ORDER BY usage_cnt DESC
    LIMIT 10
),

/* 5. Average score of a user's answers (correlated subquery later) */
user_answer_stats AS (
    SELECT
        u.Id                            AS user_id,
        COALESCE(AVG(p.Score),0)        AS avg_answer_score,
        COUNT(p.Id)                     AS answer_cnt
    FROM Users u
    LEFT JOIN Posts p
      ON p.OwnerUserId = u.Id
     AND p.PostTypeId = 2               -- answers only
    GROUP BY u.Id
),

/* 6. Recent questions with possible duplicate links (self‑join via PostLinks) */
recent_questions AS (
    SELECT
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.FavoriteCount,
        COALESCE(NULLIF(q.Tags, ''), '<no tags>')          AS raw_tags,
        /* Extract first tag for quick look‑up */
        CASE WHEN q.Tags IS NOT NULL
             THEN split_part(substring(q.Tags FROM 2 FOR char_length(q.Tags)-2), '><', 1)
             ELSE NULL END                                 AS primary_tag,
        /* Detect if question has a duplicate link */
        EXISTS (
            SELECT 1
            FROM PostLinks pl
            WHERE pl.PostId = q.Id
              AND pl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate')
        )                                                  AS is_duplicate
    FROM Posts q
    WHERE q.PostTypeId = 1                 -- only questions
      AND q.CreationDate >= CURRENT_DATE - INTERVAL '60 days'
),

/* 7. Union of two result sets: questions with high score and answers with high vote score */
high_quality AS (
    /* Part A – high‑scoring recent questions */
    SELECT
        rq.Id                     AS post_id,
        rq.Title,
        rq.CreationDate,
        rq.Score                  AS post_score,
        rq.ViewCount,
        rq.FavoriteCount,
        'question'                AS post_type,
        NULL::int                 AS parent_id,
        rq.primary_tag,
        rq.is_duplicate
    FROM recent_questions rq
    WHERE rq.Score >= 20
      AND rq.ViewCount > 500

    UNION ALL

    /* Part B – answers whose owners have strong reputation and recent up‑votes */
    SELECT
        a.Id                     AS post_id,
        COALESCE(p.Title,'<orphan answer>') AS Title,
        a.CreationDate,
        a.Score                  AS post_score,
        NULL::int                AS ViewCount,
        NULL::int                AS FavoriteCount,
        'answer'                  AS post_type,
        a.ParentId               AS parent_id,
        NULL                     AS primary_tag,
        FALSE                    AS is_duplicate
    FROM Posts a
    JOIN Posts p ON p.Id = a.ParentId AND p.PostTypeId = 1
    JOIN Users u ON u.Id = a.OwnerUserId
    WHERE a.PostTypeId = 2
      AND a.Score >= 10
      AND u.Reputation > 5000
      AND EXISTS (
          SELECT 1
          FROM recent_votes rv
          WHERE rv.UserId = u.Id
            AND rv.vote_score > 0
      )
)

SELECT
    h.post_id,
    h.Title,
    h.CreationDate,
    h.post_score,
    h.ViewCount,
    h.FavoriteCount,
    h.post_type,
    h.parent_id,
    COALESCE(h.primary_tag, t.tag)                               AS tag_or_top_tag,
    h.is_duplicate,
    u.DisplayName,
    u.Reputation,
    ub.total_badges,
    ub.gold,
    ub.silver,
    ub.bronze,
    ub.any_tag_based,
    rv.vote_cnt,
    rv.vote_score,
    rv.last_vote_dt,
    uas.avg_answer_score,
    uas.answer_cnt,
    ROW_NUMBER() OVER (PARTITION BY h.post_type ORDER BY h.post_score DESC)   AS rank_in_type,
    /* Complex expression: weighted activity score */
    (COALESCE(h.post_score,0) * 1.5
     + COALESCE(rv.vote_score,0) * 1.2
     + COALESCE(ub.gold,0) * 5
     + COALESCE(ub.silver,0) * 3
     + COALESCE(ub.bronze,0) * 1
     + COALESCE(uas.avg_answer_score,0) * 0.8)                AS weighted_activity
FROM high_quality h
LEFT JOIN Users u                 ON u.Id = CASE WHEN h.post_type = 'question' THEN
                                                (SELECT OwnerUserId FROM Posts WHERE Id = h.post_id)
                                              ELSE
                                                (SELECT OwnerUserId FROM Posts WHERE Id = h.post_id)
                                              END
LEFT JOIN user_badges ub         AS ub ON ub.UserId = u.Id
LEFT JOIN recent_votes rv        ON rv.UserId = u.Id
LEFT JOIN user_answer_stats uas  ON uas.user_id = u.Id
LEFT JOIN top_tags t              ON t.rn = 1 AND h.primary_tag = t.tag
WHERE u.Id IS NOT NULL                           -- filter out deleted users
  AND (h.is_duplicate = FALSE OR h.post_type = 'answer')
ORDER BY weighted_activity DESC
LIMIT 100;
