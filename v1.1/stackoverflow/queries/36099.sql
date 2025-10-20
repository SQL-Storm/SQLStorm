SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(p.Id) AS PostCount,
  AVG(p.Score) AS AvgScorePerPost,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  MAX(p.CreationDate) AS MostRecentPostDate,
  SUM(v.BountyAmount) AS TotalBountyAwarded,
  STRING_AGG(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN 'Up' WHEN v.VoteTypeId = 3 THEN 'Down' END, ',') AS VoteTypesSeen
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
      AND v.VoteTypeId IN (2,3,8,9,10,11,12,14,15,16)
WHERE
  u.AccountId IS NOT NULL
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(p.Id) > 50
ORDER BY
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) DESC
LIMIT 100;