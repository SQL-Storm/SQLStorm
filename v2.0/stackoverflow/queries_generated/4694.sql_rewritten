-- {"query": "4694.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1022} 
WITH
  PostSummaries AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate,
      CASE
        WHEN p.PostTypeId = 1 THEN SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2)
        ELSE NULL
      END AS Tags,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostSequence
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
  ),
  UserActivity AS (
    SELECT
      ph.UserId,
      u.DisplayName AS UserDisplayName,
      COUNT(DISTINCT ph.PostId) AS EditedPostCount,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 2 THEN ph.PostId END) AS BodyEditCount,
      MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory AS ph
    JOIN Users AS u
      ON ph.UserId = u.Id
    WHERE
      ph.PostHistoryTypeId IN (2, 4, 5, 8)
    GROUP BY
      ph.UserId,
      u.DisplayName
  ),
  HighScoringAnswers AS (
    SELECT
      ParentId,
      COUNT(*) AS HighScoringAnswerCount
    FROM Posts
    WHERE
      PostTypeId = 2 AND Score > 10
    GROUP BY
      ParentId
  ),
  AvgPostScore AS (
    SELECT
      OwnerUserId,
      AVG(Score) AS AvgUserScore
    FROM Posts
    WHERE
      PostTypeId = 1
    GROUP BY
      OwnerUserId
  )
SELECT
  ps.PostId,
  ps.PostTypeName,
  ps.OwnerDisplayName,
  ps.PostCreationDate,
  ps.PostScore,
  ps.PostViewCount,
  ps.AnswerCount,
  ps.CommentCount,
  ps.FavoriteCount,
  ps.Tags,
  ps.PreviousPostScore,
  ps.PostSequence,
  ua.EditedPostCount,
  ua.BodyEditCount,
  ua.LastEditDate,
  hsa.HighScoringAnswerCount,
  aps.AvgUserScore,
  CASE
    WHEN ps.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN ps.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  CASE
    WHEN ps.OwnerUserId IS NULL THEN 'Unknown'
    WHEN LENGTH(TRIM(COALESCE(u.Location, ''))) = 0 THEN 'No Location'
    ELSE u.Location
  END AS UserLocation,
  COALESCE(ps.PostScore, 0) + COALESCE(ps.AnswerCount, 0) * 5 AS WeightedScore,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = ps.PostId AND c.Score > 0
  ) AS CommentCountWithScore
FROM PostSummaries AS ps
LEFT JOIN UserActivity AS ua
  ON ps.OwnerUserId = ua.UserId
LEFT JOIN HighScoringAnswers AS hsa
  ON ps.PostId = hsa.ParentId
LEFT JOIN AvgPostScore AS aps
  ON ps.OwnerUserId = aps.OwnerUserId
LEFT JOIN Users AS u
  ON ps.OwnerUserId = u.Id
WHERE
  ps.PostSequence <= 10 AND ps.PostScore > 5 AND (
    ps.Tags LIKE '%sql%' OR ps.Tags LIKE '%performance%'
  ) AND COALESCE(ps.FavoriteCount, 0) > 0
ORDER BY
  ps.PostCreationDate DESC,
  ps.PostScore DESC;