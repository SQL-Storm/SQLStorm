WITH cte AS (
  SELECT p.Id, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, u.Reputation, u.UpVotes, u.DownVotes, u.Views
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
)
SELECT 
  CAST(DATE_PART('day', TIMESTAMP '2024-10-01 12:34:56' - CreationDate) AS INTEGER) AS PostAgeDays,
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
GROUP BY CAST(DATE_PART('day', TIMESTAMP '2024-10-01 12:34:56' - CreationDate) AS INTEGER), 
         CASE 
           WHEN Reputation >= 10000 THEN '10k+'
           WHEN Reputation >= 5000 THEN '5k-10k'
           WHEN Reputation >= 2000 THEN '2k-5k'
           WHEN Reputation >= 1000 THEN '1k-2k'
           WHEN Reputation >= 500 THEN '500-1k'
           WHEN Reputation >= 200 THEN '200-500'
           ELSE '<200'
         END
ORDER BY PostAgeDays, ReputationBucket;