WITH active_users AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
    FROM Users u
    WHERE u.Reputation > 1000
      AND u.LastAccessDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
),
question_stats AS (
    SELECT p.Id AS post_id, p.OwnerUserId, p.CreationDate,
           p.Score, p.ViewCount, p.AnswerCount,
           COALESCE(p.CommentCount, 0) AS comment_count,
           LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
           AVG(p.Score) OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate)) AS monthly_avg_score,
           COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS edit_count
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId 
        AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE p.PostTypeId = 1
      AND p.Score > 0
      AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '2 years')
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, 
             p.AnswerCount, p.CommentCount
    HAVING COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) = 0
),
top_interactions AS (
    SELECT qs.post_id, qs.OwnerUserId, 
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
           SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_count,
           COUNT(DISTINCT c.Id) AS comment_count,
           STRING_AGG(
               CASE 
                   WHEN pl.LinkTypeId = 1 THEN 'Linked: ' || COALESCE(rp.Title, 'Unknown')
                   WHEN pl.LinkTypeId = 3 THEN 'Duplicate: ' || COALESCE(rp.Title, 'Unknown')
                   ELSE 'Other: ' || CAST(pl.LinkTypeId AS varchar)
               END, 
               '; ' ORDER BY pl.CreationDate
           ) AS link_descriptions
    FROM question_stats qs
    LEFT JOIN Votes v ON qs.post_id = v.PostId 
        AND v.VoteTypeId IN (1, 2, 3)
    LEFT JOIN Comments c ON qs.post_id = c.PostId 
        AND c.Score >= 0
        AND LENGTH(TRIM(c.Text)) > 10
    LEFT JOIN PostLinks pl ON qs.post_id = pl.PostId
    LEFT JOIN Posts rp ON pl.RelatedPostId = rp.Id
    WHERE qs.AnswerCount > 0
    GROUP BY qs.post_id, qs.OwnerUserId
    HAVING SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) + 5
),
badge_analysis AS (
    SELECT au.Id AS user_id, au.DisplayName,
           COUNT(b.Id) AS total_badges,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
           MAX(b.Date) AS latest_badge_date,
           AVG(EXTRACT(DAY FROM (b.Date - u.CreationDate))) AS avg_days_to_badge
    FROM active_users au
    JOIN Users u ON au.Id = u.Id
    LEFT JOIN Badges b ON au.Id = b.UserId
        AND b.Date >= u.CreationDate
    WHERE b.TagBased IS NOT NULL
    GROUP BY au.Id, au.DisplayName, u.CreationDate
)
SELECT 
    au.DisplayName AS user_name,
    au.rep_rank,
    COALESCE(ti.upvotes, 0) AS total_upvotes,
    COALESCE(ti.downvotes, 0) AS total_downvotes,
    COALESCE(qs.edit_count, 0) AS total_edits,
    ba.total_badges,
    ba.gold_badges,
    (COALESCE(ti.upvotes, 0) * 1.0 / NULLIF(COALESCE(ti.downvotes, 0), 0)) AS upvote_ratio,
    CASE 
        WHEN ba.gold_badges > 0 THEN 'Elite'
        WHEN ba.silver_badges > 5 THEN 'Veteran'
        WHEN ba.total_badges > 10 THEN 'Active'
        ELSE 'Novice'
    END AS user_tier,
    SUBSTRING(
        COALESCE(ti.link_descriptions, 
                 'No significant links; tags: ' || 
                 COALESCE(CAST(qs.post_id AS varchar), 'N/A')), 
        1, 100
    ) AS interaction_summary,
    RANK() OVER (
        ORDER BY (COALESCE(ti.upvotes, 0) + COALESCE(qs.edit_count, 0) * 2 + COALESCE(ba.gold_badges, 0) * 10) DESC
    ) AS overall_engagement_rank
FROM active_users au
LEFT JOIN question_stats qs ON au.Id = qs.OwnerUserId
LEFT JOIN top_interactions ti ON qs.post_id = ti.post_id
LEFT JOIN badge_analysis ba ON au.Id = ba.user_id
WHERE au.rep_rank <= 100
  AND (COALESCE(ti.upvotes, 0) > 50 OR COALESCE(ba.gold_badges, 0) > 0 OR COALESCE(qs.edit_count, 0) > 20)
  AND (ba.latest_badge_date IS NULL OR ba.latest_badge_date >= (CAST('2024-10-01' AS DATE) - INTERVAL '6 months'))
ORDER BY overall_engagement_rank
LIMIT 50;