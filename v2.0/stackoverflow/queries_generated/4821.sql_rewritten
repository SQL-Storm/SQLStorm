-- {"query": "4821.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1205} 
WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ph.UserId,
      ph.Comment,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (1, 4, 7) -- Title changes
  ),
  LatestPostTitles AS (
    SELECT
      rph.PostId,
      CASE
        WHEN rph.rn = 1
        THEN COALESCE(p.Title, 'No Title')
        ELSE COALESCE(rph.Comment, 'No Comment')
      END AS CurrentTitle,
      p.OwnerUserId
    FROM Posts AS p
    LEFT JOIN RankedPostHistory AS rph
      ON p.Id = rph.PostId AND rph.rn = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS PostCount,
      SUM(p.Score) AS TotalScore,
      AVG(p.ViewCount) AS AverageViewCount
    FROM Users AS u
    JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    WHERE
      p.PostTypeId = 1 -- Questions only
    GROUP BY
      u.Id,
      u.DisplayName
    HAVING
      COUNT(DISTINCT p.Id) > 50
  ),
  TagAnalysis AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(p.AnswerCount) AS TotalAnswers,
      AVG(p.FavoriteCount) AS AverageFavorites
    FROM Tags AS t
    JOIN Posts AS p
      ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE
      p.PostTypeId = 1 -- Questions only
    GROUP BY
      t.TagName
    ORDER BY
      QuestionCount DESC
    LIMIT 10
  ),
  CloseVoteAnalysis AS (
    SELECT
      p.Id AS PostId,
      COUNT(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE NULL END) AS CloseVoteCount,
      COUNT(CASE WHEN v.VoteTypeId = 7 THEN 1 ELSE NULL END) AS ReopenVoteCount,
      MAX(CASE WHEN v.VoteTypeId = 6 THEN v.CreationDate ELSE NULL END) AS LastCloseVoteDate,
      MAX(CASE WHEN v.VoteTypeId = 7 THEN v.CreationDate ELSE NULL END) AS LastReopenVoteDate
    FROM Posts AS p
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId = 1 -- Questions only
    GROUP BY
      p.Id
    HAVING
      COUNT(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE NULL END) > 5 OR COUNT(CASE WHEN v.VoteTypeId = 7 THEN 1 ELSE NULL END) > 0
  )
SELECT
  ua.DisplayName,
  ua.PostCount,
  ua.TotalScore,
  ua.AverageViewCount,
  lpt.CurrentTitle,
  ta.TagName,
  ta.QuestionCount,
  ta.TotalAnswers,
  ta.AverageFavorites,
  cva.CloseVoteCount,
  cva.ReopenVoteCount,
  CASE
    WHEN ua.TotalScore > 10000 AND ta.AverageFavorites > 50 AND cva.CloseVoteCount < 5
    THEN 'High Engagement, Low Closure Risk'
    WHEN ua.TotalScore < 100 AND ta.QuestionCount < 10
    THEN 'Low Engagement, Niche Topic'
    ELSE 'Standard Performance'
  END AS PerformanceCategory,
  CASE
    WHEN cva.LastCloseVoteDate IS NOT NULL AND (cva.LastReopenVoteDate IS NULL OR cva.LastCloseVoteDate > cva.LastReopenVoteDate)
    THEN 'Closed Recently'
    WHEN cva.LastReopenVoteDate IS NOT NULL AND cva.LastCloseVoteDate IS NULL OR cva.LastReopenVoteDate > cva.LastCloseVoteDate
    THEN 'Reopened Recently'
    ELSE 'Stable Status'
  END AS ClosureStatus
FROM UserActivity AS ua
JOIN LatestPostTitles AS lpt
  ON ua.UserId = lpt.OwnerUserId
JOIN TagAnalysis AS ta
  ON ta.TagName = SUBSTRING(lpt.CurrentTitle FROM '#"?(.*?)#"') -- Assuming tags are in the title for demonstration
LEFT JOIN CloseVoteAnalysis AS cva
  ON lpt.PostId = cva.PostId
WHERE
  ua.TotalScore > 5000
UNION
SELECT
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  ta.TagName,
  ta.QuestionCount,
  ta.TotalAnswers,
  ta.AverageFavorites,
  NULL,
  NULL,
  'Tag Spotlight' AS PerformanceCategory,
  'N/A' AS ClosureStatus
FROM TagAnalysis AS ta
WHERE
  ta.QuestionCount > 5000;