-- {"query": "5769.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 505} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  MAX(p.CreationDate) AS LastPostDate,
  STRING_AGG(DISTINCT tt.Name, ',') AS PostTypesMentioned,
  AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
  SUM(CASE WHEN v.VoteTypeId IN (2, 14, 16) THEN 1 ELSE 0 END) AS UpvoteEvents,
  SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS DeletionEvents,
  COUNT(DISTINCT b.Id) AS BadgesEarned,
  MAX(b.Date) AS LastBadgeDate
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id
  AND v.CreationDate = (
    SELECT MAX(CreationDate)
    FROM Votes
    WHERE UserId = u.Id
  )
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
LEFT JOIN (SELECT Id, Name FROM PostHistoryTypes) AS h ON 1=1
LEFT JOIN (
  SELECT
    p1.OwnerUserId,
    p1.Id,
    p1.Title,
    p1.PostTypeId,
    p1.CreationDate,
    p1.Score
  FROM Posts p1
) AS p ON p.OwnerUserId = u.Id
LEFT JOIN (
  SELECT
    p.Id AS PostId,
    COUNT(*) AS TagCount
  FROM Posts p
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
) AS t ON t.PostId = p.Id
WHERE
  u.AccountId IS NOT NULL
  OR u.Id IS NOT NULL
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  LastPostDate DESC NULLS LAST
LIMIT 100;