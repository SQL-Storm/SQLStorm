-- {"query": "56021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 506} 
WITH top_100_users AS (
  SELECT Id, Reputation, DisplayName, 
         ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS row_num
  FROM Users
),
top_100_posts AS (
  SELECT p.Id, p.Score, p.ViewCount, p.Title, 
         ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS row_num
  FROM Posts p
  JOIN top_100_users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
post_history_stats AS (
  SELECT ph.PostId, COUNT(ph.Id) AS num_edits, 
         SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS num_closes,
         SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS num_reopens
  FROM PostHistory ph
  GROUP BY ph.PostId
),
post_link_stats AS (
  SELECT pl.PostId, COUNT(pl.Id) AS num_links, 
         SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS num_linked,
         SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS num_duplicates
  FROM PostLinks pl
  GROUP BY pl.PostId
),
vote_stats AS (
  SELECT v.PostId, COUNT(v.Id) AS num_votes, 
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS num_upvotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS num_downvotes
  FROM Votes v
  GROUP BY v.PostId
)
SELECT 
  p.Id, p.Score, p.ViewCount, p.Title, 
  phs.num_edits, phs.num_closes, phs.num_reopens, 
  pls.num_links, pls.num_linked, pls.num_duplicates, 
  vs.num_votes, vs.num_upvotes, vs.num_downvotes
FROM top_100_posts p
JOIN post_history_stats phs ON p.Id = phs.PostId
JOIN post_link_stats pls ON p.Id = pls.PostId
JOIN vote_stats vs ON p.Id = vs.PostId
WHERE p.row_num <= 10 AND phs.num_edits > 5 AND pls.num_links > 10 AND vs.num_votes > 50
ORDER BY p.Score DESC;