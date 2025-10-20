WITH user_activity_metrics AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS post_count,
    COUNT(DISTINCT c.Id) AS comment_count,
    COUNT(DISTINCT b.Id) AS badge_count,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS question_score,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS answer_score,
    ROW_NUMBER() OVER (PARTITION BY SUBSTRING(COALESCE(u.Location, 'Unknown'), 1, 20) ORDER BY u.Reputation DESC) AS location_rank,
    PERCENT_RANK() OVER (ORDER BY u.Reputation) AS reputation_percentile
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN Comments c ON u.Id = c.UserId
  LEFT JOIN Badges b ON u.Id = b.UserId
  WHERE u.CreationDate >= TIMESTAMP '2015-01-01'
    AND (u.Location IS NULL OR LENGTH(TRIM(u.Location)) > 0)
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
  HAVING COUNT(DISTINCT p.Id) > 5 OR COUNT(DISTINCT c.Id) > 10
),
post_engagement AS (
  SELECT 
    p.Id AS post_id,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    COALESCE(p.CommentCount, 0) AS comment_count,
    LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_score,
    LEAD(p.ViewCount, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_post_views,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 3 PRECEDING AND 3 FOLLOWING) AS rolling_avg_score,
    (SELECT COUNT(*) 
     FROM PostLinks pl 
     WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS duplicate_count,
    (SELECT STRING_AGG(DISTINCT vt.Name, ', ')
     FROM Votes v
     INNER JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
     WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3, 4, 12)) AS vote_types
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= TIMESTAMP '2016-01-01'
    AND (p.Score > 5 OR p.ViewCount > 1000)
),
tag_analysis AS (
  SELECT 
    t.TagName,
    t.Count,
    COUNT(DISTINCT p.Id) AS tagged_posts,
    AVG(p.Score) AS avg_post_score,
    MAX(p.ViewCount) AS max_views,
    COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS posts_with_accepted_answer,
    NTILE(10) OVER (ORDER BY t.Count DESC) AS popularity_decile
  FROM Tags t
  INNER JOIN Posts p ON ('<' || t.TagName || '>') = ANY(
    STRING_TO_ARRAY(p.Tags, '><')
  )
  WHERE t.Count > 100
    AND p.PostTypeId = 1
    AND t.IsModeratorOnly = FALSE
  GROUP BY t.Id, t.TagName, t.Count
)
SELECT 
  uam.DisplayName,
  COALESCE(NULLIF(SUBSTRING(uam.Location, 1, 30), ''), 'No Location') AS trimmed_location,
  uam.Reputation,
  uam.post_count,
  uam.comment_count,
  uam.badge_count,
  ROUND(CAST(uam.reputation_percentile AS numeric), 4) AS rep_percentile,
  pe.Title AS recent_post_title,
  pe.Score AS post_score,
  CASE 
    WHEN pe.Score > pe.prev_post_score THEN 'Improving'
    WHEN pe.Score < pe.prev_post_score THEN 'Declining'
    WHEN pe.prev_post_score = 0 THEN 'First Post'
    ELSE 'Stable'
  END AS score_trend,
  COALESCE(pe.vote_types, 'No Votes') AS engagement_types,
  pe.rolling_avg_score,
  ta.TagName AS primary_tag,
  ta.popularity_decile,
  (SELECT COUNT(*) 
   FROM PostHistory ph 
   WHERE ph.PostId = pe.post_id 
     AND ph.PostHistoryTypeId IN (4, 5, 6)
     AND ph.UserId != pe.OwnerUserId) AS external_edits,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM Badges b 
      WHERE b.UserId = uam.Id 
        AND b.Class = 1
        AND b.Date >= TIMESTAMP '2018-01-01'
    ) THEN 'Gold Badge Holder'
    WHEN uam.reputation_percentile > 0.95 THEN 'Top 5%'
    WHEN uam.reputation_percentile > 0.75 THEN 'Top 25%'
    ELSE 'Standard'
  END AS user_tier,
  (uam.question_score + uam.answer_score * 2.0) / NULLIF(uam.post_count, 0) AS weighted_quality_score
FROM user_activity_metrics uam
INNER JOIN post_engagement pe ON uam.Id = pe.OwnerUserId
LEFT JOIN tag_analysis ta ON ta.popularity_decile <= 3
WHERE uam.location_rank <= 10
  AND pe.comment_count > 2
  AND (pe.duplicate_count = 0 OR pe.duplicate_count IS NULL)
  AND NOT EXISTS (
    SELECT 1 FROM Votes v
    WHERE v.PostId = pe.post_id
      AND v.VoteTypeId IN (4, 12)
      AND v.CreationDate >= TIMESTAMP '1970-01-01'
  )
  AND (pe.next_post_views IS NULL OR pe.next_post_views > pe.ViewCount * 0.5)
GROUP BY uam.Id, uam.DisplayName, uam.Location, uam.Reputation, uam.post_count, 
         uam.comment_count, uam.badge_count, uam.reputation_percentile, uam.question_score,
         uam.answer_score, pe.Title, pe.post_id, pe.Score, pe.prev_post_score, 
         pe.vote_types, pe.rolling_avg_score, pe.OwnerUserId, pe.ViewCount, 
         pe.next_post_views, ta.TagName, ta.popularity_decile
HAVING (uam.question_score + uam.answer_score * 2.0) / NULLIF(uam.post_count, 0) > 3.0
ORDER BY weighted_quality_score DESC, 
         uam.reputation_percentile DESC,
         pe.rolling_avg_score DESC
LIMIT 500;