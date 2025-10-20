WITH top_posters AS (
  SELECT u.Id, u.DisplayName, COUNT(p.Id) AS post_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.DisplayName
  ORDER BY COUNT(p.Id) DESC
  LIMIT 10
),
top_tags AS (
  SELECT t.TagName, COUNT(p.Id) AS post_count
  FROM Tags t
  JOIN Posts p ON t.Id = (
    SELECT Id FROM Tags WHERE TagName = ANY(string_to_array(p.Tags, '<'))
  )
  GROUP BY t.TagName
  ORDER BY COUNT(p.Id) DESC
  LIMIT 10
),
most_voted_posts AS (
  SELECT p.Id, p.Title,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
  FROM Posts p
  JOIN Votes v ON p.Id = v.PostId
  GROUP BY p.Id, p.Title
  ORDER BY SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) DESC
  LIMIT 10
)
SELECT 
  tp.DisplayName AS top_poster, 
  tt.TagName AS top_tag, 
  mvp.Title AS most_voted_post, 
  (mvp.upvotes - mvp.downvotes) AS score
FROM top_posters tp
JOIN top_tags tt ON tp.post_count > 50
JOIN most_voted_posts mvp ON mvp.upvotes > 100
WHERE tp.Id IN (
  SELECT UserId FROM Votes WHERE VoteTypeId = 2 AND PostId IN (
    SELECT Id FROM Posts WHERE Score > 10
  )
)
AND tt.post_count > 20
AND mvp.downvotes < 10
GROUP BY tp.DisplayName, tt.TagName, mvp.Title, mvp.upvotes, mvp.downvotes, tp.Id, tt.post_count, mvp.Id, mvp.downvotes;