WITH
    recent_questions AS (
        SELECT
            p.Id                                     AS q_id,
            p.OwnerUserId                            AS q_owner,
            p.CreationDate                           AS q_created,
            p.Score                                  AS q_score,
            p.Title                                  AS q_title,
            p.Tags                                   AS q_tags,
            p.ViewCount                              AS q_views,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_q
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    answer_agg AS (
        SELECT
            a.ParentId                               AS q_id,
            COUNT(*)                                 AS ans_cnt,
            AVG(a.Score)                             AS ans_avg_score,
            MAX(a.CreationDate)                      AS ans_last_date
        FROM Posts a
        WHERE a.PostTypeId = 2
        GROUP BY a.ParentId
    ),
    badge_summary AS (
        SELECT
            b.UserId                                 AS user_id,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt,
            COUNT(*)                                 AS total_cnt
        FROM Badges b
        GROUP BY b.UserId
    ),
    vote_summary AS (
        SELECT
            v.PostId                                 AS post_id,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_cnt,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_cnt,
            MAX(v.CreationDate)                      AS last_vote
        FROM Votes v
        GROUP BY v.PostId
    ),
    tag_details AS (
        SELECT
            t.TagName,
            t.Count                                   AS tag_use_cnt,
            p.Id                                      AS excerpt_post_id,
            p.Title                                   AS excerpt_title,
            ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.CreationDate DESC) AS rn_tag
        FROM Tags t
        LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    ),
    -- explode tags per question and aggregate per user+question using standard grouping (no STRING_AGG as window)
    question_tags AS (
        SELECT
            u.Id                                      AS user_id,
            q.q_id,
            q.q_title,
            q.q_tags,
            q.q_score,
            q.q_views,
            TRIM(BOTH '<>' FROM q.q_tags)             AS trimmed_tags,
            -- split tags into rows: use dialect-agnostic method via replacing >< with delimiter; assume available functions are similar
            -- For portability, use regexp_split_to_table for Postgres; otherwise replace with appropriate split function.
            -- Here use regexp_split_to_table as standard-ish; if not available, user can adapt.
            regexp_split_to_table(TRIM(BOTH '<>' FROM q.q_tags), '><') AS tag_name
        FROM Users u
        LEFT JOIN recent_questions q
            ON q.q_owner = u.Id AND q.rn_q <= 5
        WHERE q.q_id IS NOT NULL
    ),
    user_question_tag_aggs AS (
        SELECT
            user_id,
            q_id,
            q_title,
            q_tags,
            q_score,
            q_views,
            STRING_AGG(tag_name, ', ') AS user_tags -- aggregate per group, not as window
        FROM question_tags
        GROUP BY user_id, q_id, q_title, q_tags, q_score, q_views
    )

SELECT
    u.Id                                            AS user_id,
    COALESCE(u.DisplayName, 'Anonymous')            AS display_name,
    u.Reputation,
    q.q_id,
    q.q_title,
    LEFT(q.q_tags, 120)                             AS tags_snippet,
    q.q_score,
    COALESCE(a.ans_cnt, 0)                          AS answer_count,
    ROUND(COALESCE(a.ans_avg_score, 0), 2)          AS avg_answer_score,
    a.ans_last_date,
    bs.gold_cnt,
    bs.silver_cnt,
    bs.bronze_cnt,
    vs.up_cnt,
    vs.down_cnt,
    vs.last_vote,
    CASE
        WHEN q.q_score + COALESCE(vs.up_cnt,0) - COALESCE(vs.down_cnt,0) > 150 THEN 'Hot'
        WHEN q.q_views > 2000                                                    THEN 'Popular'
        ELSE 'Normal'
    END                                            AS popularity_tier,
    uqa.user_tags
FROM Users u
LEFT JOIN recent_questions q
       ON q.q_owner = u.Id AND q.rn_q <= 5
LEFT JOIN answer_agg a
       ON a.q_id = q.q_id
LEFT JOIN badge_summary bs
       ON bs.user_id = u.Id
LEFT JOIN vote_summary vs
       ON vs.post_id = q.q_id
LEFT JOIN user_question_tag_aggs uqa
       ON uqa.user_id = u.Id AND uqa.q_id = q.q_id
WHERE u.CreationDate < CAST('2024-10-01' AS DATE) - INTERVAL '1 year'

UNION ALL

SELECT
    u2.Id,
    COALESCE(u2.DisplayName, 'Anonymous'),
    u2.Reputation,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL,
    'Inactive',
    NULL
FROM Users u2
WHERE NOT EXISTS (
        SELECT 1 FROM Posts p
        WHERE p.OwnerUserId = u2.Id
          AND p.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '6 months'
      )
  AND u2.Reputation < 100
ORDER BY Reputation DESC, q_score DESC NULLS LAST
LIMIT 100;