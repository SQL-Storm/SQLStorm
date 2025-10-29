-- {"query": "5130.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 444}
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
  AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  STRING_AGG(DISTINCT tt.Name, ',') AS PopularHistories,
  MAX(p.LastActivityDate) AS LastActivity,
  MIN(p.CreationDate) AS FirstPostDate,
  CASE
    WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) = 0 THEN NULL
    ELSE SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0)
  END AS AvgQuestionViews
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
  LEFT JOIN (
    SELECT Id, STRING_AGG(Name, ',') AS Name
    FROM PostHistoryTypes
    GROUP BY Id
  ) AS tt ON tt.Id = ph.PostHistoryTypeId
WHERE
  u.AccountId IS NOT NULL
  AND u.Reputation >= 0
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  u.Reputation DESC, u.DisplayName ASC
LIMIT 100;