WITH
  RankedQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      COUNT(a.Id) AS AnswerCountByPost,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.OwnerUserId
        ORDER BY
          p.CreationDate DESC
      ) AS RowNum
    FROM Posts AS p
    LEFT JOIN Posts AS a
      ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE
      p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY
      p.Id,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.FavoriteCount
  ),
  UserAnswerStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserName,
      u.Reputation,
      COUNT(DISTINCT ans.Id) AS TotalAnswers,
      AVG(ans.Score) AS AvgAnswerScore,
      SUM(CASE WHEN ans.Score > 0 THEN 1 ELSE 0 END) AS PositiveAnswerCount,
      MAX(ans.CreationDate) AS LastAnswerDate
    FROM Users AS u
    LEFT JOIN Posts AS ans
      ON u.Id = ans.OwnerUserId AND ans.PostTypeId = 2
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  ComplexVoteAnalysis AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpvotesGiven,
      COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownvotesGiven,
      COUNT(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 END) AS AcceptedAnswers,
      AVG(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN (EXTRACT(EPOCH FROM (v.CreationDate - p.CreationDate)) / 86400.0) ELSE NULL END) AS AvgAcceptedAnswerLeadTime,
      SUM(CASE WHEN vt.Name = 'BountyStart' THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS TotalBountyAmount
    FROM Votes AS v
    JOIN VoteTypes AS vt
      ON v.VoteTypeId = vt.Id
    JOIN Posts AS p
      ON v.PostId = p.Id
    WHERE
      v.UserId IS NOT NULL AND vt.Name IN ('UpMod', 'DownMod', 'AcceptedByOriginator', 'BountyStart')
    GROUP BY
      v.UserId
  )
SELECT
  rq.QuestionId,
  rq.Title AS QuestionTitle,
  uas.UserName AS QuestionOwner,
  rq.QuestionCreationDate,
  rq.QuestionScore,
  rq.QuestionViewCount,
  rq.AnswerCount AS QuestionAnswerCount,
  rq.FavoriteCount AS QuestionFavoriteCount,
  uas.TotalAnswers AS UserTotalAnswers,
  uas.AvgAnswerScore,
  uas.PositiveAnswerCount,
  uas.LastAnswerDate,
  cva.UpvotesGiven AS UserUpvotesGiven,
  cva.DownvotesGiven AS UserDownvotesGiven,
  cva.AcceptedAnswers AS UserAcceptedAnswers,
  cva.AvgAcceptedAnswerLeadTime,
  cva.TotalBountyAmount AS UserTotalBountyGiven,
  COALESCE(pht.CountOfEdits, 0) AS PostHistoryEditCount,
  CASE WHEN rq.QuestionScore > 100 AND rq.AnswerCountByPost > 5 THEN 'High Performant' WHEN rq.QuestionScore < 0 THEN 'Low Performant' ELSE 'Average' END AS PerformanceCategory,
  CASE WHEN rq.QuestionCreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year') THEN 'Old' ELSE 'Recent' END AS AgeCategory,
  UPPER(SUBSTR(rq.Title, 1, 3)) AS TitlePrefix,
  CASE WHEN uas.Reputation IS NULL THEN 'Unknown Location' WHEN uas.Reputation IS NOT NULL AND (SELECT 1 FROM Users u2 WHERE u2.Id = rq.OwnerUserId AND u2.Location LIKE '%United States%') = 1 THEN 'USA User' WHEN (SELECT u3.Location FROM Users u3 WHERE u3.Id = rq.OwnerUserId) IS NULL THEN 'Unknown Location' ELSE 'Other Location' END AS UserLocationCategory,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = rq.QuestionId AND LENGTH(c.Text) > 100
  ) AS LongCommentCount
FROM RankedQuestions AS rq
LEFT JOIN Users AS u
  ON rq.OwnerUserId = u.Id
LEFT JOIN UserAnswerStats AS uas
  ON u.Id = uas.UserId
LEFT JOIN ComplexVoteAnalysis AS cva
  ON u.Id = cva.UserId
LEFT JOIN (
  SELECT
    PostId,
    COUNT(*) AS CountOfEdits
  FROM PostHistory
  WHERE
    PostHistoryTypeId IN (4, 5, 6)
  GROUP BY
    PostId
) AS pht
  ON rq.QuestionId = pht.PostId
WHERE
  rq.RowNum <= 10 AND rq.QuestionScore > 5
ORDER BY
  rq.QuestionScore DESC,
  rq.QuestionViewCount DESC,
  uas.AvgAnswerScore DESC NULLS LAST;