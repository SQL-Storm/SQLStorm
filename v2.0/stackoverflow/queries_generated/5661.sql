-- {"query": "5661.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 412} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostsCount,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
  COALESCE(SUM(v.BountyAmount),0) AS TotalBounty,
  MAX(p.CreationDate) AS LastActivePostDate,
  STRING_AGG(DISTINCT tt.Name, ',') FILTER (WHERE t.TagBased = 0) AS BadgesNotTagBased,
  COUNT(DISTINCT bl.BadgeId) AS BadgesEarned
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
LEFT JOIN (
  SELECT b.UserId, b.Id AS BadgeId
  FROM Badges b
  WHERE b.Class IN (1,2,3)
) bl ON bl.UserId = u.Id
LEFT JOIN PostHistory ph ON ph.UserId = u.Id
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN (
  SELECT Id, Name, 0 AS TagBased FROM PostLinks
) pl ON pl.Id = p.Id
LEFT JOIN (
  SELECT Id, Name, TagBased FROM Badges
) tb ON tb.Id = bl.BadgeId
LEFT JOIN Tags t ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
LEFT JOIN (
  SELECT Id, Name, 0 AS TagBased FROM PostLinks
) pr ON pr.Id = p.Id
GROUP BY
  u.Id, u.DisplayName, u.Reputation
ORDER BY
  Reputation DESC, PostsCount DESC
LIMIT 100;