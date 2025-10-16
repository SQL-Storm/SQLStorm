-- {"query": "214.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4343} 
WITH
recent_posts AS (
  SELECT p.*,
    COALESCE(p.ViewCount,0) AS vc,
    COALESCE(p.Score,0) AS sc,
    CASE WHEN p.PostTypeId=1 THEN 'Question' WHEN p.PostTypeId=2 THEN 'Answer' ELSE 'Other' END AS post_type,
    array_length(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><'),1) AS tag_count
  FROM Posts p
  WHERE p.CreationDate >= now() - interval '5 years'
),
user_stats AS (
  SELECT u.Id, u.DisplayName,
    u.Reputation,
    COALESCE(u.Views,0) AS profile_views,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId=1) AS q_count,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId=2) AS a_count,
    SUM(CASE WHEN p.PostTypeId IN (1,2) THEN COALESCE(p.Score,0) ELSE 0 END) AS total_post_score,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS rep_rank
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
top_tags AS (
  SELECT t.TagName, t.Count,
    COALESCE(t.ExcerptPostId,0) AS excerpt_post_id,
    COALESCE(t.WikiPostId,0) AS wiki_post_id,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE t.Count > 0
),
post_metrics AS (
  SELECT p.Id,
    p.Title,
    p.OwnerUserId,
    p.PostTypeId,
    p.CreationDate,
    COALESCE(p.Score,0) AS score,
    COALESCE(p.ViewCount,0) AS views,
    COALESCE(p.AnswerCount,0) AS answer_count,
    COALESCE(p.FavoriteCount,0) AS favorites,
    (COALESCE(p.Score,0) * 3 + COALESCE(p.ViewCount,0) / GREATEST(NULLIF(p.AnswerCount,0),1) + COALESCE(p.FavoriteCount,0) * 5) AS popularity,
    CASE WHEN p.Tags IS NOT NULL THEN split_part(substring(p.Tags from 2 for length(p.Tags)-2), '><',1) ELSE NULL END AS first_tag,
    COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id),0) AS comment_count,
    COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2),0) AS upvotes,
    COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3),0) AS downvotes
  FROM Posts p
),
answer_depth AS (
  SELECT q.Id AS question_id, q.Title, q.OwnerUserId AS question_owner, q.CreationDate,
    COUNT(a.Id) AS answer_count,
    MAX(a.Score) AS best_answer_score,
    AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS avg_answer_score,
    SUM(CASE WHEN a.OwnerUserId = q.OwnerUserId THEN 1 ELSE 0 END) AS self_answer_count
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  WHERE q.PostTypeId = 1
  GROUP BY q.Id, q.Title, q.OwnerUserId, q.CreationDate
),
badge_impact AS (
  SELECT b.UserId,
    COUNT(*) AS badge_count,
    SUM(CASE WHEN b.Class=1 THEN 3 WHEN b.Class=2 THEN 2 ELSE 1 END) AS badge_weight,
    MAX(b.Date) AS last_badge_date
  FROM Badges b
  GROUP BY b.UserId
),
recent_activity AS (
  SELECT ph.PostId,
    MAX(ph.CreationDate) AS last_history,
    COUNT(*) AS history_count,
    BOOL_OR(ph.PostHistoryTypeId IN (10,12,24,50)) AS volatile_flag
  FROM PostHistory ph
  GROUP BY ph.PostId
),
linked_matrix AS (
  SELECT pl.PostId, pl.RelatedPostId, pl.LinkTypeId,
    SUM(CASE WHEN lt.Name IS NULL THEN 0 ELSE 1 END) OVER (PARTITION BY pl.PostId) AS related_count_for_post
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
),
user_ranked_posts AS (
  SELECT p.OwnerUserId, p.Id, p.Title, p.CreationDate, p.Score,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST, p.CreationDate DESC) AS user_rank
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
)
SELECT
  u.Id AS user_id,
  u.DisplayName AS user_name,
  u.Reputation,
  us.q_count,
  us.a_count,
  COALESCE(bi.badge_count,0) AS badge_count,
  COALESCE(bi.badge_weight,0) AS badge_weight,
  SUM(pm.views) FILTER (WHERE pm.PostTypeId = 1) AS total_question_views,
  SUM(pm.views) FILTER (WHERE pm.PostTypeId = 2) AS total_answer_views,
  AVG(pm.score) AS avg_post_score,
  MAX(pm.popularity) AS max_post_popularity,
  COALESCE(NULLIF(SUM(pm.comment_count),0),0) / NULLIF(GREATEST(COUNT(pm.Id),1),1) AS avg_comments_per_post,
  COUNT(DISTINCT CASE WHEN ad.answer_count > 0 AND ad.avg_answer_score >= 2 THEN ad.question_id END) AS high_quality_question_count,
  CASE
    WHEN u.Location IS NULL OR trim(u.Location) = '' THEN 'Unknown'
    WHEN u.Location ILIKE '%United%' THEN 'International'
    ELSE left(u.Location, 30)
  END AS location_bucket,
  COALESCE(EXTRACT(EPOCH FROM (now() - GREATEST(COALESCE(bi.last_badge_date, '1970-01-01'::timestamp), COALESCE(ra.last_history,'1970-01-01'::timestamp) )) )/86400, NULL) AS days_since_last_highlight,
  (SELECT split_part(substring(t.Tags from 2 for length(t.Tags)-2), '><',1)
   FROM Posts t
   WHERE t.OwnerUserId = u.Id AND t.PostTypeId = 1 AND t.Tags IS NOT NULL
   ORDER BY t.CreationDate DESC LIMIT 1) AS latest_first_tag,
  MIN(ur.user_rank) FILTER (WHERE ur.user_rank <= 3) AS top3_posts_count,
  CASE WHEN EXISTS (SELECT 1 FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) THEN true ELSE false END AS ever_upvoted,
  CASE WHEN COALESCE(bi.badge_weight,0) >= 3 AND EXISTS (SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.Score >= 10) THEN 'star-contributor' ELSE NULL END AS special_label
FROM Users u
LEFT JOIN user_stats us ON us.Id = u.Id
LEFT JOIN badge_impact bi ON bi.UserId = u.Id
LEFT JOIN post_metrics pm ON pm.OwnerUserId = u.Id
LEFT JOIN recent_activity ra ON ra.PostId = pm.Id
LEFT JOIN answer_depth ad ON ad.question_owner = u.Id
LEFT JOIN user_ranked_posts ur ON ur.OwnerUserId = u.Id
WHERE u.Reputation >= 500
GROUP BY u.Id, u.DisplayName, u.Reputation, us.q_count, us.a_count, bi.badge_count, bi.badge_weight, bi.last_badge_date, ra.last_history, u.Location
HAVING (SUM(pm.views) FILTER (WHERE pm.PostTypeId = 1) > 1000 OR COUNT(DISTINCT pm.Id) > 5)
ORDER BY u.Reputation DESC NULLS LAST, max_post_popularity DESC
LIMIT 200;