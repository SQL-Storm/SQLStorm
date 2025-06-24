
WITH RankedUsers AS (
    SELECT 
        Id,
        DisplayName,
        Reputation,
        RANK() OVER (ORDER BY Reputation DESC) as ReputationRank
    FROM 
        Users
), 
RecentPosts AS (
    SELECT 
        p.Id as PostId,
        p.OwnerUserId, 
        p.Title, 
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as RecentRank
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= DATEADD(YEAR, -1, '2024-10-01 12:34:56')
), 
UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(rp.PostId) as PostCount,
        COALESCE(SUM(rp.Score), 0) as TotalScore,
        MAX(rp.CreationDate) as LastPostDate
    FROM 
        RankedUsers u
    LEFT JOIN 
        RecentPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName
), 
ClosedPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.ClosedDate,
        COUNT(ph.Id) as ClosureCount
    FROM 
        Posts p
    JOIN 
        PostHistory ph ON p.Id = ph.PostId 
    WHERE 
        ph.PostHistoryTypeId = 10
    GROUP BY 
        p.Id, p.Title, p.ClosedDate
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.PostCount,
    ups.TotalScore,
    ups.LastPostDate,
    COALESCE(cp.ClosureCount, 0) as ClosedPostCount,
    CASE 
        WHEN ups.LastPostDate IS NULL THEN 'No posts'
        WHEN ups.LastPostDate < DATEADD(DAY, -30, '2024-10-01 12:34:56') THEN 'Inactive'
        ELSE 'Active'
    END as UserStatus
FROM 
    UserPostStats ups
LEFT JOIN 
    ClosedPosts cp ON ups.UserId = (SELECT TOP 1 OwnerUserId FROM Posts WHERE Id = cp.PostId)
WHERE 
    ups.PostCount > 0
ORDER BY 
    ups.TotalScore DESC, ups.PostCount DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
