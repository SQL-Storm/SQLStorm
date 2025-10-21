SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  AVG(COALESCE(v.BountyAmount, 0)) AS AvgBounty,
  MAX(p.CreationDate) AS LastPostDate,
  STRING_AGG(DISTINCT tt.Name, ',') AS TopTags,
  COUNT(DISTINCT bh.Id) FILTER (WHERE bh.PostHistoryTypeId = 52) AS HotNetworkQuestionVotes
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostHistory bh ON bh.PostId = p.Id
  LEFT JOIN Tags t ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
  LEFT JOIN PostHistoryTypes pht ON bh.PostHistoryTypeId = pht.Id
  LEFT JOIN (
    SELECT
      PT.Id,
      STRING_AGG(PT.Name, ',') AS Name
    FROM PostTypes PT
    GROUP BY PT.Id
  ) tt ON tt.Id = p.PostTypeId
WHERE
  u.Id IS NOT NULL
GROUP BY
  u.Id, u.DisplayName, u.Reputation
ORDER BY
  Reputation DESC, LastPostDate DESC
LIMIT 100;