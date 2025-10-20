-- {"query": "23099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 831} 

WITH TopUsers AS (
    SELECT u.Id, u.Reputation, u.DisplayName,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank,
           COALESCE(u.UpVotes + u.DownVotes, 0) AS TotalVotes
    FROM Users u
    WHERE u.Reputation > 1000 AND u.Location IS NOT NULL
),
UserBadges AS (
    SELECT b.UserId, b.Class, COUNT(b.Id) AS BadgeCount,
           STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId, b.Class
    HAVING COUNT(b.Id) > 5
),
ActivePosts AS (
    SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.Tags,
           CASE WHEN p.ClosedDate IS NULL THEN 'Open' ELSE 'Closed' END AS Status,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01' AND p.Tags LIKE '%sql%'
       OR p.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts q WHERE q.Id = p.ParentId AND q.Tags LIKE '%database%')
),
RankedPosts AS (
    SELECT ap.*, tu.DisplayName, ub.BadgeCount,
           RANK() OVER (PARTITION BY ap.OwnerUserId ORDER BY ap.Score DESC) AS PostRank,
           LAG(ap.Score) OVER (PARTITION BY ap.OwnerUserId ORDER BY ap.CreationDate) AS PrevScore
    FROM ActivePosts ap
    LEFT JOIN TopUsers tu ON ap.OwnerUserId = tu.Id
    LEFT JOIN UserBadges ub ON ap.OwnerUserId = ub.UserId AND ub.Class = 1
    WHERE ap.PositiveComments > 2 OR ap.ViewCount > 1000
),
EditsSummary AS (
    SELECT ph.PostId, COUNT(ph.Id) AS EditCount,
           MAX(ph.CreationDate) AS LastEdit,
           SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS MajorEdits
    FROM PostHistory ph
    WHERE ph.Comment IS NULL OR LENGTH(ph.Comment) > 50
    GROUP BY ph.PostId
    HAVING COUNT(ph.Id) >= 3
)
SELECT rp.Id AS PostId, rp.DisplayName, rp.BadgeCount, rp.PostRank,
       COALESCE(rp.PrevScore, 0) AS PreviousScore,
       rp.Status || ' - ' || NULLIF(SUBSTRING(rp.Tags, 1, 50), '') AS PostInfo,
       es.EditCount, es.MajorEdits,
       (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 8) AS AvgBounty
FROM RankedPosts rp
LEFT JOIN EditsSummary es ON rp.Id = es.PostId
WHERE rp.PostRank <= 5
UNION ALL
SELECT p.Id, u.DisplayName, NULL AS BadgeCount, NULL AS PostRank,
       NULL AS PreviousScore,
       'Duplicate - ' || lt.Name AS PostInfo,
       NULL AS EditCount, NULL AS MajorEdits,
       NULL AS AvgBounty
FROM PostLinks pl
INNER JOIN Posts p ON pl.PostId = p.Id
INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE lt.Id = 3 AND p.Score < 0
INTERSECT
SELECT p.Id, NULL, NULL, NULL, NULL, 'Tagged - ' || t.TagName, NULL, NULL, NULL
FROM Posts p
INNER JOIN Tags t ON p.Id = t.ExcerptPostId
WHERE t.Count > 10000 AND p.ContentLicense IS NOT NULL
ORDER BY PostId DESC;
