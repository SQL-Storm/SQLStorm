WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS UserRank
  FROM Users u
  WHERE u.Reputation > 1000
    AND u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
),
QuestionMetrics AS (
  SELECT 
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.CreationDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS QuestionRank,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years'
    AND p.ClosedDate IS NULL
),
AnswerStats AS (
  SELECT 
    p.ParentId AS QuestionId,
    COUNT(p.Id) AS AnswerCount,
    MAX(p.Score) AS MaxAnswerScore,
    AVG(p.Score) AS AvgAnswerScore
  FROM Posts p
  WHERE p.PostTypeId = 2
  GROUP BY p.ParentId
),
HighActivityQuestions AS (
  SELECT 
    qm.PostId,
    qm.Title,
    qm.Score,
    qm.OwnerUserId,
    us.DisplayName,
    us.Reputation,
    ans.AnswerCount,
    ans.MaxAnswerScore,
    ans.AvgAnswerScore,
    COALESCE(pl.RelatedPostCount, 0) AS RelatedPostCount,
    qm.ViewCount
  FROM QuestionMetrics qm
  JOIN TopUsers us ON qm.OwnerUserId = us.Id
  LEFT JOIN AnswerStats ans ON qm.PostId = ans.QuestionId
  LEFT JOIN (
    SELECT 
      pl.PostId,
      COUNT(pl.RelatedPostId) AS RelatedPostCount
    FROM PostLinks pl
    GROUP BY pl.PostId
  ) pl ON qm.PostId = pl.PostId
  WHERE qm.QuestionRank <= 5
    AND qm.AvgUserScore > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
),
EditedQuestions AS (
  SELECT 
    ph.PostId,
    COUNT(*) AS EditCount,
    MAX(ph.CreationDate) AS LastEditDate
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4, 5, 6)
  GROUP BY ph.PostId
)
SELECT 
  hq.Title,
  hq.Score,
  hq.DisplayName AS Owner,
  hq.Reputation,
  hq.AnswerCount,
  hq.MaxAnswerScore,
  hq.AvgAnswerScore,
  hq.RelatedPostCount,
  eq.EditCount,
  eq.LastEditDate,
  hq.Score * 1.0 / NULLIF(hq.ViewCount, 1) AS EngagementRatio
FROM HighActivityQuestions hq
LEFT JOIN EditedQuestions eq ON hq.PostId = eq.PostId
GROUP BY
  hq.Title,
  hq.Score,
  hq.DisplayName,
  hq.Reputation,
  hq.AnswerCount,
  hq.MaxAnswerScore,
  hq.AvgAnswerScore,
  hq.RelatedPostCount,
  eq.EditCount,
  eq.LastEditDate,
  hq.PostId,
  hq.ViewCount
ORDER BY hq.Score DESC, hq.RelatedPostCount DESC
LIMIT 100;