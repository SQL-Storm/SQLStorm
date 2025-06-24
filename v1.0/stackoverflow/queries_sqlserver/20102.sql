
WITH UserReputation AS (
    SELECT 
        Id AS UserId,
        Reputation,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS Rank,
        CASE 
            WHEN Reputation >= 10000 THEN 'High Repute'
            WHEN Reputation >= 1000 THEN 'Medium Repute'
            ELSE 'Low Repute'
        END AS ReputationCategory
    FROM Users
),
PostDetails AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        ISNULL(p.ClosedDate, '1970-01-01') AS ClosureDate,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        LEN(p.Tags) - LEN(REPLACE(p.Tags, ',', '')) + 1 AS TagCount,
        YEAR(p.CreationDate) AS CreationYear
    FROM Posts p
),
PostHistoryCounts AS (
    SELECT 
        PostId,
        COUNT(*) AS EditCount
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6) 
    GROUP BY PostId
),
ActiveUsers AS (
    SELECT
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS ActivePostCount,
        SUM(ISNULL(ph.EditCount, 0)) AS TotalEdits,
        AVG(ISNULL(uv.Rank, 0)) AS AvgPostRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistoryCounts ph ON p.Id = ph.PostId
    LEFT JOIN UserReputation uv ON u.Id = uv.UserId
    WHERE u.LastAccessDate >= DATEADD(year, -1, '2024-10-01')
    GROUP BY u.Id, u.DisplayName
),
TopUsers AS (
    SELECT 
        DisplayName,
        ActivePostCount,
        TotalEdits,
        AvgPostRank,
        ROW_NUMBER() OVER (ORDER BY ActivePostCount DESC, TotalEdits DESC) AS UserRank
    FROM ActiveUsers
)
SELECT 
    tu.DisplayName,
    tu.ActivePostCount,
    tu.TotalEdits,
    CASE 
        WHEN tu.AvgPostRank IS NULL THEN 'Unknown'
        WHEN tu.AvgPostRank < 1 THEN 'No Posts'
        ELSE 'Active Contributor'
    END AS ContributorStatus,
    pd.Title,
    pd.TagCount,
    CASE 
        WHEN pd.UserPostRank = 1 THEN 'Latest'
        ELSE 'Earlier Post'
    END AS PostStatus,
    ISNULL(pts.Name, 'No Type') AS PostType
FROM TopUsers tu
LEFT JOIN PostDetails pd ON tu.ActivePostCount = pd.OwnerUserId
LEFT JOIN PostTypes pts ON pd.PostId = pts.Id
WHERE tu.UserRank <= 10
ORDER BY tu.ActivePostCount DESC, tu.TotalEdits DESC;
