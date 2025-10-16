WITH RECURSIVE user_activity_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS net_votes,
        EXTRACT(YEAR FROM u.CreationDate) AS join_year,
        CASE 
            WHEN u.Location IS NOT NULL AND LENGTH(TRIM(u.Location)) > 0 
            THEN UPPER(SUBSTRING(u.Location FROM 1 FOR 2))
            ELSE 'UN'
        END AS location_code
    FROM Users u
    WHERE u.Reputation > 1000
),
post_engagement_cte AS (
    SELECT 
        p.Id AS post_id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COALESCE(p.FavoriteCount, 0) AS favorites,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 
            ELSE 0 
        END AS has_accepted_answer,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS user_post_rank,
        DENSE_RANK() OVER (ORDER BY CAST(p.CreationDate AS DATE)) AS post_day_rank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS user_avg_score,
        NULL AS median_views_by_year,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= CAST('2015-01-01' AS TIMESTAMP)
        AND (p.ClosedDate IS NULL OR p.ClosedDate > p.CreationDate + INTERVAL '7' DAY)
),
median_views_by_year_calc AS (
    SELECT
        year,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY viewcount) AS median_views
    FROM (
        SELECT EXTRACT(YEAR FROM CreationDate) AS year, COALESCE(ViewCount, 0) AS viewcount
        FROM Posts
        WHERE CreationDate >= CAST('2015-01-01' AS TIMESTAMP)
          AND PostTypeId IN (1,2)
    ) t
    GROUP BY year
),
post_engagement_with_median AS (
    SELECT
        pe.post_id,
        pe.OwnerUserId,
        pe.PostTypeId,
        pe.Score,
        pe.ViewCount,
        pe.AnswerCount,
        pe.CommentCount,
        pe.favorites,
        pe.has_accepted_answer,
        pe.user_post_rank,
        pe.post_day_rank,
        pe.user_avg_score,
        mv.median_views,
        pe.CreationDate
    FROM post_engagement_cte pe
    LEFT JOIN median_views_by_year_calc mv
        ON mv.year = EXTRACT(YEAR FROM pe.CreationDate)
),
tag_expert_scores AS (
    SELECT 
        p.OwnerUserId,
        tag_name,
        COUNT(*) AS tag_post_count,
        SUM(p.Score) AS total_tag_score,
        AVG(COALESCE(p.ViewCount, 0)) AS avg_tag_views
    FROM Posts p,
         UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS tag_name
    WHERE p.PostTypeId = 1 
        AND p.Tags IS NOT NULL
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, tag_name
    HAVING COUNT(*) >= 5
),
vote_patterns AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvote_count,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvote_count,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS favorite_count,
        MAX(v.CreationDate) AS last_vote_date,
        STRING_AGG(DISTINCT vt.Name, '; ' ORDER BY vt.Name) AS vote_types
    FROM Votes v
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.CreationDate >= CAST('2018-01-01' AS TIMESTAMP)
    GROUP BY v.PostId
),
badge_tiers AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badges,
        COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS tag_badges,
        MAX(CASE WHEN b.Class = 1 THEN b.Date END) AS first_gold_date
    FROM Badges b
    GROUP BY b.UserId
    HAVING COUNT(CASE WHEN b.Class IN (1, 2) THEN 1 END) > 0
)
SELECT 
    uam.DisplayName,
    uam.Reputation,
    uam.location_code,
    COALESCE(bt.gold_badges, 0) + COALESCE(bt.silver_badges, 0) * 0.5 + COALESCE(bt.bronze_badges, 0) * 0.1 AS weighted_badge_score,
    pe.post_id,
    pe.Score AS post_score,
    pe.user_post_rank,
    ROUND(CAST(pe.user_avg_score AS numeric), 2) AS user_avg_post_score,
    CASE 
        WHEN pe.ViewCount > COALESCE(pe.median_views, 0) THEN 'Above Median'
        WHEN pe.ViewCount IS NULL THEN 'No Views'
        ELSE 'Below Median'
    END AS view_performance,
    tes.tag_name AS expert_tag,
    tes.total_tag_score,
    COALESCE(vp.upvote_count, 0) AS post_upvotes,
    COALESCE(vp.downvote_count, 0) AS post_downvotes,
    ROUND(
        CASE 
            WHEN COALESCE(vp.upvote_count, 0) + COALESCE(vp.downvote_count, 0) > 0
            THEN (CAST(COALESCE(vp.upvote_count, 0) AS numeric) / NULLIF(COALESCE(vp.upvote_count, 0) + COALESCE(vp.downvote_count, 0), 0)) * 100
            ELSE NULL
        END, 2
    ) AS upvote_percentage,
    (
        SELECT COUNT(DISTINCT c.Id)
        FROM Comments c
        WHERE c.PostId = pe.post_id
            AND c.Score > 0
            AND c.UserId != uam.Id
    ) AS valuable_comments_from_others,
    (
        SELECT STRING_AGG(DISTINCT pht.Name, ', ' ORDER BY pht.Name)
        FROM PostHistory ph
        JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
        WHERE ph.PostId = pe.post_id
            AND ph.PostHistoryTypeId IN (4, 5, 6)
        LIMIT 5
    ) AS edit_types,
    EXISTS(
        SELECT 1 
        FROM PostLinks pl
        WHERE pl.PostId = pe.post_id 
            AND pl.LinkTypeId = 3
    ) AS is_duplicate_target,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - uam.CreationDate)) / 86400.0 AS days_since_joined,
    ROUND(CAST(uam.Reputation AS numeric) / NULLIF(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - uam.CreationDate)) / 86400.0, 0), 2) AS rep_per_day
FROM user_activity_metrics uam
INNER JOIN post_engagement_with_median pe ON uam.Id = pe.OwnerUserId
LEFT OUTER JOIN tag_expert_scores tes ON uam.Id = tes.OwnerUserId AND tes.tag_post_count = (
    SELECT MAX(tes2.tag_post_count)
    FROM tag_expert_scores tes2
    WHERE tes2.OwnerUserId = uam.Id
)
LEFT OUTER JOIN badge_tiers bt ON uam.Id = bt.UserId
LEFT OUTER JOIN vote_patterns vp ON pe.post_id = vp.PostId
WHERE pe.user_post_rank <= 10
    AND uam.net_votes > 0
    AND (COALESCE(bt.gold_badges,0) > 0 OR uam.Reputation > 5000)
    AND pe.Score >= CASE 
        WHEN pe.PostTypeId = 1 THEN 5 
        WHEN pe.PostTypeId = 2 THEN 3 
        ELSE 0 
    END
    AND NOT EXISTS (
        SELECT 1 
        FROM Posts p2 
        WHERE p2.ParentId = pe.post_id 
            AND p2.Score < -5
    )
ORDER BY 
    weighted_badge_score DESC,
    rep_per_day DESC,
    pe.user_avg_score DESC,
    COALESCE(vp.upvote_count, 0) DESC
LIMIT 500;