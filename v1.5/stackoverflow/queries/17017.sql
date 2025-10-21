WITH user_activity_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS questions_asked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answers_given,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS avg_post_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) FILTER (WHERE p.Score > 0) AS median_positive_score,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') FILTER (WHERE p.Tags IS NOT NULL) AS all_tags_used
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '2' YEAR
        AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
elite_answerers AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) AS accepted_answers,
        RANK() OVER (ORDER BY COUNT(*) DESC) AS acceptance_rank,
        DENSE_RANK() OVER (ORDER BY AVG(p.Score) DESC) AS quality_rank
    FROM Posts p
    INNER JOIN Posts q ON p.ParentId = q.Id AND q.AcceptedAnswerId = p.Id
    WHERE p.PostTypeId = 2
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
    HAVING COUNT(*) >= 5
),
controversial_posts AS (
    SELECT 
        p.Id AS post_id,
        p.Title,
        p.Score,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS upvotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS downvotes,
        COUNT(DISTINCT c.Id) AS comment_count,
        MAX(LENGTH(COALESCE(c.Text, ''))) AS max_comment_length,
        COALESCE(p.Score, 0) * 1.0 / NULLIF(COUNT(DISTINCT v.Id), 0) AS score_per_vote
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
        AND p.ClosedDate IS NULL
        AND EXISTS (
            SELECT 1 
            FROM PostHistory ph 
            WHERE ph.PostId = p.Id 
                AND ph.PostHistoryTypeId IN (4, 5, 6)
            HAVING COUNT(*) >= 3
        )
    GROUP BY p.Id, p.Title, p.Score
    HAVING COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) > 
           COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) * 0.3
),
badge_sequences AS (
    SELECT 
        UserId,
        Name AS badge_name,
        Date AS badge_date,
        Class AS badge_class,
        LAG(Date) OVER (PARTITION BY UserId ORDER BY Date) AS prev_badge_date,
        LEAD(Name) OVER (PARTITION BY UserId ORDER BY Date) AS next_badge_name,
        ROW_NUMBER() OVER (PARTITION BY UserId, Name ORDER BY Date) AS badge_occurrence
    FROM Badges
    WHERE TagBased = '0'
)
SELECT 
    uam.DisplayName,
    uam.Reputation,
    COALESCE(uam.total_posts, 0) AS total_posts,
    ROUND(COALESCE(uam.avg_post_score, 0), 2) AS avg_score,
    COALESCE(ea.accepted_answers, 0) AS accepted_answers,
    CASE 
        WHEN ea.acceptance_rank <= 10 THEN 'Elite'
        WHEN ea.acceptance_rank <= 50 THEN 'Expert'
        WHEN ea.acceptance_rank <= 100 THEN 'Advanced'
        WHEN ea.acceptance_rank IS NOT NULL THEN 'Contributor'
        ELSE 'Observer'
    END AS answerer_tier,
    COALESCE(cp.controversial_count, 0) AS controversial_posts,
    CONCAT(
        COALESCE(bs.gold_badges, 0), '/',
        COALESCE(bs.silver_badges, 0), '/',
        COALESCE(bs.bronze_badges, 0)
    ) AS badge_summary,
    CASE 
        WHEN bs.avg_days_between_badges < 30 THEN 'Rapid Achiever'
        WHEN bs.avg_days_between_badges < 90 THEN 'Steady Progress'
        WHEN bs.avg_days_between_badges IS NOT NULL THEN 'Gradual Growth'
        ELSE NULL
    END AS badge_velocity,
    UPPER(SUBSTRING(COALESCE(uam.all_tags_used, 'none'), 1, 1)) || 
    LOWER(SUBSTRING(COALESCE(uam.all_tags_used, 'none'), 2, 100)) AS primary_tags,
    COALESCE((
        SELECT STRING_AGG(DISTINCT CAST(pl.LinkTypeId AS VARCHAR) || ':' || CAST(pl.RelatedPostId AS VARCHAR), '; ')
        FROM PostLinks pl
        INNER JOIN Posts linked_post ON pl.PostId = linked_post.Id
        WHERE linked_post.OwnerUserId = uam.Id
            AND pl.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '6' MONTH
    ), 'No recent links') AS recent_post_links
FROM user_activity_metrics uam
LEFT JOIN elite_answerers ea ON uam.Id = ea.OwnerUserId
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS controversial_count
    FROM controversial_posts cp
    INNER JOIN Posts p ON cp.post_id = p.Id
    WHERE p.OwnerUserId = uam.Id
) cp ON TRUE
LEFT JOIN LATERAL (
    SELECT 
        UserId,
        COUNT(*) FILTER (WHERE badge_class = 1) AS gold_badges,
        COUNT(*) FILTER (WHERE badge_class = 2) AS silver_badges,
        COUNT(*) FILTER (WHERE badge_class = 3) AS bronze_badges,
        AVG(EXTRACT(EPOCH FROM (badge_date - prev_badge_date))/86400) AS avg_days_between_badges
    FROM badge_sequences
    WHERE UserId = uam.Id
    GROUP BY UserId
) bs ON TRUE
WHERE uam.total_posts > 0
    OR EXISTS (
        SELECT 1 
        FROM Comments c 
        WHERE c.UserId = uam.Id 
            AND c.Score > 5
    )
ORDER BY 
    uam.Reputation DESC,
    COALESCE(ea.acceptance_rank, 999999),
    uam.avg_post_score DESC NULLS LAST
LIMIT 100;