-- {"query": "55047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1742} 

WITH
-- Extract questions with their tag arrays
questions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        regexp_split_to_array(
            trim(both '<>' FROM COALESCE(p.Tags, '')),
            '><'
        ) AS tag_list
    FROM Posts p
    WHERE p.PostTypeId = 1                -- only questions
),

-- Aggregate statistics per tag
tag_stats AS (
    SELECT
        t.TagName,
        COUNT(*)                                            AS question_count,
        AVG(q.Score)                                        AS avg_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY q.Score) AS median_score,
        SUM(q.ViewCount)                                    AS total_views,
        COUNT(DISTINCT q.OwnerUserId)                       AS distinct_askers,
        MAX(q.CreationDate)                                 AS latest_question_date
    FROM questions q
    JOIN LATERAL unnest(q.tag_list) AS tag(tag_name) ON true
    JOIN Tags t ON t.TagName = tag.tag_name
    GROUP BY t.TagName
),

-- Top contributing users per tag (at least 5 questions)
top_users AS (
    SELECT
        t.TagName,
        u.Id                                    AS user_id,
        u.DisplayName,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY SUM(q.Score) DESC) AS rn,
        SUM(q.Score)                            AS total_score,
        COUNT(*)                                 AS questions_answered
    FROM questions q
    JOIN LATERAL unnest(q.tag_list) AS tag(tag_name) ON true
    JOIN Tags t ON t.TagName = tag.tag_name
    JOIN Users u ON u.Id = q.OwnerUserId
    GROUP BY t.TagName, u.Id, u.DisplayName
    HAVING COUNT(*) >= 5
),

-- Badge counts per user
user_badges AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS gold,
        COUNT(*) FILTER (WHERE b.Class = 2) AS silver,
        COUNT(*) FILTER (WHERE b.Class = 3) AS bronze
    FROM Badges b
    GROUP BY b.UserId
),

-- Most recent vote on any post containing the tag (last 30 days)
recent_votes AS (
    SELECT
        v.PostId,
        v.VoteTypeId,
        v.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
    FROM Votes v
    WHERE v.CreationDate >= NOW() - INTERVAL '30 days'
)

SELECT
    ts.TagName,
    ts.question_count,
    ts.avg_score,
    ts.median_score,
    ts.total_views,
    ts.distinct_askers,
    ts.latest_question_date,
    tu.user_id,
    tu.DisplayName,
    tu.total_score,
    tu.questions_answered,
    ub.gold,
    ub.silver,
    ub.bronze,
    rv.VoteTypeId,
    rv.CreationDate AS recent_vote_date
FROM tag_stats ts
LEFT JOIN top_users tu
       ON tu.TagName = ts.TagName AND tu.rn = 1
LEFT JOIN user_badges ub
       ON ub.UserId = tu.user_id
LEFT JOIN LATERAL (
    SELECT rv.VoteTypeId, rv.CreationDate
    FROM recent_votes rv
    JOIN Posts p ON p.Id = rv.PostId
    WHERE p.Tags ILIKE '%' || ts.TagName || '%'
    ORDER BY rv.CreationDate DESC
    LIMIT 1
) rv ON TRUE
ORDER BY ts.question_count DESC
LIMIT 100;
