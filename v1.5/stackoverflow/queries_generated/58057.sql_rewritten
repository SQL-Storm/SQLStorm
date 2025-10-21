-- {"query": "58057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1265} 
WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           COUNT(DISTINCT p.Id) AS TotalPosts,
           COUNT(DISTINCT c.Id) AS TotalComments,
           COUNT(DISTINCT v.Id) AS TotalVotes,
           COUNT(DISTINCT b.Id) AS TotalBadges,
           AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore,
           MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3, 8)
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class IN (1, 2)
    WHERE u.Reputation > 10000
      AND EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 5)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, p.Score
),
TagEngagement AS (
    SELECT UserId, 
           ARRAY_AGG(DISTINCT REPLACE(REPLACE(pt.Tags, '><', ','), '<>', '')) AS ActiveTags,
           COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 2 THEN ph.PostId END) AS MajorEdits
    FROM Posts pt
    JOIN PostHistory ph ON pt.Id = ph.PostId AND ph.PostHistoryTypeId IN (2, 5, 6)
    WHERE pt.Tags IS NOT NULL
      AND LENGTH(pt.Tags) - LENGTH(REPLACE(pt.Tags, '><', '')) > 3
    GROUP BY UserId
),
PostLinkAnalysis AS (
    SELECT pl.PostId,
           COUNT(CASE WHEN lt.Name = 'Duplicate' THEN 1 END) AS DuplicateLinks,
           COUNT(CASE WHEN lt.Name = 'Linked' THEN 1 END) AS RelatedLinks
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
)
SELECT au.DisplayName, au.Reputation, au.TotalPosts, au.TotalComments,
       au.TotalVotes, au.TotalBadges, au.AvgPostScore,
       te.ActiveTags, te.MajorEdits,
       pla.DuplicateLinks, pla.RelatedLinks,
       RANK() OVER (ORDER BY au.TotalPosts DESC, au.Reputation DESC) AS ActivityRank
FROM ActiveUsers au
JOIN TagEngagement te ON au.Id = te.UserId
LEFT JOIN Posts p ON au.Id = p.OwnerUserId
LEFT JOIN PostLinkAnalysis pla ON p.Id = pla.PostId
WHERE au.LastPostDate > '2020-01-01'
  AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = au.Id AND b.Name LIKE '%Legendary%')
ORDER BY ActivityRank, au.LastPostDate DESC
LIMIT 100;