-- {"query": "21081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1303} 

WITH active_users AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) as rep_rank
    FROM Users u
    WHERE u.Reputation > 1000
      AND u.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
      AND u.Location IS NOT NULL
      AND LENGTH(u.Location) > 5
),
top_posts AS (
    SELECT p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount,
           p.OwnerUserId,
           COALESCE(p.Score, 0) * LOG(GREATEST(p.ViewCount, 1)) + COALESCE(p.AnswerCount, 0) * 10 as engagement_score,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as post_seq
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score > 0
      AND p.ClosedDate IS NULL
      AND p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '6 months'
),
user_stats AS (
    SELECT au.Id as user_id,
           au.DisplayName,
           au.rep_rank,
           COUNT(tp.Id) as total_questions,
           SUM(CASE WHEN tp.engagement_score > 100 THEN 1 ELSE 0 END) as high_engagement_count,
           AVG(tp.engagement_score) as avg_engagement,
           MAX(tp.engagement_score) as max_engagement,
           STRING_AGG(tp.Title, ' || ' ORDER BY tp.CreationDate DESC) as recent_titles
    FROM active_users au
    LEFT JOIN top_posts tp ON au.Id = tp.OwnerUserId AND tp.post_seq <= 5
    GROUP BY au.Id, au.DisplayName, au.rep_rank
    HAVING COUNT(tp.Id) > 0
),
badge_insights AS (
    SELECT b.UserId,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) as gold_badges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) as silver_badges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) as bronze_badges,
           STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Date DESC) as top_badges
    FROM Badges b
    WHERE b.Date > CURRENT_TIMESTAMP - INTERVAL '1 year'
      AND b.TagBased = false
    GROUP BY b.UserId
),
comment_activity AS (
    SELECT c.UserId,
           COUNT(c.Id) as comment_count,
           AVG(c.Score) as avg_comment_score,
           SUM(CASE WHEN LENGTH(c.Text) > 200 THEN 1 ELSE 0 END) as detailed_comments
    FROM Comments c
    WHERE c.UserId IS NOT NULL
      AND c.CreationDate > CURRENT_TIMESTAMP - INTERVAL '3 months'
    GROUP BY c.UserId
)
SELECT us.user_id,
       us.DisplayName,
       us.rep_rank,
       us.total_questions,
       us.high_engagement_count,
       ROUND(us.avg_engagement, 2) as avg_engagement,
       us.max_engagement,
       us.recent_titles,
       COALESCE(bi.gold_badges, 0) as gold_badges,
       COALESCE(bi.silver_badges, 0) as silver_badges,
       COALESCE(bi.bronze_badges, 0) as bronze_badges,
       COALESCE(bi.top_badges, 'None') as top_badges,
       COALESCE(ca.comment_count, 0) as comment_count,
       COALESCE(ca.detailed_comments, 0) as detailed_comments,
       CASE 
           WHEN us.high_engagement_count >= 3 AND COALESCE(bi.gold_badges, 0) >= 1 THEN 'Elite Contributor'
           WHEN us.total_questions >= 10 OR us.rep_rank <= 100 THEN 'Active Poster'
           WHEN COALESCE(ca.comment_count, 0) >= 20 THEN 'Comment Enthusiast'
           ELSE 'Emerging User'
       END as user_category,
       (COALESCE(bi.gold_badges, 0) * 10 + COALESCE(bi.silver_badges, 0) * 5 + COALESCE(bi.bronze_badges, 0) * 1 + us.high_engagement_count * 2 + COALESCE(ca.detailed_comments, 0)) as composite_score
FROM user_stats us
LEFT JOIN badge_insights bi ON us.user_id = bi.UserId
LEFT JOIN comment_activity ca ON us.user_id = ca.UserId
WHERE us.total_questions >= 2
  AND (us.rep_rank <= 500 OR us.high_engagement_count > 0)
UNION ALL
SELECT NULL as user_id,
       'Community Aggregate' as DisplayName,
       NULL as rep_rank,
       COUNT(DISTINCT us.user_id) as total_questions,
       SUM(us.high_engagement_count) as high_engagement_count,
       AVG(us.avg_engagement) as avg_engagement,
       MAX(us.max_engagement) as max_engagement,
       NULL as recent_titles,
       SUM(COALESCE(bi.gold_badges, 0)) as gold_badges,
       SUM(COALESCE(bi.silver_badges, 0)) as silver_badges,
       SUM(COALESCE(bi.bronze_badges, 0)) as bronze_badges,
       NULL as top_badges,
       SUM(COALESCE(ca.comment_count, 0)) as comment_count,
       SUM(COALESCE(ca.detailed_comments, 0)) as detailed_comments,
       'Overall Community' as user_category,
       SUM((COALESCE(bi.gold_badges, 0) * 10 + COALESCE(bi.silver_badges, 0) * 5 + COALESCE(bi.bronze_badges, 0) * 1 + us.high_engagement_count * 2 + COALESCE(ca.detailed_comments, 0))) as composite_score
FROM user_stats us
LEFT JOIN badge_insights bi ON us.user_id = bi.UserId
LEFT JOIN comment_activity ca ON us.user_id = ca.UserId
ORDER BY composite_score DESC NULLS LAST, rep_rank ASC;
