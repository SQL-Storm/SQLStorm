-- {"query": "44052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 454}

WITH cte AS (
  SELECT p.Id, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, u.Reputation, u.UpVotes, u.DownVotes, u.Views
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
)
SELECT 
  DATEDIFF(CURRENT_TIMESTAMP, CreationDate) AS PostAgeDays,
  CASE 
    WHEN Reputation >= 10000 THEN '10k+'
    WHEN Reputation >= 5000 THEN '5k-10k'
    WHEN Reputation >= 2000 THEN '2k-5k'
    WHEN Reputation >= 1000 THEN '1k-2k'
    WHEN Reputation >= 500 THEN '500-1k'
    WHEN Reputation >= 200 THEN '200-500'
    ELSE '<200'
  END AS ReputationBucket,
  AVG(Score) AS AvgScore,
  AVG(ViewCount) AS AvgViewCount,
  AVG(AnswerCount) AS AvgAnswerCount,
  AVG(CommentCount) AS AvgCommentCount,
  AVG(FavoriteCount) AS AvgFavoriteCount,
  AVG(UpVotes) AS AvgUpVotes,
  AVG(DownVotes) AS AvgDownVotes,
  AVG(Views) AS AvgViews
FROM cte
GROUP BY DATEDIFF(CURRENT_TIMESTAMP, CreationDate), ReputationBucket
ORDER BY PostAgeDays, ReputationBucket;
