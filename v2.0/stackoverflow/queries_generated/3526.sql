-- {"query": "3526.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1974} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS gold_badges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS silver_badges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS bronze_badges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS question_count,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS answer_count,
        COALESCE((
            SELECT AVG(p.Score) 
            FROM Posts p 
            WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1
        ), 0) AS avg_question_score
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentVotes AS (
    SELECT 
        v.UserId,
        ROW_NUMBER() OVER (PARTITION BY v.UserId ORDER BY v.CreationDate DESC) AS rn,
        v.VoteTypeId,
        v.CreationDate,
        p.Id AS PostId,
        p.Title
    FROM Votes v
    JOIN Posts p ON p.Id = v.PostId
    WHERE v.UserId IS NOT NULL
),
TopRecentVotes AS (
    SELECT UserId, VoteTypeId, CreationDate, PostId, Title
    FROM RecentVotes
    WHERE rn <= 5
),
TagActivity AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS question_posts,
        SUM(p.Score) AS total_score,
        AVG(p.ViewCount) AS avg_views
    FROM Tags t
    JOIN Posts p ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
Combined AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.gold_badges,
        us.silver_badges,
        us.bronze_badges,
        us.question_count,
        us.answer_count,
        us.avg_question_score,
        COALESCE(rv.VoteTypeId, 0)           AS recent_vote_type,
        rv.CreationDate                      AS recent_vote_date,
        rv.Title                             AS recent_voted_post_title,
        COALESCE(ta.TagName, '<no tag>')     AS top_tag,
        COALESCE(ta.total_score, 0)          AS top_tag_score
    FROM UserStats us
    LEFT JOIN LATERAL (
        SELECT rv.VoteTypeId, rv.CreationDate, rv.Title
        FROM TopRecentVotes rv
        WHERE rv.UserId = us.Id
        ORDER BY rv.CreationDate DESC
        LIMIT 1
    ) rv ON TRUE
    LEFT JOIN LATERAL (
        SELECT t.TagName, t.total_score
        FROM TagActivity t
        ORDER BY t.total_score DESC
        LIMIT 1
    ) ta ON TRUE
)
SELECT *
FROM Combined
WHERE Reputation > 10000
   OR gold_badges >= 5
   OR avg_question_score > 2
ORDER BY Reputation DESC, gold_badges DESC
LIMIT 100

UNION ALL

SELECT 
    NULL::int          AS Id,
    '--- Summary ---'  AS DisplayName,
    NULL::int          AS Reputation,
    NULL::int          AS gold_badges,
    NULL::int          AS silver_badges,
    NULL::int          AS bronze_badges,
    NULL::int          AS question_count,
    NULL::int          AS answer_count,
    NULL::numeric      AS avg_question_score,
    NULL::smallint     AS recent_vote_type,
    NULL::timestamp    AS recent_vote_date,
    NULL::varchar      AS recent_voted_post_title,
    NULL::varchar      AS top_tag,
    NULL::int          AS top_tag_score
FROM (SELECT 1) AS dummy;