WITH user_stats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)               AS question_count,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)               AS answer_count,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)              AS avg_question_score,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)              AS avg_answer_score,
        SUM(v.up_votes)                                           AS upvotes,
        SUM(v.down_votes)                                         AS downvotes,
        MAX(p.LastActivityDate)                                   AS recent_activity
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
        SELECT 
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)   AS up_votes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)   AS down_votes
        FROM Votes v
        WHERE v.PostId = p.Id
    ) v ON true
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_counts AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)   AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)   AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)   AS bronze_badges
    FROM Badges b
    GROUP BY b.UserId
),
user_tag_counts AS (
    SELECT 
        u.Id                                   AS UserId,
        t.TagName,
        COUNT(*)                               AS tag_use_cnt
    FROM Users u
    JOIN Posts p
        ON p.OwnerUserId = u.Id
        AND p.PostTypeId = 1                     -- only questions
    JOIN LATERAL (
        SELECT regexp_split_to_table(p.Tags, '[><]') AS tag_raw
    ) split ON true
    JOIN Tags t
        ON t.TagName = split.tag_raw
    GROUP BY u.Id, t.TagName
),
top_three_tags AS (
    SELECT 
        UserId,
        STRING_AGG(TagName, ', ') AS top_3_tags
    FROM (
        SELECT 
            UserId,
            TagName,
            tag_use_cnt,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY tag_use_cnt DESC) AS rn
        FROM user_tag_counts
    ) ranked
    WHERE rn <= 3
    GROUP BY UserId
)
SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.question_count,
    us.answer_count,
    ROUND(COALESCE(us.avg_question_score, 0) , 2)    AS avg_question_score,
    ROUND(COALESCE(us.avg_answer_score, 0) , 2)      AS avg_answer_score,
    us.upvotes,
    us.downvotes,
    bc.gold_badges,
    bc.silver_badges,
    bc.bronze_badges,
    us.recent_activity,
    t.top_3_tags
FROM user_stats us
LEFT JOIN badge_counts bc
    ON bc.UserId = us.Id
LEFT JOIN top_three_tags t
    ON t.UserId = us.Id
ORDER BY us.Reputation DESC
LIMIT 100;