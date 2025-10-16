-- {"query": "18064.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 981} 

WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS RankByScore,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextScore
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.Score > 0 AND p.OwnerUserId IS NOT NULL AND p.Title IS NOT NULL
  ),
  UserPostContributions AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AverageScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  HighReputationUsers AS (
    SELECT
      UserId,
      DisplayName
    FROM UserPostContributions
    WHERE
      TotalPosts > 1000 AND AverageScore > 50
  ),
  PostHistoryAggregates AS (
    SELECT
      ph.PostId,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 END) AS BodyEdits,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (1, 4, 7) THEN 1 END) AS TitleEdits,
      MAX(ph.CreationDate) AS LastEditDateForPost
    FROM PostHistory AS ph
    WHERE
      ph.UserId IN (SELECT UserId FROM HighReputationUsers)
    GROUP BY
      ph.PostId
  )
SELECT
  rp.PostId,
  rp.Title,
  rp.PostTypeName,
  rp.Score,
  rp.AnswerCount,
  rp.CommentCount,
  rp.RankByScore,
  rp.PreviousScore,
  rp.NextScore,
  COALESCE(hr.DisplayName, 'Unknown User') AS OwnerDisplayName,
  pha.BodyEdits,
  pha.TitleEdits,
  CASE
    WHEN rp.Score > 1000 THEN 'Very High'
    WHEN rp.Score > 100 THEN 'High'
    WHEN rp.Score > 10 THEN 'Medium'
    ELSE 'Low'
  END AS ScoreCategory,
  (rp.AnswerCount + rp.CommentCount) AS TotalInteractions,
  CHARINDEX('sql', LOWER(rp.Title)) AS SqlKeywordPosition,
  DATEDIFF(day, rp.CreationDate, GETDATE()) AS DaysSinceCreation
FROM RankedPosts AS rp
LEFT JOIN HighReputationUsers AS hr
  ON rp.OwnerUserId = hr.UserId
LEFT JOIN PostHistoryAggregates AS pha
  ON rp.PostId = pha.PostId
WHERE
  rp.RankByScore <= 50 AND EXISTS (SELECT 1 FROM Tags t WHERE t.TagName = 'performance' AND rp.Id IN (SELECT PostId FROM Posts WHERE Tags LIKE '%' + t.TagName + '%'))
UNION ALL
SELECT
  NULL,
  '--- Summary ---',
  NULL,
  AVG(Score),
  AVG(AnswerCount),
  AVG(CommentCount),
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  'Average',
  AVG(AnswerCount + CommentCount),
  NULL,
  NULL
FROM RankedPosts
WHERE
  RankByScore <= 50;
