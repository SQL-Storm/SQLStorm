-- {"query": "56092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 527} 

WITH top_100_posts AS (
  SELECT p.Id, p.Score, p.ViewCount, p.Tags, u.DisplayName AS OwnerDisplayName, u.Reputation AS OwnerReputation
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 AND p.Score > 0
  ORDER BY p.Score DESC
  LIMIT 100
),
top_100_post_comments AS (
  SELECT c.PostId, COUNT(c.Id) AS CommentCount, SUM(c.Score) AS CommentScore
  FROM Comments c
  WHERE c.PostId IN (SELECT Id FROM top_100_posts)
  GROUP BY c.PostId
),
top_100_post_votes AS (
  SELECT v.PostId, COUNT(v.Id) AS VoteCount, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes v
  WHERE v.PostId IN (SELECT Id FROM top_100_posts)
  GROUP BY v.PostId
),
top_100_post_tags AS (
  SELECT p.Id, STRING_AGG(TAGNAME, ', ') AS TagNames
  FROM Posts p
  JOIN PostTags pt ON p.Id = pt.PostId
  JOIN Tags t ON pt.TagId = t.Id
  WHERE p.Id IN (SELECT Id FROM top_100_posts)
  GROUP BY p.Id
)
SELECT 
  t1.Id, 
  t1.Score, 
  t1.ViewCount, 
  t1.Tags, 
  t1.OwnerDisplayName, 
  t1.OwnerReputation, 
  COALESCE(t2.CommentCount, 0) AS CommentCount, 
  COALESCE(t2.CommentScore, 0) AS CommentScore, 
  COALESCE(t3.VoteCount, 0) AS VoteCount, 
  COALESCE(t3.UpVotes, 0) AS UpVotes, 
  COALESCE(t3.DownVotes, 0) AS DownVotes, 
  COALESCE(t4.TagNames, '') AS TagNames
FROM top_100_posts t1
LEFT JOIN top_100_post_comments t2 ON t1.Id = t2.PostId
LEFT JOIN top_100_post_votes t3 ON t1.Id = t3.PostId
LEFT JOIN top_100_post_tags t4 ON t1.Id = t4.Id
ORDER BY t1.Score DESC;
