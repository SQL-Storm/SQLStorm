-- {"query": "5656.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 371} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
  AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
  MAX(p.LastActivityDate) AS LastActive,
  STRING_AGG(Distinct CASE WHEN vV.VoteTypeName IS NOT NULL THEN vV.VoteTypeName ELSE 'UNKNOWN' END, ',') AS DistinctVoteTypes,
  COUNT(DISTINCT b.Id) AS BadgesEarned,
  SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
  SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
  SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
FROM
  Users u
LEFT JOIN Posts p
  ON p.OwnerUserId = u.Id
LEFT JOIN LATERAL (
  SELECT v.PostId, vt.Name AS VoteTypeName
  FROM Votes v
  JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  WHERE v.UserId = u.Id
  GROUP BY v.PostId, vt.Name
  LIMIT 100
) vV ON vV.PostId IS NOT NULL
LEFT JOIN Badges b
  ON b.UserId = u.Id
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  Reputation DESC,
  UserName
LIMIT 100;