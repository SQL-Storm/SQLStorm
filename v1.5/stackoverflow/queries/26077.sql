WITH 
  avg_reputation AS (
    SELECT AVG(u.Reputation) AS avg_rep
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
  ),
  top_tags AS (
    SELECT t.TagName, COUNT(*) AS question_count
    FROM Tags t
    JOIN Posts p ON p.PostTypeId = 1
    WHERE p.Tags IS NOT NULL
    GROUP BY t.TagName
    ORDER BY question_count DESC
    LIMIT 10
  ),
  post_votes AS (
    SELECT p.Id, 
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id
  ),
  top_posts AS (
    SELECT p.Id, p.Title, pv.upvotes, pv.downvotes
    FROM Posts p
    JOIN post_votes pv ON p.Id = pv.Id
    ORDER BY pv.upvotes DESC, pv.downvotes DESC
    LIMIT 10
  ),
  user_avg_score AS (
    SELECT u.Id, AVG(p.Score) AS avg_score
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id
  )
SELECT 
  u.Id, 
  u.DisplayName, 
  u.Reputation, 
  COALESCE(uas.avg_score, 0) AS avg_score,
  COALESCE(tp.Title, 'No top post') AS top_post_title,
  COALESCE(tp.upvotes, 0) AS top_post_upvotes,
  COALESCE(tp.downvotes, 0) AS top_post_downvotes,
  COALESCE(tt.TagName, 'No top tag') AS top_tag,
  ar.avg_rep AS avg_reputation
FROM Users u
LEFT JOIN user_avg_score uas ON u.Id = uas.Id
LEFT JOIN top_posts tp ON u.Id = tp.Id
LEFT JOIN (
  SELECT t.TagName
  FROM top_tags t
  ORDER BY t.question_count DESC
  LIMIT 1
) tt ON 1=1
CROSS JOIN avg_reputation ar
WHERE u.Reputation > COALESCE((SELECT avg_rep FROM avg_reputation), 0)
ORDER BY u.Reputation DESC;