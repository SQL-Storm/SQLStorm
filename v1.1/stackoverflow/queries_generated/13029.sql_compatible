WITH UserScores AS (
    SELECT 
        u.Id,
        u.DisplayName,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
        RANK() OVER (ORDER BY SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) DESC) AS RankByUpvotes
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
HighActivityPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        COUNT(ph.Id) AS EditCount,
        LAG(p.LastEditDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PreviousEditDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS RowNum,
        p.CreationDate,
        p.LastEditDate,
        p.ViewCount
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.Score, p.CreationDate, p.LastEditDate, p.ViewCount
),
FinalCTE AS (
    SELECT
        us.DisplayName,
        us.TotalUpvotes,
        us.TotalDownvotes,
        hap.Title,
        hap.Score,
        hap.EditCount,
        COALESCE(EXTRACT(DAY FROM (hap.PreviousEditDate - hap.CreationDate)), 0) AS DaysSinceLastEdit,
        us.RankByUpvotes,
        hap.RowNum
    FROM UserScores us
    JOIN HighActivityPosts hap ON us.Id = hap.OwnerUserId
    WHERE us.RankByUpvotes <= 100
      AND hap.RowNum = 1
      AND hap.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
)
SELECT
    fc.DisplayName,
    fc.TotalUpvotes,
    fc.TotalDownvotes,
    fc.Title,
    fc.Score,
    fc.EditCount,
    fc.DaysSinceLastEdit,
    (fc.TotalUpvotes - fc.TotalDownvotes) * LN(fc.Score + 1) AS WeightedScore
FROM FinalCTE fc
WHERE fc.Title LIKE '%performance%'
  AND fc.EditCount > (SELECT AVG(EditCount) FROM HighActivityPosts)
ORDER BY WeightedScore DESC, fc.TotalUpvotes DESC
LIMIT 20;