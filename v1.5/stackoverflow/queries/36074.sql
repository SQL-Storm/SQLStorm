SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  MAX(p.CreationDate) AS LastActivity,
  AVG(u.Reputation) AS AvgReputation,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
    AND v.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year') -- votes in the last year
GROUP BY
  u.Id,
  u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  PostCount DESC,
  LastActivity DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;