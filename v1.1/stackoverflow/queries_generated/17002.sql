-- {"query": "17002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2497}

WITH user_activity_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS questions_asked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answers_given,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS avg_post_score,
        COALESCE(SUM(p.ViewCount), 0) AS total_views,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') FILTER (WHERE p.Tags IS NOT NULL) AS all_tags_used,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS reputation_rank,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) OVER (PARTITION BY u.Id) AS median_score
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND (u.Location IS NOT NULL OR u.AboutMe IS NOT NULL)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
top_answerers AS (
    SELECT 
        p.OwnerUserId,
        p.ParentId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS answer_rank,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) AS next_best_score,
        CASE 
            WHEN p.Id = q.AcceptedAnswerId THEN 'ACCEPTED'
            WHEN p.Score > 10 THEN 'HIGH_SCORE'
            WHEN p.Score < 0 THEN 'NEGATIVE'
            ELSE 'NEUTRAL'
        END AS answer_quality
    FROM Posts p
    INNER JOIN Posts q ON p.ParentId = q.Id AND q.PostTypeId = 1
    WHERE p.PostTypeId = 2 
        AND p.OwnerUserId IS NOT NULL
),
badge_analysis AS (
    SELECT 
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS gold_badges,
        COUNT(*) FILTER (WHERE Class = 2) AS silver_badges,
        COUNT(*) FILTER (WHERE Class = 3) AS bronze_badges,
        COUNT(*) FILTER (WHERE TagBased = B'1') AS tag_badges,
        MIN(Date) AS first_badge_date,
        MAX(Date) AS latest_badge_date,
        EXTRACT(EPOCH FROM (MAX(Date) - MIN(Date)))/86400.0 AS badge_span_days
    FROM Badges
    GROUP BY UserId
),
comment_sentiment AS (
    SELECT 
        c.UserId,
        COUNT(*) AS total_comments,
        AVG(LENGTH(c.Text)) AS avg_comment_length,
        SUM(CASE WHEN LOWER(c.Text) LIKE '%thank%' OR LOWER(c.Text) LIKE '%great%' OR LOWER(c.Text) LIKE '%excellent%' THEN 1 ELSE 0 END) AS positive_comments,
        SUM(CASE WHEN LOWER(c.Text) LIKE '%wrong%' OR LOWER(c.Text) LIKE '%bad%' OR LOWER(c.Text) LIKE '%incorrect%' THEN 1 ELSE 0 END) AS negative_comments,
        COUNT(*) FILTER (WHERE c.Score > 5) AS high_score_comments
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
recursive_post_chain AS (
    SELECT 
        Id AS root_id,
        Id,
        ParentId,
        PostTypeId,
        Score,
        0 AS depth,
        ARRAY[Id] AS path
    FROM Posts
    WHERE PostTypeId = 1 AND ParentId IS NULL
    
    UNION ALL
    
    SELECT 
        rpc.root_id,
        p.Id,
        p.ParentId,
        p.PostTypeId,
        p.Score,
        rpc.depth + 1,
        rpc.path || p.Id
    FROM recursive_post_chain rpc
    INNER JOIN Posts p ON p.ParentId = rpc.Id
    WHERE rpc.depth < 3 AND NOT (p.Id = ANY(rpc.path))
)
SELECT DISTINCT
    uam.DisplayName,
    uam.Reputation,
    uam.reputation_rank,
    COALESCE(uam.questions_asked, 0) AS questions_asked,
    COALESCE(uam.answers_given, 0) AS answers_given,
    ROUND(CAST(uam.avg_post_score AS NUMERIC), 2) AS avg_post_score,
    uam.median_score,
    uam.total_views,
    CASE 
        WHEN uam.all_tags_used IS NULL THEN 'NO_TAGS'
        WHEN LENGTH(uam.all_tags_used) > 100 THEN SUBSTRING(uam.all_tags_used, 1, 97) || '...'
        ELSE uam.all_tags_used
    END AS primary_tags,
    COALESCE(ba.gold_badges, 0) + COALESCE(ba.silver_badges, 0) * 0.5 + COALESCE(ba.bronze_badges, 0) * 0.25 AS weighted_badge_score,
    COALESCE(ba.badge_span_days, 0) AS badge_collection_days,
    COALESCE(cs.total_comments, 0) AS comments_made,
    ROUND(COALESCE(cs.positive_comments::NUMERIC / NULLIF(cs.total_comments, 0), 0) * 100, 1) AS positive_comment_ratio,
    COUNT(DISTINCT ta.ParentId) FILTER (WHERE ta.answer_rank = 1) AS best_answers,
    COUNT(DISTINCT ta.ParentId) FILTER (WHERE ta.answer_quality = 'ACCEPTED') AS accepted_answers,
    MAX(ta.Score - ta.next_best_score) AS max_score_differential,
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks pl
        INNER JOIN Posts linked_post ON pl.PostId = linked_post.Id
        WHERE linked_post.OwnerUserId = uam.Id
            AND pl.LinkTypeId = 1
    ) AS posts_linked_to,
    EXISTS (
        SELECT 1 
        FROM PostHistory ph 
        WHERE ph.UserId = uam.Id 
            AND ph.PostHistoryTypeId IN (10, 12, 14)
    ) AS has_moderation_activity,
    COALESCE(
        (
            SELECT STRING_AGG(DISTINCT vt.Name, ', ' ORDER BY vt.Name)
            FROM Votes v
            INNER JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
            WHERE v.UserId = uam.Id
                AND v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
        ),
        'NO_RECENT_VOTES'
    ) AS recent_vote_types,
    CASE 
        WHEN uam.Reputation > 10000 AND ba.gold_badges > 5 THEN 'EXPERT'
        WHEN uam.Reputation > 5000 OR ba.gold_badges > 0 THEN 'ADVANCED'
        WHEN uam.Reputation > 1000 THEN 'INTERMEDIATE'
        ELSE 'BEGINNER'
    END AS user_tier
FROM user_activity_metrics uam
LEFT JOIN badge_analysis ba ON uam.Id = ba.UserId
LEFT JOIN comment_sentiment cs ON uam.Id = cs.UserId
LEFT JOIN top_answerers ta ON uam.Id = ta.OwnerUserId
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS chain_participation
    FROM recursive_post_chain rpc
    WHERE rpc.root_id IN (
        SELECT Id 
        FROM Posts 
        WHERE OwnerUserId = uam.Id 
            AND PostTypeId = 1
    )
) chain_stats ON true
WHERE uam.Reputation > 100
    AND (uam.questions_asked > 0 OR uam.answers_given > 0)
    AND NOT EXISTS (
        SELECT 1
        FROM Users u2
        WHERE u2.Id != uam.Id
            AND u2.EmailHash = (SELECT EmailHash FROM Users WHERE Id = uam.Id)
            AND (SELECT EmailHash FROM Users WHERE Id = uam.Id) IS NOT NULL
    )
GROUP BY 
    uam.Id, uam.DisplayName, uam.Reputation, uam.reputation_rank,
    uam.questions_asked, uam.answers_given, uam.avg_post_score,
    uam.median_score, uam.total_views, uam.all_tags_used,
    ba.gold_badges, ba.silver_badges, ba.bronze_badges,
    ba.badge_span_days, cs.total_comments, cs.positive_comments
HAVING COUNT(DISTINCT ta.ParentId) > 0 
    OR uam.questions_asked > 5
    OR ba.gold_badges IS NOT NULL
ORDER BY 
    weighted_badge_score DESC NULLS LAST,
    uam.Reputation DESC,
    best_answers DESC NULLS LAST
LIMIT 100;
