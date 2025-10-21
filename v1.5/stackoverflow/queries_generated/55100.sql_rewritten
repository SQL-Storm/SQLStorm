-- {"query": "55100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1873} 
WITH 
    -- All posts owned by users
    user_posts AS (
        SELECT 
            u.Id                         AS user_id,
            p.Id                         AS post_id,
            p.PostTypeId,
            p.Score,
            p.CreationDate,
            p.Tags
        FROM Users u
        JOIN Posts p ON p.OwnerUserId = u.Id
    ),

    -- Aggregate post statistics per user
    post_metrics AS (
        SELECT 
            up.user_id,
            COUNT(*) FILTER (WHERE up.PostTypeId = 1)                     AS question_count,
            COUNT(*) FILTER (WHERE up.PostTypeId = 2)                     AS answer_count,
            SUM(up.Score)                                                 AS total_score,
            AVG(up.Score)                                                 AS avg_score,
            COUNT(DISTINCT tag) FILTER (WHERE up.PostTypeId = 1)          AS distinct_tag_count
        FROM user_posts up
        LEFT JOIN LATERAL (
            SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(up.Tags, 2, LENGTH(up.Tags)-2), '><')) AS tag
        ) t ON up.Tags IS NOT NULL
        GROUP BY up.user_id
    ),

    -- Badge counts per class per user
    badge_counts AS (
        SELECT 
            b.UserId                     AS user_id,
            COUNT(*) FILTER (WHERE b.Class = 1)  AS gold_badges,
            COUNT(*) FILTER (WHERE b.Class = 2)  AS silver_badges,
            COUNT(*) FILTER (WHERE b.Class = 3)  AS bronze_badges
        FROM Badges b
        GROUP BY b.UserId
    ),

    -- Vote aggregates per post
    vote_agg AS (
        SELECT 
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
        FROM Votes v
        GROUP BY v.PostId
    ),

    -- Sum of votes per user (through their posts)
    user_votes AS (
        SELECT 
            p.OwnerUserId               AS user_id,
            SUM(va.up_votes)           AS total_up_votes,
            SUM(va.down_votes)         AS total_down_votes
        FROM Posts p
        JOIN vote_agg va ON va.PostId = p.Id
        GROUP BY p.OwnerUserId
    ),

    -- Count of closed events per user (via PostHistory)
    closed_counts AS (
        SELECT 
            ph.UserId                   AS user_id,
            COUNT(*)                    AS closed_count
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10      -- Post Closed
        GROUP BY ph.UserId
    ),

    -- Tag usage per user (how many distinct tags they have ever used)
    user_tag_usage AS (
        SELECT 
            up.user_id,
            COUNT(DISTINCT t.tag) AS distinct_tag_usage
        FROM user_posts up
        LEFT JOIN LATERAL (
            SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(up.Tags, 2, LENGTH(up.Tags)-2), '><')) AS tag
        ) t ON up.Tags IS NOT NULL
        WHERE up.PostTypeId = 1               -- only questions have tags
        GROUP BY up.user_id
    )

SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(pm.question_count, 0)   AS question_count,
    COALESCE(pm.answer_count, 0)     AS answer_count,
    COALESCE(pm.total_score, 0)      AS total_score,
    COALESCE(pm.avg_score, 0)        AS avg_score,
    COALESCE(bc.gold_badges, 0)      AS gold_badges,
    COALESCE(bc.silver_badges, 0)    AS silver_badges,
    COALESCE(bc.bronze_badges, 0)    AS bronze_badges,
    COALESCE(uv.total_up_votes, 0)   AS total_up_votes,
    COALESCE(uv.total_down_votes, 0) AS total_down_votes,
    COALESCE(cc.closed_count, 0)     AS closed_posts_count,
    COALESCE(uta.distinct_tag_usage, 0) AS distinct_tags_used,
    COALESCE(pm.distinct_tag_count,0)   AS distinct_tags_on_questions
FROM Users u
LEFT JOIN post_metrics pm      ON pm.user_id = u.Id
LEFT JOIN badge_counts bc      ON bc.user_id = u.Id
LEFT JOIN user_votes uv        ON uv.user_id = u.Id
LEFT JOIN closed_counts cc    ON cc.user_id = u.Id
LEFT JOIN user_tag_usage uta   ON uta.user_id = u.Id
ORDER BY u.Reputation DESC
LIMIT 100;