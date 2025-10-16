WITH user_activity_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT p.Id) AS post_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS avg_post_score,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions_with_accepted_answers,
        ROW_NUMBER() OVER (PARTITION BY SUBSTRING(COALESCE(u.Location, 'Unknown'), 1, 20) ORDER BY u.Reputation DESC) AS location_rank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS overall_post_rank
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= DATE '2020-01-01'
        AND (u.Reputation > 100 OR u.UpVotes > 10)
        AND u.Id NOT IN (
            SELECT UserId 
            FROM Votes 
            WHERE VoteTypeId IN (4, 12) 
                AND UserId IS NOT NULL
            GROUP BY UserId 
            HAVING COUNT(*) > 5
        )
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
    HAVING COUNT(DISTINCT p.Id) > 0
),
badge_aggregates AS (
    SELECT 
        b.UserId,
        COUNT(*) AS total_badges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
        -- For broad SQL compatibility: use LISTAGG or STRING_AGG depending on dialect. Keep STRING_AGG for engines that support it.
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS gold_badge_names,
        MAX(b.Date) AS last_badge_date,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS tag_based_badge_count
    FROM Badges b
    WHERE b.Date >= DATE '2019-01-01'
    GROUP BY b.UserId
),
post_engagement_stats AS (
    SELECT 
        p.Id AS post_id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        COALESCE(p.CommentCount, 0) + COALESCE(p.AnswerCount, 0) AS total_engagement,
        CASE 
            WHEN p.ViewCount > 10000 THEN 'Viral'
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Moderate'
            ELSE 'Low'
        END AS engagement_tier,
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.PostId = p.Id 
           AND c.Score > 0
           AND (c.Text LIKE '%thank%' OR c.Text LIKE '%great%')
        ) AS positive_comment_count,
        (SELECT AVG(EXTRACT(EPOCH FROM (v.CreationDate - p.CreationDate)))
         FROM Votes v
         WHERE v.PostId = p.Id 
           AND v.VoteTypeId = 2
           AND v.CreationDate IS NOT NULL
        ) AS avg_time_to_upvote_seconds,
        EXISTS(
            SELECT 1 
            FROM PostLinks pl 
            WHERE pl.PostId = p.Id 
              AND pl.LinkTypeId = 3
        ) AS is_duplicate
    FROM Posts p
    WHERE p.CreationDate >= DATE '2019-01-01'
        AND p.OwnerUserId IS NOT NULL
        AND (p.ClosedDate IS NULL OR p.ClosedDate > p.CreationDate + INTERVAL '30 days')
),
tag_expertise AS (
    SELECT 
        p.OwnerUserId AS OwnerUserId,
        tag AS tag_name,
        COUNT(*) AS tag_usage_count,
        AVG(p.Score) AS avg_tag_score,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.Score) AS percentile_75_score
    FROM Posts p,
    LATERAL (
      SELECT UNNEST(string_to_array(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '|')) AS tag
    ) t
    WHERE p.PostTypeId = 1 
        AND p.Tags IS NOT NULL 
        AND LENGTH(p.Tags) > 2
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, tag
    HAVING COUNT(*) >= 5
)
SELECT 
    uam.DisplayName,
    COALESCE(uam.Location, 'N/A') AS user_location,
    uam.Reputation,
    uam.post_count,
    uam.question_count,
    uam.answer_count,
    ROUND(CAST(uam.avg_post_score AS numeric), 2) AS avg_score,
    ROUND((CAST(uam.questions_with_accepted_answers AS numeric) / NULLIF(uam.question_count, 0) * 100), 2) AS acceptance_rate,
    COALESCE(ba.total_badges, 0) AS total_badges,
    CONCAT(COALESCE(ba.gold_badges, 0), 'G/', COALESCE(ba.silver_badges, 0), 'S/', COALESCE(ba.bronze_badges, 0), 'B') AS badge_breakdown,
    ba.gold_badge_names,
    COALESCE(ba.tag_based_badge_count, 0) AS tag_based_badge_count,
    COUNT(DISTINCT pes.post_id) AS engaged_posts,
    AVG(pes.total_engagement) AS avg_engagement_per_post,
    STRING_AGG(DISTINCT pes.engagement_tier, ', ') AS engagement_tiers,
    SUM(CASE WHEN pes.is_duplicate THEN 1 ELSE 0 END) AS duplicate_posts,
    (SELECT STRING_AGG(te.tag_name, ', ' ORDER BY te.tag_usage_count DESC)
     FROM (SELECT tag_name, tag_usage_count 
           FROM tag_expertise te2 
           WHERE te2.OwnerUserId = uam.Id 
           ORDER BY tag_usage_count DESC 
           LIMIT 5) te) AS top_5_tags,
    MAX(te.percentile_75_score) AS best_tag_p75_score,
    uam.location_rank,
    uam.overall_post_rank,
    EXTRACT(YEAR FROM (DATE '2024-10-01' - uam.CreationDate)) AS account_age_years
FROM user_activity_metrics uam
LEFT JOIN badge_aggregates ba ON uam.Id = ba.UserId
LEFT JOIN post_engagement_stats pes ON uam.Id = pes.OwnerUserId
LEFT JOIN tag_expertise te ON uam.Id = te.OwnerUserId
WHERE uam.location_rank <= 10
    AND (COALESCE(ba.total_badges, 0) >= 5 OR uam.Reputation > 1000)
    AND NOT EXISTS (
        SELECT 1 
        FROM PostHistory ph 
        WHERE ph.UserId = uam.Id 
          AND ph.PostHistoryTypeId = 12
        GROUP BY ph.UserId
        HAVING COUNT(*) > 3
    )
GROUP BY 
    uam.Id,
    uam.DisplayName, 
    uam.Location, 
    uam.Reputation, 
    uam.post_count,
    uam.question_count,
    uam.answer_count,
    uam.avg_post_score,
    uam.questions_with_accepted_answers,
    ba.total_badges,
    ba.gold_badges,
    ba.silver_badges,
    ba.bronze_badges,
    ba.gold_badge_names,
    ba.tag_based_badge_count,
    uam.location_rank,
    uam.overall_post_rank,
    uam.CreationDate
HAVING COUNT(DISTINCT pes.post_id) >= 3
    AND AVG(pes.total_engagement) > 2
ORDER BY 
    uam.Reputation DESC,
    ba.total_badges DESC,
    uam.overall_post_rank ASC
LIMIT 100;