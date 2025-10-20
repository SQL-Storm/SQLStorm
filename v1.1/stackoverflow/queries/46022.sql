WITH RECURSIVE UserHierarchy AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    0 AS Level
  FROM Users u
  WHERE u.Reputation > 50000
  
  UNION ALL
  
  SELECT 
    u2.Id,
    u2.DisplayName,
    u2.Reputation,
    u2.CreationDate,
    uh.Level + 1
  FROM Users u2
  INNER JOIN Comments c ON u2.Id = c.UserId
  INNER JOIN Posts p ON c.PostId = p.Id
  INNER JOIN UserHierarchy uh ON p.OwnerUserId = uh.Id
  WHERE uh.Level < 3
),
TagPerformance AS (
  SELECT 
    t.TagName,
    t.Count,
    AVG(p.Score) AS AvgScore,
    COUNT(DISTINCT p.OwnerUserId) AS UniqueContributors,
    SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS ResolvedQuestions,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS MedianViews
  FROM Tags t
  INNER JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2' YEAR)
  GROUP BY t.TagName, t.Count
  HAVING COUNT(*) > 100
),
AnswerQuality AS (
  SELECT 
    a.Id AS AnswerId,
    a.OwnerUserId,
    a.ParentId,
    a.Score AS AnswerScore,
    a.CreationDate AS AnswerDate,
    q.Score AS QuestionScore,
    q.ViewCount,
    DENSE_RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank,
    CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted,
    COUNT(c.Id) AS CommentCount,
    AVG(EXTRACT(EPOCH FROM (v.CreationDate - a.CreationDate))) AS AvgVoteDelaySeconds
  FROM Posts a
  INNER JOIN Posts q ON a.ParentId = q.Id
  LEFT JOIN Comments c ON a.Id = c.PostId
  LEFT JOIN Votes v ON a.Id = v.PostId AND v.VoteTypeId IN (2, 3)
  WHERE a.PostTypeId = 2
    AND q.PostTypeId = 1
    AND a.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '18' MONTH)
  GROUP BY a.Id, a.OwnerUserId, a.ParentId, a.Score, a.CreationDate, q.Score, q.ViewCount, q.AcceptedAnswerId
)
SELECT 
  uh.DisplayName AS InfluentialUser,
  uh.Reputation,
  uh.Level AS InfluenceLevel,
  tp.TagName,
  tp.AvgScore AS TagAvgScore,
  tp.UniqueContributors,
  tp.MedianViews,
  COUNT(DISTINCT aq.AnswerId) AS AnswersGiven,
  AVG(aq.AnswerScore) AS AvgAnswerScore,
  SUM(aq.IsAccepted) AS AcceptedAnswers,
  AVG(aq.AnswerRank) AS AvgAnswerRank,
  SUM(aq.CommentCount) AS TotalComments,
  COUNT(DISTINCT b.Id) AS BadgesEarned,
  SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
  SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
  COUNT(DISTINCT ph.Id) AS EditsMade,
  AVG(EXTRACT(EPOCH FROM (aq.AnswerDate - q.CreationDate))) / 3600 AS AvgHoursToAnswer,
  COALESCE(AVG(aq.AvgVoteDelaySeconds), 0) / 86400 AS AvgDaysToReceiveVotes
FROM UserHierarchy uh
INNER JOIN AnswerQuality aq ON uh.Id = aq.OwnerUserId
INNER JOIN Posts q ON aq.ParentId = q.Id
CROSS JOIN TagPerformance tp
LEFT JOIN Badges b ON uh.Id = b.UserId AND b.Date >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2' YEAR)
LEFT JOIN PostHistory ph ON uh.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
WHERE q.Tags LIKE '%' || '<' || tp.TagName || '>' || '%'
  AND aq.AnswerRank <= 5
  AND tp.Count > 500
GROUP BY uh.DisplayName, uh.Reputation, uh.Level, tp.TagName, tp.AvgScore, tp.UniqueContributors, tp.MedianViews
HAVING COUNT(DISTINCT aq.AnswerId) >= 5
ORDER BY uh.Reputation DESC, AVG(aq.AnswerScore) DESC, tp.AvgScore DESC
LIMIT 100;