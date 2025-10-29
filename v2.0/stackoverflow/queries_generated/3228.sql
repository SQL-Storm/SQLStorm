-- {"query": "3228.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2092} 

WITH TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
    FROM Users u
    WHERE u.Reputation > 1000
),
UserBadgePoints AS (
    SELECT 
        b.UserId,
        SUM(CASE b.Class 
                WHEN 1 THEN 100    -- Gold
                WHEN 2 THEN  50    -- Silver
                ELSE      10       -- Bronze
            END) AS badge_points
    FROM Badges b
    GROUP BY b.UserId
),
UserRecentPost AS (
    SELECT 
        p.OwnerUserId AS UserId,
        MAX(p.CreationDate) AS last_post_date,
        COUNT(*) FILTER (WHERE p.Score > 0) AS positive_posts,
        COUNT(*) FILTER (WHERE p.Score <= 0) AS nonpositive_posts
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserVoteStats AS (
    SELECT 
        v.PostId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS upvotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS downvotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS favorites
    FROM Votes v
    GROUP BY v.PostId
),
UserAggregated AS (
    SELECT 
        tu.Id,
        tu.DisplayName,
        tu.Reputation,
        COALESCE(ubp.badge_points, 0) AS badge_points,
        COALESCE(urp.last_post_date, TIMESTAMP '1970-01-01') AS last_post_date,
        COALESCE(urp.positive_posts, 0)      AS positive_posts,
        COALESCE(urp.nonpositive_posts,0)    AS nonpositive_posts,
        ROUND(
            COALESCE(ubp.badge_points::numeric,0) 
            / NULLIF(tu.Reputation,0)::numeric,
            2) AS badge_to_rep_ratio
    FROM TopUsers tu
    LEFT JOIN UserBadgePoints ubp ON ubp.UserId = tu.Id
    LEFT JOIN UserRecentPost urp ON urp.UserId = tu.Id
),
PostDetails AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        COALESCE(vs.upvotes,0)     AS upvotes,
        COALESCE(vs.downvotes,0)   AS downvotes,
        COALESCE(vs.favorites,0)   AS favorites,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.CreationDate DESC
        ) AS rn
    FROM Posts p
    LEFT JOIN UserVoteStats vs ON vs.PostId = p.Id
    WHERE p.PostTypeId = 1                                 -- questions only
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
),
TopPostsPerUser AS (
    SELECT 
        pd.Id,
        pd.Title,
        pd.CreationDate,
        pd.Score,
        pd.ViewCount,
        pd.Tags,
        pd.OwnerUserId,
        pd.upvotes,
        pd.downvotes,
        pd.favorites
    FROM PostDetails pd
    WHERE pd.rn = 1
)
SELECT 
    ua.Id                                   AS user_id,
    ua.DisplayName,
    ua.Reputation,
    ua.badge_points,
    ua.badge_to_rep_ratio,
    ua.last_post_date,
    ua.positive_posts,
    ua.nonpositive_posts,
    tp.Id                                   AS top_question_id,
    tp.Title                                AS top_question_title,
    tp.CreationDate                         AS top_question_date,
    tp.Score                                AS top_question_score,
    tp.ViewCount                            AS top_question_views,
    tp.upvotes                              AS top_question_upvotes,
    tp.downvotes                            AS top_question_downvotes,
    tp.favorites                            AS top_question_favorites,
    COALESCE((regexp_split_to_array(tp.Tags, '[><]+'))[1], '') AS first_tag,
    LENGTH(COALESCE(tp.Tags,'')) - 
        LENGTH(REPLACE(COALESCE(tp.Tags,''), '>', '')) AS tag_count_estimate
FROM UserAggregated ua
LEFT JOIN TopPostsPerUser tp ON tp.OwnerUserId = ua.Id
WHERE ua.rn <= 50
ORDER BY ua.Reputation DESC, ua.badge_points DESC
UNION ALL
SELECT 
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL
LIMIT 1000;
