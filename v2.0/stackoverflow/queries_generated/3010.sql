-- {"query": "3010.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2348} 

WITH
    q_posts AS (
        SELECT
            p.Id,
            p.OwnerUserId,
            p.Score,
            p.CreationDate,
            regexp_replace(p.Title, '<[^>]+>', '', 'g')        AS clean_title,
            COALESCE(p.Tags, '')                               AS tags_text,
            CASE
                WHEN p.Tags IS NOT NULL AND length(p.Tags) > 2
                THEN string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')
                ELSE ARRAY[]::varchar[]
            END                                               AS tags_array
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    a_posts AS (
        SELECT
            p.Id,
            p.ParentId                                   AS question_id,
            p.OwnerUserId,
            p.Score,
            p.CreationDate,
            p.Body,
            ROW_NUMBER() OVER (
                PARTITION BY p.ParentId
                ORDER BY p.Score DESC, p.CreationDate
            )                                            AS rn
        FROM Posts p
        WHERE p.PostTypeId = 2
    ),
    user_badges AS (
        SELECT
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1)         AS gold,
            COUNT(*) FILTER (WHERE b.Class = 2)         AS silver,
            COUNT(*) FILTER (WHERE b.Class = 3)         AS bronze,
            COUNT(*)                                    AS total_badges,
            MAX(b.Date)                                 AS last_badge_date
        FROM Badges b
        GROUP BY b.UserId
    ),
    user_votes AS (
        SELECT
            v.UserId,
            COUNT(*) FILTER (WHERE vt.Name = 'UpMod')   AS up_votes,
            COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS down_votes,
            SUM(CASE
                    WHEN vt.Name = 'UpMod'   THEN 1
                    WHEN vt.Name = 'DownMod' THEN -1
                    ELSE 0
                END)                                     AS net_votes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.UserId
    ),
    recent_questions AS (
        SELECT
            q.Id,
            q.OwnerUserId,
            q.Score,
            q.clean_title,
            q.tags_array,
            ROW_NUMBER() OVER (ORDER BY q.CreationDate DESC) AS recent_rank
        FROM q_posts q
        WHERE q.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    ),
    top_answerers AS (
        SELECT
            a.question_id,
            a.OwnerUserId,
            a.Score,
            a.rn,
            q.Title
        FROM a_posts a
        JOIN q_posts q ON q.Id = a.question_id
        WHERE a.rn = 1
    )
SELECT
    u.Id                                            AS user_id,
    COALESCE(u.DisplayName, 'Anonymous')            AS display_name,
    u.Reputation,
    ub.gold,
    ub.silver,
    ub.bronze,
    uv.up_votes,
    uv.down_votes,
    uv.net_votes,
    COALESCE(ub.total_badges, 0)                    AS badge_count,
    COALESCE(rq.recent_rank, 0)                     AS recent_question_rank,
    COALESCE(ta.Title, '')                         AS top_answered_question,
    COALESCE(ta.Score, 0)                           AS top_answer_score,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM PostLinks pl
            WHERE pl.PostId = ANY (
                SELECT unnest(rq.tags_array)::int
            )
              AND pl.LinkTypeId = 3
        ) THEN 1
        ELSE 0
    END                                            AS has_duplicate_link
FROM Users u
LEFT JOIN user_badges ub      ON ub.UserId = u.Id
LEFT JOIN user_votes uv      ON uv.UserId = u.Id
LEFT JOIN recent_questions rq ON rq.OwnerUserId = u.Id
LEFT JOIN top_answerers ta    ON ta.OwnerUserId = u.Id
WHERE (u.CreationDate < CURRENT_DATE - INTERVAL '1 year' OR u.Reputation > 1000)
ORDER BY uv.net_votes DESC NULLS LAST
LIMIT 100

UNION ALL

SELECT
    NULL                                           AS user_id,
    'Summary'                                      AS display_name,
    NULL                                           AS Reputation,
    SUM(COALESCE(gold, 0))                         AS gold,
    SUM(COALESCE(silver, 0))                       AS silver,
    SUM(COALESCE(bronze, 0))                       AS bronze,
    SUM(COALESCE(up_votes, 0))                     AS up_votes,
    SUM(COALESCE(down_votes, 0))                   AS down_votes,
    SUM(COALESCE(net_votes, 0))                    AS net_votes,
    NULL                                           AS badge_count,
    NULL                                           AS recent_question_rank,
    NULL                                           AS top_answered_question,
    NULL                                           AS top_answer_score,
    NULL                                           AS has_duplicate_link
FROM (
    SELECT ub.gold, ub.silver, ub.bronze,
           uv.up_votes, uv.down_votes, uv.net_votes
    FROM Users u
    LEFT JOIN user_badges ub ON ub.UserId = u.Id
    LEFT JOIN user_votes uv ON uv.UserId = u.Id
) sub;
