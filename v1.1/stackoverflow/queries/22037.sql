-- {"query": "22037.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 619} 
WITH GoldBadgeUsers AS (
    SELECT DISTINCT u.Id, u.DisplayName, u.Reputation
    FROM Users u
    INNER JOIN Badges b ON u.Id = b.UserId
    WHERE b.Class = 1 AND b.Date >= '2020-01-01'
),
PostScores AS (
    SELECT p.Id, p.OwnerUserId, p.Title, p.Score, p.ViewCount, p.AnswerCount,
           CASE WHEN p.ViewCount IS NOT NULL THEN p.Score * 1.0 / NULLIF(p.ViewCount, 0) ELSE 0 END AS NormalizedScore,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY (p.Score * 1.0 / NULLIF(p.ViewCount, 0)) DESC, p.CreationDate ASC) AS Rn,
           string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '<>') AS TagArray
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL AND p.Score > 0
),
UserPostStats AS (
    SELECT g.Id AS UserId, g.DisplayName, g.Reputation, ps.Id AS PostId, ps.Title, ps.NormalizedScore,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ps.Id) AS CommentCount,
           COALESCE((
               SELECT SUM(v.BountyAmount) 
               FROM Votes v 
               WHERE v.PostId = ps.Id AND v.VoteTypeId = 8 AND v.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
           ), 0) AS TotalBounties,
           CASE WHEN ps.TagArray IS NOT NULL THEN array_to_string(ps.TagArray, ',') ELSE 'No Tags' END AS TagString,
           (SELECT ph2.CreationDate FROM PostHistory ph2 WHERE ph2.PostId = ps.Id AND ph2.PostHistoryTypeId IN (4,5,6) ORDER BY ph2.CreationDate DESC LIMIT 1) AS LastEdit
    FROM GoldBadgeUsers g
    LEFT OUTER JOIN PostScores ps ON g.Id = ps.OwnerUserId AND ps.Rn = 1
)
SELECT ups.UserId, ups.DisplayName, ups.Reputation, ups.PostId, ups.Title,
       ups.NormalizedScore * (1 + (ups.CommentCount * 0.1) + (ups.TotalBounties * 0.05)) AS AdjustedScore,
       ups.TagString,
       ups.LastEdit,
       CASE WHEN ups.LastEdit IS NULL THEN 'Never Edited' ELSE 'Edited' END AS EditStatus,
       (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = ups.PostId OR pl.RelatedPostId = ups.PostId) AS LinkCount
FROM UserPostStats ups
WHERE ups.NormalizedScore > 0.01 OR ups.TotalBounties > 0
ORDER BY AdjustedScore DESC, ups.Reputation DESC
LIMIT 100;