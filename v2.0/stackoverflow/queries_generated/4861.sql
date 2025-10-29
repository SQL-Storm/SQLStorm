-- {"query": "4861.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1233} 

WITH
  RankedPosts AS (
    SELECT
      p.Id,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate ASC) AS ScoreRank
    FROM Posts AS p
    WHERE
      p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
  ),
  UserPostCounts AS (
    SELECT
      rp.OwnerUserId,
      COUNT(rp.Id) AS TotalPosts,
      SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM RankedPosts AS rp
    GROUP BY
      rp.OwnerUserId
  ),
  UserReputation AS (
    SELECT
      u.Id AS UserId,
      u.Reputation,
      u.CreationDate,
      u.DisplayName,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      CASE
        WHEN u.WebsiteUrl IS NULL THEN 'No Website'
        WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
        ELSE 'External'
      END AS WebsiteCategory
    FROM Users AS u
  )
SELECT
  rp.Id AS PostId,
  pt.Name AS PostTypeName,
  ur.DisplayName AS OwnerDisplayName,
  ur.Reputation,
  ur.WebsiteCategory,
  rp.Score,
  rp.PreviousScore,
  rp.Score - rp.PreviousScore AS ScoreDelta,
  rp.AnswerCount AS PostAnswerCount,
  rp.CommentCount AS PostCommentCount,
  rp.FavoriteCount AS PostFavoriteCount,
  rp.ViewCount AS PostViewCount,
  upc.TotalPosts AS UserTotalPosts,
  upc.QuestionCount AS UserQuestionCount,
  upc.AnswerCount AS UserAnswerCount,
  CASE
    WHEN rp.Score > ur.UserUpVotes * 1.5 THEN 'High Score Relative to Votes'
    WHEN rp.Score < ur.UserDownVotes * 0.5 THEN 'Low Score Relative to Votes'
    ELSE 'Moderate Score'
  END AS ScoreVsUserVotes,
  COALESCE(rp.OwnerUserId, -1) AS EffectiveOwnerUserId,
  CASE
    WHEN rp.ScoreRank <= 50 THEN 'Top 50'
    WHEN rp.ScoreRank <= 200 THEN 'Top 200'
    ELSE 'Other'
  END AS ScoreTier
FROM RankedPosts AS rp
JOIN PostTypes AS pt
  ON rp.PostTypeId = pt.Id
LEFT JOIN UserPostCounts AS upc
  ON rp.OwnerUserId = upc.OwnerUserId
LEFT JOIN UserReputation AS ur
  ON rp.OwnerUserId = ur.UserId
WHERE
  rp.Score > 10
  AND rp.AnswerCount > 0
  AND rp.CreationDate >= '2023-01-01'
  AND rp.CommentCount > (
    SELECT
      AVG(c.Score)
    FROM Comments AS c
    WHERE
      c.PostId = rp.Id
  )
UNION ALL
SELECT
  rp.Id AS PostId,
  pt.Name AS PostTypeName,
  ur.DisplayName AS OwnerDisplayName,
  ur.Reputation,
  ur.WebsiteCategory,
  rp.Score,
  rp.PreviousScore,
  rp.Score - rp.PreviousScore AS ScoreDelta,
  rp.AnswerCount AS PostAnswerCount,
  rp.CommentCount AS PostCommentCount,
  rp.FavoriteCount AS PostFavoriteCount,
  rp.ViewCount AS PostViewCount,
  upc.TotalPosts AS UserTotalPosts,
  upc.QuestionCount AS UserQuestionCount,
  upc.AnswerCount AS UserAnswerCount,
  CASE
    WHEN rp.Score > ur.UserUpVotes * 1.5 THEN 'High Score Relative to Votes'
    WHEN rp.Score < ur.UserDownVotes * 0.5 THEN 'Low Score Relative to Votes'
    ELSE 'Moderate Score'
  END AS ScoreVsUserVotes,
  COALESCE(rp.OwnerUserId, -1) AS EffectiveOwnerUserId,
  CASE
    WHEN rp.ScoreRank <= 50 THEN 'Top 50'
    WHEN rp.ScoreRank <= 200 THEN 'Top 200'
    ELSE 'Other'
  END AS ScoreTier
FROM RankedPosts AS rp
JOIN PostTypes AS pt
  ON rp.PostTypeId = pt.Id
LEFT JOIN UserPostCounts AS upc
  ON rp.OwnerUserId = upc.OwnerUserId
LEFT JOIN UserReputation AS ur
  ON rp.OwnerUserId = ur.UserId
WHERE
  rp.Score < -5
  AND rp.CreationDate < '2023-01-01'
  AND rp.FavoriteCount IS NULL
ORDER BY
  Score DESC;
