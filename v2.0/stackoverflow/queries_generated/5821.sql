-- {"query": "5821.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 490} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  MAX(p.CreationDate) AS LastPostDate,
  COALESCE(SUM(v2.BountyAmount), 0) AS TotalBountiesGiven,
  STRING_AGG(DISTINCT CASE
                    WHEN b.Name IS NOT NULL THEN b.Name
                    ELSE NULL
                  END, ',') FILTER (WHERE b.Name IS NOT NULL) AS BadgesEarned,
  AVG(NULLIF(v.Score, NULL)) OVER (PARTITION BY u.Id) AS AvgPostScore,
  (SELECT AVG(p1.Score) FROM Posts p1 WHERE p1.OwnerUserId = u.Id) AS AvgOwnPostScore,
  COUNT(DISTINCT CASE WHEN c.PostId IS NOT NULL THEN c.Id END) AS CommentCountByUser,
  MIN(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate END) AS FirstQuestionDate,
  MAX(CASE WHEN p.PostTypeId = 1 THEN p.LastActivityDate END) AS LastQuestionActivity
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
LEFT JOIN PostLinks pl2 ON pl2.RelatedPostId = p.Id AND pl2.PostId <> p.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN (SELECT UserId, SUM(BountyAmount) AS BountyAmount
           FROM Votes
           WHERE VoteTypeId = 8 -- BountyStart
           GROUP BY UserId) v2 ON v2.UserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
ORDER BY
  u.Reputation DESC, LastPostDate DESC
LIMIT 100;