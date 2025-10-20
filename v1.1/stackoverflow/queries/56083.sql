WITH top_10_users_with_most_upvotes AS (
  SELECT u.Id, u.DisplayName, COUNT(v.Id) AS upvote_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
  GROUP BY u.Id, u.DisplayName
  ORDER BY COUNT(v.Id) DESC
  LIMIT 10
),
top_10_tags_with_most_posts AS (
  SELECT t.TagName, COUNT(p.Id) AS post_count
  FROM Tags t
  JOIN Posts p ON t.TagName = (
    -- extract tag names from Posts.Tags which are stored like "<tag1><tag2>"
    -- transform to a comparable form: check for presence of '<' || t.TagName || '>'
    -- This is a portable approach avoiding string_to_array/ANY which are Postgres-specific
    CASE
      WHEN p.Tags IS NULL THEN NULL
      WHEN POSITION('<' || t.TagName || '>' IN p.Tags) > 0 THEN t.TagName
      ELSE NULL
    END
  )
  WHERE p.Tags IS NOT NULL AND POSITION('<' || t.TagName || '>' IN p.Tags) > 0
  GROUP BY t.TagName
  ORDER BY COUNT(p.Id) DESC
  LIMIT 10
)
SELECT 
  u.Id, 
  u.DisplayName, 
  COUNT(p.Id) AS post_count, 
  SUM(p.Score) AS total_score, 
  SUM(p.ViewCount) AS total_view_count, 
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId IN (SELECT p2.Id FROM Posts p2 WHERE p2.OwnerUserId = u.Id)) AS comment_count,
  (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId IN (SELECT p3.Id FROM Posts p3 WHERE p3.OwnerUserId = u.Id) AND v2.VoteTypeId = 2) AS upvote_count,
  (SELECT COUNT(*) FROM Votes v3 WHERE v3.PostId IN (SELECT p4.Id FROM Posts p4 WHERE p4.OwnerUserId = u.Id) AND v3.VoteTypeId = 3) AS downvote_count,
  (SELECT STRING_AGG(t2.TagName, ', ') FROM Posts p5 JOIN Tags t2 ON POSITION('<' || t2.TagName || '>' IN p5.Tags) > 0 WHERE p5.OwnerUserId = u.Id AND p5.Tags IS NOT NULL) AS tags,
  tu.upvote_count AS top_upvote_count,
  tt.post_count AS top_tag_post_count
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN top_10_users_with_most_upvotes tu ON u.Id = tu.Id
JOIN top_10_tags_with_most_posts tt ON tt.TagName = (
  SELECT t_inner.TagName
  FROM Tags t_inner
  WHERE POSITION('<' || t_inner.TagName || '>' IN p.Tags) > 0
  FETCH FIRST 1 ROWS ONLY
)
GROUP BY u.Id, u.DisplayName, tu.upvote_count, tt.post_count
ORDER BY COUNT(p.Id) DESC;