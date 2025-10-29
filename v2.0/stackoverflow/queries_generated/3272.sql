-- {"query": "3272.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1763} 

-- Benchmark query: heavy use of CTEs, joins, window functions, set operators and complex predicates
WITH
-- 1. Basic user aggregates
user_stats AS (
    SELECT
        u.Id                                   AS user_id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Views,0)                    AS total_views,
        COUNT(b.Id)                            AS badge_count,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
        COUNT(DISTINCT p.Id)                   AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END)        AS avg_answer_score,
        MAX(p.CreationDate)                    AS last_post_date
    FROM Users u
    LEFT JOIN Badges b      ON b.UserId = u.Id
    LEFT JOIN Posts  p      ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),

-- 2. Recent voting activity per user (last 30 days)
recent_votes AS (
    SELECT
        v.UserId                               AS voter_id,
        COUNT(*)                               AS votes_cast,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS down_votes,
        MAX(v.CreationDate)                    AS last_vote_date
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 day'
      AND v.UserId IS NOT NULL
    GROUP BY v.UserId
),

-- 3. Tag activity derived from question posts (exploding the Tags column)
tag_activity AS (
    SELECT
        u.Id                                   AS user_id,
        t.TagName,
        COUNT(*)                               AS questions_tagged,
        AVG(p.Score)                           AS avg_question_score,
        MAX(p.CreationDate)                    AS last_question_date
    FROM Users u
    JOIN Posts p      ON p.OwnerUserId = u.Id
    JOIN PostTypes pt ON pt.Id = p.PostTypeId
    JOIN LATERAL (
        SELECT trim(both '><' from split_part(tg, '><', n)) AS TagName
        FROM generate_series(1,
            array_length(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><'),1)
        ) AS n
        CROSS JOIN LATERAL string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><') AS tg
    ) AS t ON true
    WHERE pt.Name = 'Question' AND p.Tags IS NOT NULL
    GROUP BY u.Id, t.TagName
),

-- 4. Users with no recent activity (NULL handling)
inactive_users AS (
    SELECT
        us.user_id,
        us.DisplayName,
        us.Reputation,
        us.last_post_date,
        rv.last_vote_date
    FROM user_stats us
    LEFT JOIN recent_votes rv ON rv.voter_id = us.user_id
    WHERE (us.last_post_date IS NULL OR us.last_post_date < CURRENT_DATE - INTERVAL '365 day')
      AND (rv.last_vote_date IS NULL OR rv.last_vote_date < CURRENT_DATE - INTERVAL '365 day')
),

-- 5. Top users per tag (using window functions)
top_tag_users AS (
    SELECT
        ta.user_id,
        ta.TagName,
        ta.questions_tagged,
        ROW_NUMBER() OVER (PARTITION BY ta.TagName ORDER BY ta.questions_tagged DESC) AS tag_rank
    FROM tag_activity ta
),

-- 6. Union of active and inactive user snapshots for set operator test
user_snapshot AS (
    SELECT
        us.user_id,
        us.DisplayName,
        us.Reputation,
        us.total_views,
        us.badge_count,
        us.gold_badges,
        us.silver_badges,
        us.bronze_badges,
        us.question_count,
        us.answer_count,
        us.avg_answer_score,
        'ACTIVE' AS user_status
    FROM user_stats us
    WHERE us.last_post_date >= CURRENT_DATE - INTERVAL '90 day'

    UNION ALL

    SELECT
        iu.user_id,
        iu.DisplayName,
        iu.Reputation,
        0                AS total_views,
        0                AS badge_count,
        0                AS gold_badges,
        0                AS silver_badges,
        0                AS bronze_badges,
        0                AS question_count,
        0                AS answer_count,
        0                AS avg_answer_score,
        'INACTIVE' AS user_status
    FROM inactive_users iu
)

-- Final result set with ordering and a complex predicate
SELECT
    us.user_id,
    us.DisplayName,
    us.Reputation,
    us.total_views,
    us.badge_count,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    us.question_count,
    us.answer_count,
    ROUND(us.avg_answer_score,2)               AS avg_answer_score,
    us.user_status,
    COALESCE(rv.votes_cast,0)                 AS votes_last_30d,
    COALESCE(rv.up_votes,0)                   AS up_votes_last_30d,
    COALESCE(rv.down_votes,0)                 AS down_votes_last_30d,
    tt.TagName,
    tt.questions_tagged,
    tt.tag_rank
FROM user_snapshot us
LEFT JOIN recent_votes rv ON rv.voter_id = us.user_id
LEFT JOIN top_tag_users tt ON tt.user_id = us.user_id AND tt.tag_rank <= 3
WHERE (us.Reputation > 10000 OR us.badge_count >= 10)
  AND (us.user_status = 'ACTIVE' OR tt.TagName IS NOT NULL)
ORDER BY us.Reputation DESC, us.badge_count DESC, tt.tag_rank ASC
LIMIT 200;
