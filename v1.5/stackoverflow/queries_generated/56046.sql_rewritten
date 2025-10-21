-- {"query": "56046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 282} 
WITH top_posters AS (
  SELECT u.Id, u.DisplayName, COUNT(p.Id) as post_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName
  ORDER BY post_count DESC
  LIMIT 10
),
top_voters AS (
  SELECT u.Id, u.DisplayName, COUNT(v.Id) as vote_count
  FROM Users u
  JOIN Votes v ON u.Id = v.UserId
  WHERE v.VoteTypeId IN (2, 3)
  GROUP BY u.Id, u.DisplayName
  ORDER BY vote_count DESC
  LIMIT 10
),
top_commenters AS (
  SELECT u.Id, u.DisplayName, COUNT(c.Id) as comment_count
  FROM Users u
  JOIN Comments c ON u.Id = c.UserId
  GROUP BY u.Id, u.DisplayName
  ORDER BY comment_count DESC
  LIMIT 10
)
SELECT 
  tp.Id, 
  tp.DisplayName, 
  tp.post_count, 
  tv.vote_count, 
  tc.comment_count
FROM top_posters tp
JOIN top_voters tv ON tp.Id = tv.Id
JOIN top_commenters tc ON tp.Id = tc.Id
ORDER BY tp.post_count DESC, tv.vote_count DESC, tc.comment_count DESC;