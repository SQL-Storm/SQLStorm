-- {"query": "4766.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1581}
WITH
  PostQuality AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.Score,
      CASE
        WHEN p.PostTypeId = 1 THEN p.Score * 1.5
        WHEN p.PostTypeId = 2 THEN p.Score * 1.2
        WHEN p.PostTypeId IN (3, 5) THEN p.Score * 1.1
        ELSE p.Score
      END AS CalculatedQuality,
      p.OwnerUserId,
      p.CreationDate,
      p.Title,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      pt.Name AS PostTypeName,
      p.Tags
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.Score > 0 OR p.PostTypeId IN (3, 5)
  ),
  UserContributionRank AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(b.Id) AS BadgeCount,
      RANK() OVER (ORDER BY u.Reputation DESC, COUNT(b.Id) DESC) AS UserRank
    FROM Users u
    LEFT JOIN Badges b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
    HAVING
      u.Reputation > 1000
  ),
  ClosedPostsInfo AS (
    SELECT
      p.Id AS PostId,
      p.ClosedDate,
      crt.Name AS CloseReasonName
    FROM Posts p
    LEFT JOIN PostHistory ph
      ON p.Id = ph.PostId
    LEFT JOIN CloseReasonTypes crt
      ON (CASE
            WHEN ph.Comment ~ '^\d+$' THEN CAST(ph.Comment AS INTEGER)
            ELSE NULL
          END) = crt.Id
    WHERE
      p.ClosedDate IS NOT NULL
      AND ph.PostHistoryTypeId = 10
  ),
  UserAnswerQuality AS (
    SELECT
      p_ans.OwnerUserId,
      AVG(pq.CalculatedQuality) AS AvgAcceptedAnswerQuality,
      COUNT(DISTINCT p_q.Id) AS NumberOfQuestionsAnswered
    FROM Posts p_ans
    JOIN Posts p_q
      ON p_ans.ParentId = p_q.Id
    JOIN PostQuality pq
      ON p_ans.Id = pq.PostId
    WHERE
      p_ans.PostTypeId = 2
      AND p_q.AcceptedAnswerId = p_ans.Id
      AND p_ans.OwnerUserId IS NOT NULL
    GROUP BY
      p_ans.OwnerUserId
  ),
  PostTypeMetrics AS (
    SELECT
      pt.Name AS PostTypeName,
      COUNT(p.Id) AS TotalPosts,
      AVG(p.Score) AS AvgScore,
      SUM(p.ViewCount) AS TotalViews,
      AVG(p.AnswerCount) AS AvgAnswers
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    GROUP BY
      pt.Name
  )
SELECT
  pq.PostId,
  pq.Title,
  pq.PostTypeName,
  pq.CalculatedQuality,
  pq.Score,
  pq.FavoriteCount,
  pq.CommentCount,
  pq.AnswerCount,
  u.DisplayName AS OwnerDisplayName,
  ucr.UserRank,
  COALESCE(cpi.CloseReasonName, 'Not Closed') AS ClosureStatus,
  CASE
    WHEN cpi.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS IsPostClosed,
  uaq.AvgAcceptedAnswerQuality,
  uaq.NumberOfQuestionsAnswered,
  ptm.TotalPosts AS PostTypeTotalPosts,
  ptm.AvgScore AS PostTypeAvgScore,
  ptm.TotalViews AS PostTypeTotalViews,
  ptm.AvgAnswers AS PostTypeAvgAnswers,
  CASE
    WHEN pq.PostTypeId = 1 THEN pq.CalculatedQuality * (1.0 / NULLIF(ucr.UserRank,0)) * COALESCE(uaq.AvgAcceptedAnswerQuality, 0)
    ELSE pq.CalculatedQuality * (1.0 / NULLIF(ucr.UserRank,0))
  END AS AdjustedQualityScore,
  CASE
    WHEN pq.Score < 5 AND pq.CommentCount > 10 THEN 'High Comment/Low Score Anomaly'
    WHEN pq.Score > 50 AND pq.CommentCount < 5 THEN 'High Score/Low Comment Anomaly'
    ELSE 'Normal Engagement'
  END AS EngagementPattern,
  REPLACE(REPLACE(COALESCE(pq.Tags, ''), '<', ''), '>', '') AS FormattedTags
FROM PostQuality pq
LEFT JOIN Users u
  ON pq.OwnerUserId = u.Id
LEFT JOIN UserContributionRank ucr
  ON u.Id = ucr.UserId
LEFT JOIN ClosedPostsInfo cpi
  ON pq.PostId = cpi.PostId
LEFT JOIN UserAnswerQuality uaq
  ON pq.OwnerUserId = uaq.OwnerUserId AND pq.PostTypeId = 1
LEFT JOIN PostTypeMetrics ptm
  ON pq.PostTypeName = ptm.PostTypeName
WHERE
  pq.CreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-12-31'
  AND (pq.Score > 10 OR pq.PostTypeName = 'Question')
  AND u.Id IS NOT NULL
ORDER BY
  AdjustedQualityScore DESC
LIMIT 100;