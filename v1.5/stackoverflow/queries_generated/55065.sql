-- {"query": "55065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1614} 

WITH user_stats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id)          FILTER (WHERE p.PostTypeId = 1) AS question_count,
        COUNT(p.Id)          FILTER (WHERE p.PostTypeId = 2) AS answer_count,
        COALESCE(SUM(p.Score),0)                         AS total_score,
        AVG(p.Score)         FILTER (WHERE p.PostTypeId = 1) AS avg_question_score,
        AVG(p.Score)         FILTER (WHERE p.PostTypeId = 2) AS avg_answer_score,
        COUNT(b.Id)                                  AS badge_count,
        COUNT(*)              FILTER (WHERE b.Class = 1) AS gold_badges,
        COUNT(*)              FILTER (WHERE b.Class = 2) AS silver_badges,
        COUNT(*)              FILTER (WHERE b.Class = 3) AS bronze_badges,
        MAX(p.CreationDate)                         AS last_post_date
    FROM Users u
    LEFT JOIN Posts   p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges  b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

top_tags AS (
    SELECT 
        t.TagName,
        COUNT(p.Id)                         AS post_usage,
        SUM(p.Score)                        AS total_score,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS rn
    FROM Tags t
    JOIN Posts p ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 100
),

recent_votes AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
        MAX(v.CreationDate)                               AS last_vote_date
    FROM Votes v
    WHERE v.CreationDate >= NOW() - INTERVAL '30 days'
    GROUP BY v.PostId
)

SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.question_count,
    us.answer_count,
    us.total_score,
    us.avg_question_score,
    us.avg_answer_score,
    us.badge_count,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    us.last_post_date,
    tt.TagName,
    tt.post_usage,
    rv.upvotes,
    rv.downvotes,
    rv.last_vote_date
FROM user_stats us
LEFT JOIN LATERAL (
    SELECT TagName, post_usage
    FROM top_tags
    WHERE rn = 1
) tt ON true
LEFT JOIN LATERAL (
    SELECT 
        rv.upvotes,
        rv.downvotes,
        rv.last_vote_date
    FROM recent_votes rv
    WHERE rv.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = us.Id
        ORDER BY p.CreationDate DESC
        LIMIT 1
    )
) rv ON true
WHERE us.Reputation > 10000
ORDER BY us.total_score DESC, us.Reputation DESC
LIMIT 50;
