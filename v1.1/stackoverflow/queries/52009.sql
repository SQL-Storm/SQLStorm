WITH user_posts AS (
  SELECT OwnerUserId, PostTypeId, COUNT(*) AS cnt, SUM(Score) AS total_score, SUM(COALESCE(ViewCount, 0)) AS total_views, AVG(Score) AS avg_score
  FROM Posts
  WHERE OwnerUserId IS NOT NULL
  GROUP BY OwnerUserId, PostTypeId
),
user_comments AS (
  SELECT UserId, COUNT(*) AS comment_cnt, SUM(Score) AS total_comment_score, MAX(CreationDate) AS last_comment_date
  FROM Comments
  WHERE UserId IS NOT NULL
  GROUP BY UserId
),
user_votes_received AS (
  SELECT p.OwnerUserId, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS net_votes_received,
         COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes_received, COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes_received
  FROM Votes v
  JOIN Posts p ON v.PostId = p.Id
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
),
user_badges AS (
  SELECT UserId, COUNT(*) AS badge_cnt, SUM(CASE WHEN Class = 1 THEN 10 WHEN Class = 2 THEN 5 ELSE 1 END) AS badge_weight
  FROM Badges
  GROUP BY UserId
),
tag_usage AS (
  -- convert tags like '<tag1><tag2>' into rows without relying on postgres-specific array literal operator
  SELECT tag, OwnerUserId, COUNT(*) AS tag_posts
  FROM (
    SELECT OwnerUserId,
           TRIM(tag) AS tag
    FROM Posts p
    CROSS JOIN LATERAL (
      -- replace angle brackets with a separator and split using standard string functions
      SELECT regexp_split_to_table(
               regexp_replace(Tags, '^<|>$', '', 'g'),
               '><'
             ) AS tag
    ) s
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
  ) sub
  GROUP BY tag, OwnerUserId
),
user_tag_diversity AS (
  SELECT OwnerUserId, COUNT(DISTINCT tag) AS unique_tags, SUM(tag_posts) AS total_tag_posts
  FROM tag_usage
  GROUP BY OwnerUserId
)
SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
  COALESCE(q.cnt, 0) AS question_count,
  COALESCE(q.total_score, 0) AS question_score_sum,
  COALESCE(q.total_views, 0) AS question_view_sum,
  COALESCE(q.avg_score, 0) AS avg_question_score,
  COALESCE(a.cnt, 0) AS answer_count,
  COALESCE(a.total_score, 0) AS answer_score_sum,
  COALESCE(c.comment_cnt, 0) AS comment_count,
  COALESCE(c.total_comment_score, 0) AS comment_score_sum,
  COALESCE(vr.net_votes_received, 0) AS net_votes_received,
  COALESCE(vr.upvotes_received, 0) AS upvotes_received,
  COALESCE(vr.downvotes_received, 0) AS downvotes_received,
  COALESCE(b.badge_cnt, 0) AS badge_count,
  COALESCE(b.badge_weight, 0) AS badge_weight,
  COALESCE(td.unique_tags, 0) AS unique_tags_used,
  COALESCE(td.total_tag_posts, 0) AS total_tag_posts,
  (u.Reputation * 1.0 +
   COALESCE(q.total_score, 0) * 10.0 +
   COALESCE(a.total_score, 0) * 5.0 +
   COALESCE(c.comment_cnt, 0) * 1.0 +
   COALESCE(b.badge_weight, 0) * 100.0 +
   COALESCE(vr.net_votes_received, 0) * 2.0 +
   COALESCE(td.unique_tags, 0) * 50.0) AS comprehensive_activity_score
FROM Users u
LEFT JOIN user_posts q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1
LEFT JOIN user_posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
LEFT JOIN user_comments c ON u.Id = c.UserId
LEFT JOIN user_votes_received vr ON u.Id = vr.OwnerUserId
LEFT JOIN user_badges b ON u.Id = b.UserId
LEFT JOIN user_tag_diversity td ON u.Id = td.OwnerUserId
WHERE u.Reputation > 0
GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
         q.cnt, q.total_score, q.total_views, q.avg_score, q.OwnerUserId, q.PostTypeId,
         a.cnt, a.total_score, a.OwnerUserId, a.PostTypeId,
         c.comment_cnt, c.total_comment_score, c.UserId,
         vr.net_votes_received, vr.upvotes_received, vr.downvotes_received, vr.OwnerUserId,
         b.badge_cnt, b.badge_weight, b.UserId,
         td.unique_tags, td.total_tag_posts, td.OwnerUserId
ORDER BY comprehensive_activity_score DESC, u.Reputation DESC
LIMIT 500;