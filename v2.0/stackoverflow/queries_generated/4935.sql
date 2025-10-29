-- {"query": "4935.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1809} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edits: Title, Body, Tags
  ),
  UserEditFrequency AS (
    SELECT
      re.UserId,
      COUNT(re.PostId) AS TotalEdits,
      AVG(CAST(EXTRACT(EPOCH FROM (re.EditDate - u.CreationDate)) AS NUMERIC) / 60.0 / 60.0 / 24.0) AS AvgDaysSinceUserCreation
    FROM RankedPostEdits AS re
    JOIN Users AS u
      ON re.UserId = u.Id
    WHERE
      re.rn = 1 -- Consider only the latest edit for each post to avoid double counting rapid edits
    GROUP BY
      re.UserId
  ),
  PostQualityMetrics AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate AS PostCreationDate,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      COUNT(c.Id) AS CommentCountForPost,
      AVG(CAST(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) AS NUMERIC) / 60.0) AS TimeToLastActivityMinutes,
      CASE
        WHEN EXISTS (
          SELECT
            1
          FROM PostLinks AS pl
          WHERE
            pl.PostId = p.Id AND pl.LinkTypeId = 3
        ) THEN 1
        ELSE 0
      END AS IsDuplicateLink,
      STRING_AGG(COALESCE(t.TagName, 'UnknownTag'), ', ') AS TagsUsed
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Tags AS t
      ON p.Tags LIKE '%' || t.TagName || '%' -- This is a simplistic tag extraction and might not be perfectly accurate
    WHERE
      p.PostTypeId = 1 -- Questions only
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate,
      p.ClosedDate,
      p.LastActivityDate
  )
SELECT
  pqm.PostId,
  pqm.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  pqm.Score,
  pqm.ViewCount,
  pqm.AnswerCount,
  pqm.CommentCountForPost,
  pqm.FavoriteCount,
  pqm.IsClosed,
  pqm.TimeToLastActivityMinutes,
  pqm.IsDuplicateLink,
  pqm.TagsUsed,
  COALESCE(uef.TotalEdits, 0) AS UserTotalEdits,
  uef.AvgDaysSinceUserCreation,
  CASE
    WHEN pqm.Score > 10 AND pqm.ViewCount > 1000 THEN 'High Value'
    WHEN pqm.Score < 0 AND pqm.IsClosed = 1 THEN 'Potentially Problematic'
    WHEN pqm.AnswerCount > 5 AND pqm.CommentCountForPost > 10 THEN 'Highly Discussed'
    ELSE 'Standard'
  END AS PostCategory,
  -- Complex calculation: weighted score based on various metrics
  (
    (pqm.Score * 5) + (pqm.ViewCount * 0.1) + (pqm.AnswerCount * 2) - (
      CASE WHEN pqm.IsClosed = 1 THEN 50 ELSE 0 END
    ) + (
      CASE WHEN pqm.FavoriteCount > 0 THEN pqm.FavoriteCount * 3 ELSE 0 END
    ) - (
      COALESCE(uef.TotalEdits, 0) * 0.5
    )
  ) AS WeightedPerformanceScore,
  LAG(pqm.Score, 1, 0) OVER (ORDER BY pqm.PostCreationDate) AS PreviousPostScore,
  LEAD(pqm.Score, 1, 0) OVER (ORDER BY pqm.PostCreationDate) AS NextPostScore,
  -- Combine information from Users and PostHistory for user engagement context
  CASE
    WHEN u.Reputation > 50000 THEN 'High Reputation'
    WHEN u.UpVotes > 10000 THEN 'Highly Voted User'
    WHEN u.CreationDate < NOW() - INTERVAL '1 year' THEN 'Established User'
    ELSE 'Standard User'
  END AS UserContext,
  -- Check for posts with unusual editing patterns relative to creation date
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostHistory AS ph_inner
      WHERE
        ph_inner.PostId = pqm.PostId
        AND ph_inner.PostHistoryTypeId IN (4, 5, 6) -- Edits
        AND ph_inner.CreationDate > pqm.PostCreationDate + INTERVAL '30 days'
    ) THEN 'Late Edit Activity'
    ELSE 'Normal Edit Activity'
  END AS EditActivityPattern
FROM PostQualityMetrics AS pqm
LEFT JOIN Users AS u
  ON pqm.OwnerUserId = u.Id
LEFT JOIN UserEditFrequency AS uef
  ON pqm.OwnerUserId = uef.UserId
WHERE
  pqm.PostCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND pqm.Score > -5 -- Exclude very low scoring posts
UNION ALL
SELECT
  NULL AS PostId,
  NULL AS OwnerUserId,
  NULL AS OwnerDisplayName,
  NULL AS Score,
  NULL AS ViewCount,
  NULL AS AnswerCount,
  NULL AS CommentCountForPost,
  NULL AS FavoriteCount,
  NULL AS IsClosed,
  NULL AS TimeToLastActivityMinutes,
  NULL AS IsDuplicateLink,
  'Summary Metrics' AS TagsUsed,
  COUNT(DISTINCT uef.UserId) AS UserTotalEdits,
  AVG(uef.AvgDaysSinceUserCreation) AS AvgDaysSinceUserCreation,
  'Overall Performance Summary' AS PostCategory,
  AVG(
    (
      (pqm.Score * 5) + (pqm.ViewCount * 0.1) + (pqm.AnswerCount * 2) - (
        CASE WHEN pqm.IsClosed = 1 THEN 50 ELSE 0 END
      ) + (
        CASE WHEN pqm.FavoriteCount > 0 THEN pqm.FavoriteCount * 3 ELSE 0 END
      ) - (
        COALESCE(uef.TotalEdits, 0) * 0.5
      )
    )
  ) AS WeightedPerformanceScore,
  AVG(pqm.Score) AS PreviousPostScore,
  AVG(pqm.Score) AS NextPostScore,
  NULL AS UserContext,
  NULL AS EditActivityPattern
FROM PostQualityMetrics AS pqm
LEFT JOIN Users AS u
  ON pqm.OwnerUserId = u.Id
LEFT JOIN UserEditFrequency AS uef
  ON pqm.OwnerUserId = uef.UserId
WHERE
  pqm.PostCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND pqm.Score > -5;
