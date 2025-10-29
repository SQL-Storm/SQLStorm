-- {"query": "5387.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 408} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(COALESCE(p.Score,0)) AS AvgPostScore,
  SUM(COALESCE(v.BountyAmount,0)) AS TotalBounty,
  MAX(p.CreationDate) AS LastPostDate,
  STRING_AGG(DISTINCT tt.Name, ',') AS TopCategories,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN (SELECT
             p.OwnerUserId AS UserForTag,
             tg.TagName
           FROM
             Posts p2
             JOIN Tags tg ON tg.ExcerptPostId = p2.Id
           GROUP BY p2.OwnerUserId, tg.TagName) AS t ON t.UserForTag = u.Id
LEFT JOIN (SELECT
             p2.OwnerUserId AS UserForTag2,
             unnest(string_to_array(p.Tags, '><')) AS TagName
           FROM Posts p2
           WHERE p2.Tags IS NOT NULL) AS tag_split ON tag_split.UserForTag2 = u.Id
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 5
ORDER BY
  u.Reputation DESC, LastPostDate DESC
LIMIT 100;