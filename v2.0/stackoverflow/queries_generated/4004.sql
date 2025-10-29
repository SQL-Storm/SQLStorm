-- {"query": "4004.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2072} 

WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      p.ClosedDate,
      pt.Name AS PostTypeName,
      CASE
        WHEN p.Title IS NOT NULL THEN LENGTH(p.Title)
        ELSE 0
      END AS TitleLength,
      CASE
        WHEN p.Tags IS NOT NULL THEN (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', ''))) + 1
        ELSE 0
      END AS TagCount,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL AND p.CreationDate > '2023-01-01'
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT p.Id) AS PostsCreated,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
      COUNT(DISTINCT c.Id) AS CommentsMade,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
      MAX(p.CreationDate) AS LastPostDate
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId
    WHERE
      u.Id <> -1 -- Exclude community user
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  PostAnalysis AS (
    SELECT
      rp.PostId,
      rp.PostTypeName,
      rp.Score,
      rp.AnswerCount,
      rp.CommentCount,
      rp.FavoriteCount,
      rp.ViewCount,
      rp.TitleLength,
      rp.TagCount,
      DATEDIFF(day, rp.CreationDate, GETDATE()) AS DaysSinceCreation,
      CASE
        WHEN rp.ClosedDate IS NOT NULL THEN DATEDIFF(day, rp.CreationDate, rp.ClosedDate)
        ELSE NULL
      END AS DaysToClose,
      ue.DisplayName AS OwnerDisplayName,
      ue.Reputation AS OwnerReputation,
      ue.UserCreationDate,
      CASE
        WHEN rp.Score > 0 AND rp.AnswerCount > 0 THEN CAST(rp.Score AS REAL) / rp.AnswerCount
        WHEN rp.Score > 0 THEN CAST(rp.Score AS REAL)
        ELSE 0
      END AS ScorePerAnswer,
      CASE
        WHEN rp.ViewCount > 0 AND rp.AnswerCount > 0 THEN CAST(rp.ViewCount AS REAL) / rp.AnswerCount
        WHEN rp.ViewCount > 0 THEN CAST(rp.ViewCount AS REAL)
        ELSE 0
      END AS ViewsPerAnswer,
      CASE
        WHEN rp.CommentCount > 0 THEN 'Has Comments'
        ELSE 'No Comments'
      END AS CommentStatus,
      CASE
        WHEN rp.Score > 100 THEN 'High Score'
        WHEN rp.Score > 10 THEN 'Medium Score'
        ELSE 'Low Score'
      END AS ScoreBracket,
      CASE
        WHEN ue.LastPostDate IS NOT NULL AND DATEDIFF(day, ue.LastPostDate, GETDATE()) < 30 THEN 'Active User'
        ELSE 'Inactive User'
      END AS UserActivityStatus,
      COALESCE(rp.FavoriteCount, 0) AS NonNullFavoriteCount,
      -- Correlated subquery to find the most recent edit date for each post
      (
        SELECT
          MAX(ph.CreationDate)
        FROM PostHistory AS ph
        WHERE
          ph.PostId = rp.PostId AND ph.PostHistoryTypeId BETWEEN 4 AND 9
      ) AS LastEditDate
    FROM RankedPosts AS rp
    JOIN UserEngagement AS ue
      ON rp.OwnerUserId = ue.UserId
    WHERE
      rp.rn <= 100
  )
SELECT
  pa.PostId,
  pa.PostTypeName,
  pa.Score,
  pa.AnswerCount,
  pa.CommentCount,
  pa.FavoriteCount,
  pa.ViewCount,
  pa.TitleLength,
  pa.TagCount,
  pa.DaysSinceCreation,
  pa.DaysToClose,
  pa.OwnerDisplayName,
  pa.OwnerReputation,
  pa.UserCreationDate,
  pa.ScorePerAnswer,
  pa.ViewsPerAnswer,
  pa.CommentStatus,
  pa.ScoreBracket,
  pa.UserActivityStatus,
  pa.NonNullFavoriteCount,
  pa.LastEditDate,
  -- Window function to calculate the average score for posts of the same type within the last year
  AVG(pa.Score) OVER (PARTITION BY pa.PostTypeName ORDER BY pa.CreationDate ROWS BETWEEN 365 PRECEDING AND CURRENT ROW) AS AvgScoreLastYearForType,
  -- Set operator to combine with a small sample of older, high-score posts
  CASE
    WHEN pa.Score > 500 THEN 'Elite Post'
    ELSE 'Standard Post'
  END AS PostTier
FROM PostAnalysis AS pa
UNION ALL
SELECT
  rp.Id,
  pt.Name,
  rp.Score,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  rp.ViewCount,
  CASE
    WHEN rp.Title IS NOT NULL THEN LENGTH(rp.Title)
    ELSE 0
  END AS TitleLength,
  CASE
    WHEN rp.Tags IS NOT NULL THEN (LENGTH(rp.Tags) - LENGTH(REPLACE(rp.Tags, '><', ''))) + 1
    ELSE 0
  END AS TagCount,
  DATEDIFF(day, rp.CreationDate, GETDATE()) AS DaysSinceCreation,
  CASE
    WHEN rp.ClosedDate IS NOT NULL THEN DATEDIFF(day, rp.CreationDate, rp.ClosedDate)
    ELSE NULL
  END AS DaysToClose,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  u.CreationDate AS UserCreationDate,
  CASE
    WHEN rp.Score > 0 AND rp.AnswerCount > 0 THEN CAST(rp.Score AS REAL) / rp.AnswerCount
    WHEN rp.Score > 0 THEN CAST(rp.Score AS REAL)
    ELSE 0
  END AS ScorePerAnswer,
  CASE
    WHEN rp.ViewCount > 0 AND rp.AnswerCount > 0 THEN CAST(rp.ViewCount AS REAL) / rp.AnswerCount
    WHEN rp.ViewCount > 0 THEN CAST(rp.ViewCount AS REAL)
    ELSE 0
  END AS ViewsPerAnswer,
  CASE
    WHEN rp.CommentCount > 0 THEN 'Has Comments'
    ELSE 'No Comments'
  END AS CommentStatus,
  CASE
    WHEN rp.Score > 100 THEN 'High Score'
    WHEN rp.Score > 10 THEN 'Medium Score'
    ELSE 'Low Score'
  END AS ScoreBracket,
  CASE
    WHEN u.LastAccessDate IS NOT NULL AND DATEDIFF(day, u.LastAccessDate, GETDATE()) < 90 THEN 'Active User'
    ELSE 'Inactive User'
  END AS UserActivityStatus,
  COALESCE(rp.FavoriteCount, 0) AS NonNullFavoriteCount,
  (
    SELECT
      MAX(ph.CreationDate)
    FROM PostHistory AS ph
    WHERE
      ph.PostId = rp.Id AND ph.PostHistoryTypeId BETWEEN 4 AND 9
  ) AS LastEditDate,
  NULL AS AvgScoreLastYearForType, -- Placeholder for union
  'Historical Elite Post' AS PostTier -- Differentiating label
FROM Posts AS rp
JOIN PostTypes AS pt
  ON rp.PostTypeId = pt.Id
LEFT JOIN Users AS u
  ON rp.OwnerUserId = u.Id
WHERE
  rp.Score > 1000 AND rp.CreationDate < '2010-01-01'
ORDER BY
  pa.Score DESC;
