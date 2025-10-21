-- {"query": "17084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 1986}

WITH user_activity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS post_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
        AVG(p.Score) AS avg_post_score,
        MAX(p.CreationDate) AS last_post_date,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS reputation_rank,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
tag_expertise AS (
    SELECT 
        p.OwnerUserId,
        TRIM(BOTH '<>' FROM UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'))) AS tag,
        COUNT(*) AS tag_usage,
        SUM(p.Score) AS total_tag_score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY SUM(p.Score) DESC, COUNT(*) DESC) AS tag_rank
    FROM Posts p
    WHERE p.Tags IS NOT NULL 
        AND p.PostTypeId = 1
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, tag
),
complex_aggregations AS (
    SELECT 
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.post_count,
        ua.avg_post_score,
        ua.reputation_rank,
        te.tag AS top_tag,
        te.total_tag_score AS top_tag_score,
        COALESCE(badge_data.gold_badges, 0) AS gold_badges,
        COALESCE(badge_data.silver_badges, 0) AS silver_badges,
        COALESCE(badge_data.bronze_badges, 0) AS bronze_badges,
        CASE 
            WHEN ua.avg_post_score > (SELECT AVG(Score) FROM Posts WHERE Score IS NOT NULL) * 2 
                AND ua.post_count >= 50 
            THEN 'Elite Contributor'
            WHEN ua.reputation_rank <= 100 
            THEN 'Top 100 User'
            WHEN ua.post_count >= 100 
            THEN 'Active Contributor'
            ELSE 'Regular User'
        END AS user_category,
        COALESCE(
            (SELECT STRING_AGG(DISTINCT UPPER(SUBSTRING(c.Text, 1, 50)), ' | ' ORDER BY UPPER(SUBSTRING(c.Text, 1, 50)))
             FROM Comments c
             WHERE c.UserId = ua.Id 
                AND c.Score >= 5
                AND c.Text LIKE '%thank%' OR c.Text LIKE '%great%' OR c.Text LIKE '%helpful%'
             LIMIT 3), 
            'No highly rated comments'
        ) AS top_comment_snippets
    FROM user_activity ua
    LEFT JOIN tag_expertise te ON ua.Id = te.OwnerUserId AND te.tag_rank = 1
    LEFT JOIN LATERAL (
        SELECT 
            UserId,
            COUNT(CASE WHEN Class = 1 THEN 1 END) AS gold_badges,
            COUNT(CASE WHEN Class = 2 THEN 1 END) AS silver_badges,
            COUNT(CASE WHEN Class = 3 THEN 1 END) AS bronze_badges
        FROM Badges
        WHERE UserId = ua.Id
        GROUP BY UserId
    ) badge_data ON TRUE
),
recursive_post_chain AS (
    SELECT 
        p.Id AS root_id,
        p.Id AS current_id,
        p.Title AS root_title,
        1 AS depth,
        p.Score AS cumulative_score,
        ARRAY[p.Id] AS path
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.AcceptedAnswerId IS NOT NULL
        AND p.Score > 50
    
    UNION ALL
    
    SELECT 
        rpc.root_id,
        pl.RelatedPostId AS current_id,
        rpc.root_title,
        rpc.depth + 1,
        rpc.cumulative_score + COALESCE(p2.Score, 0),
        rpc.path || pl.RelatedPostId
    FROM recursive_post_chain rpc
    JOIN PostLinks pl ON pl.PostId = rpc.current_id
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE rpc.depth < 5 
        AND NOT (pl.RelatedPostId = ANY(rpc.path))
)
SELECT 
    ca.DisplayName,
    ca.Reputation,
    ca.user_category,
    ca.top_tag,
    ca.top_tag_score,
    ROUND(ca.avg_post_score::numeric, 2) AS avg_post_score,
    ca.gold_badges || '/' || ca.silver_badges || '/' || ca.bronze_badges AS badge_count_gsc,
    ca.post_count,
    COALESCE(
        (SELECT COUNT(DISTINCT v.PostId)
         FROM Votes v
         JOIN Posts p ON v.PostId = p.Id
         WHERE p.OwnerUserId = ca.Id
            AND v.VoteTypeId IN (2, 3)
            AND v.CreationDate >= CURRENT_DATE - INTERVAL '6 months'),
        0
    ) AS recent_voted_posts,
    EXISTS (
        SELECT 1
        FROM Posts p1
        WHERE p1.OwnerUserId = ca.Id
            AND p1.PostTypeId = 2
            AND p1.ParentId IN (
                SELECT p2.Id 
                FROM Posts p2 
                WHERE p2.AcceptedAnswerId = p1.Id
            )
    ) AS has_accepted_answer,
    CASE 
        WHEN ca.Reputation > ALL (
            SELECT u2.Reputation 
            FROM Users u2 
            JOIN Posts p2 ON u2.Id = p2.OwnerUserId
            WHERE p2.Tags LIKE '%' || ca.top_tag || '%'
                AND u2.Id != ca.Id
            LIMIT 10
        ) THEN 'Tag Leader'
        ELSE 'Tag Contributor'
    END AS tag_status,
    SUBSTRING(ca.top_comment_snippets, 1, 100) AS comment_preview,
    (
        SELECT COALESCE(MAX(rpc.cumulative_score), 0)
        FROM recursive_post_chain rpc
        JOIN Posts p ON p.Id = rpc.root_id
        WHERE p.OwnerUserId = ca.Id
    ) AS max_post_chain_score
FROM complex_aggregations ca
WHERE ca.post_count > 0
    AND (ca.gold_badges > 0 OR ca.silver_badges > 5 OR ca.bronze_badges > 10)
ORDER BY 
    CASE ca.user_category 
        WHEN 'Elite Contributor' THEN 1
        WHEN 'Top 100 User' THEN 2
        WHEN 'Active Contributor' THEN 3
        ELSE 4
    END,
    ca.Reputation DESC NULLS LAST,
    ca.avg_post_score DESC NULLS LAST
LIMIT 100;
