-- {"query": "3633.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2555} 

WITH
    -- Expand each question into one row per tag
    question_tags AS (
        SELECT
            p.Id                AS question_id,
            p.Title,
            p.ViewCount         AS views,
            p.Score             AS q_score,
            p.CreationDate,
            regexp_split_to_table(
                trim(both '<>' FROM p.Tags),
                '><'
            )                   AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),

    -- Aggregate answer statistics per question
    answer_stats AS (
        SELECT
            a.ParentId                          AS question_id,
            COUNT(*)                            AS answer_cnt,
            MAX(a.Score)                        AS max_ans_score,
            AVG(a.Score)                        AS avg_ans_score,
            SUM(CASE WHEN a.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END) AS answered_by_users
        FROM Posts a
        WHERE a.PostTypeId = 2
        GROUP BY a.ParentId
    ),

    -- Compute per‑user activity summary
    user_activity AS (
        SELECT
            u.Id                                 AS user_id,
            u.Reputation,
            u.CreationDate,
            COALESCE(SUM(
                CASE v.VoteTypeId
                    WHEN 2 THEN  1   -- upvote
                    WHEN 3 THEN -1   -- downvote
                    ELSE 0
                END
            ), 0)                                AS vote_score_sum,
            COUNT(DISTINCT b.Id)                 AS badge_cnt,
            MAX(p.LastActivityDate)              AS last_activity,
            ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.Reputation DESC) AS rep_rank
        FROM Users u
        LEFT JOIN Votes v   ON v.UserId   = u.Id AND v.VoteTypeId IN (2,3)
        LEFT JOIN Badges b  ON b.UserId   = u.Id
        LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.Reputation, u.CreationDate
    ),

    -- Tag popularity and duplicate‑link counts
    tag_popularity AS (
        SELECT
            t.TagName,
            t.Count                               AS tag_use_cnt,
            COALESCE(SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END),0) AS dup_link_cnt
        FROM Tags t
        LEFT JOIN PostLinks pl ON pl.RelatedPostId = t.WikiPostId
        GROUP BY t.TagName, t.Count
    ),

    -- Combine everything per question‑tag pair
    combined AS (
        SELECT
            qt.question_id,
            qt.Title,
            qt.views,
            qt.q_score,
            qt.tag,
            COALESCE(asr.answer_cnt,0)            AS answer_cnt,
            COALESCE(asr.max_ans_score,0)         AS top_answer_score,
            COALESCE(asr.avg_ans_score,0)         AS avg_answer_score,
            COALESCE(tp.tag_use_cnt,0)            AS tag_use_cnt,
            COALESCE(tp.dup_link_cnt,0)           AS dup_link_cnt,
            ROW_NUMBER() OVER (PARTITION BY qt.question_id ORDER BY qt.views DESC) AS view_rank,
            CASE
                WHEN qt.q_score >= 10 AND COALESCE(asr.max_ans_score,0) >= 10 THEN 'HighEngagement'
                WHEN qt.tag IS NULL THEN 'Untagged'
                ELSE 'Normal'
            END                                   AS engagement_level
        FROM question_tags qt
        LEFT JOIN answer_stats asr ON asr.question_id = qt.question_id
        LEFT JOIN tag_popularity tp ON tp.TagName = qt.tag
    ),

    -- Fetch the top answerer (by score) for each question
    top_answerer AS (
        SELECT DISTINCT ON (a.ParentId)
            a.ParentId                AS question_id,
            a.OwnerUserId             AS user_id,
            a.Score                   AS answer_score,
            a.CreationDate
        FROM Posts a
        WHERE a.PostTypeId = 2
        ORDER BY a.ParentId, a.Score DESC, a.CreationDate ASC
    )

-- Final result set: rich question view plus a fallback set for recent negative‑score, untagged questions
SELECT
    c.question_id,
    c.Title,
    c.views,
    c.q_score,
    c.tag,
    c.answer_cnt,
    c.top_answer_score,
    c.avg_answer_score,
    c.tag_use_cnt,
    c.dup_link_cnt,
    c.view_rank,
    c.engagement_level,
    ua.Reputation,
    ua.badge_cnt,
    ua.vote_score_sum,
    ua.last_activity,
    ua.rep_rank
FROM combined c
LEFT JOIN top_answerer ta   ON ta.question_id = c.question_id
LEFT JOIN user_activity ua ON ua.user_id = ta.user_id
WHERE c.view_rank <= 10
  AND (ua.Reputation IS NULL OR ua.Reputation > 1000)
  AND c.tag IS NOT NULL
  AND c.tag <> ''
UNION ALL
SELECT
    q.Id                         AS question_id,
    q.Title,
    q.ViewCount                  AS views,
    q.Score                      AS q_score,
    NULL                         AS tag,
    0                            AS answer_cnt,
    0                            AS top_answer_score,
    0                            AS avg_answer_score,
    0                            AS tag_use_cnt,
    0                            AS dup_link_cnt,
    0                            AS view_rank,
    'NoTag'                      AS engagement_level,
    NULL                         AS Reputation,
    NULL                         AS badge_cnt,
    NULL                         AS vote_score_sum,
    NULL                         AS last_activity,
    NULL                         AS rep_rank
FROM Posts q
WHERE q.PostTypeId = 1
  AND q.Tags IS NULL
  AND q.CreationDate > CURRENT_DATE - INTERVAL '30 days'
  AND q.Score < 0
ORDER BY views DESC, Reputation DESC NULLS LAST;
