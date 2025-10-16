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
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
           p.CreationDate
    FROM Posts p
    WHERE (p.CreationDate >= DATE '2020-01-01' AND p.Tags LIKE '%sql%')
       OR (p.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts q WHERE q.Id = p.ParentId AND q.Tags LIKE '%database%'))
),
RankedPosts AS (
    SELECT ap.Id, ap.PostTypeId, ap.OwnerUserId, ap.Score, ap.ViewCount, ap.Tags, ap.Status, ap.PositiveComments, ap.CreationDate,
           tu.DisplayName, ub.BadgeCount,
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
),
FirstQuery AS (
    SELECT rp.Id AS PostId, rp.DisplayName, rp.BadgeCount, rp.PostRank,
           COALESCE(rp.PrevScore, 0) AS PreviousScore,
           rp.Status || ' - ' || NULLIF(SUBSTRING(rp.Tags FROM 1 FOR 50), '') AS PostInfo,
           es.EditCount, es.MajorEdits,
           (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 8) AS AvgBounty
    FROM RankedPosts rp
    LEFT JOIN EditsSummary es ON rp.Id = es.PostId
    WHERE rp.PostRank <= 5
),
SecondQuery AS (
    SELECT p.Id AS PostId,
           u.DisplayName,
           CAST(NULL AS INTEGER) AS BadgeCount,
           CAST(NULL AS INTEGER) AS PostRank,
           CAST(NULL AS INTEGER) AS PreviousScore,
           'Duplicate - ' || lt.Name AS PostInfo,
           CAST(NULL AS INTEGER) AS EditCount,
           CAST(NULL AS INTEGER) AS MajorEdits,
           CAST(NULL AS NUMERIC) AS AvgBounty
    FROM PostLinks pl
    INNER JOIN Posts p ON pl.PostId = p.Id
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE lt.Id = 3 AND p.Score < 0
),
ThirdQuery AS (
    SELECT p.Id AS PostId,
           CAST(NULL AS TEXT) AS DisplayName,
           CAST(NULL AS INTEGER) AS BadgeCount,
           CAST(NULL AS INTEGER) AS PostRank,
           CAST(NULL AS INTEGER) AS PreviousScore,
           'Tagged - ' || t.TagName AS PostInfo,
           CAST(NULL AS INTEGER) AS EditCount,
           CAST(NULL AS INTEGER) AS MajorEdits,
           CAST(NULL AS NUMERIC) AS AvgBounty
    FROM Posts p
    INNER JOIN Tags t ON p.Id = t.ExcerptPostId
    WHERE t.Count > 10000 AND p.ContentLicense IS NOT NULL
)
SELECT *
FROM (
    SELECT * FROM FirstQuery
    UNION ALL
    SELECT * FROM SecondQuery
    INTERSECT
    SELECT * FROM ThirdQuery
) AS combined
ORDER BY PostId DESC;