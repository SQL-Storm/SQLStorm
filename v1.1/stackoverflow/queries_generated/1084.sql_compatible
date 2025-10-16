WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.AnswerCount,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
        AND p.Score > 1
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounties,
        COUNT(b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
RecentClosedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        COALESCE(p.ClosedDate, CAST('1970-01-01' AS DATE)) AS ClosedDate,
        p.Body,
        STRING_AGG(DISTINCT (ph.UserDisplayName || ' - ' || ph.Comment), '; ') AS CloseDetails
    FROM 
        Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (10, 11)    
    WHERE 
        p.ClosedDate IS NOT NULL
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Body, p.ClosedDate
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    COALESCE(rp.Title, 'No Recent Questions') AS RecentQuestion,
    COALESCE(CAST(rp.CreationDate AS TEXT), 'N/A') AS QuestionDate,
    us.TotalBounties,
    us.BadgeCount,
    rcp.Title AS ClosedPostTitle,
    rcp.CloseDetails
FROM 
    UserStats us
LEFT JOIN RankedPosts rp ON us.UserId = rp.OwnerUserId AND rp.rn = 1
LEFT JOIN RecentClosedPosts rcp ON us.UserId = (
    SELECT p2.OwnerUserId FROM Posts p2 WHERE p2.Id = rcp.Id
)
WHERE 
    us.Reputation > 100
GROUP BY
    us.UserId,
    us.DisplayName,
    us.Reputation,
    rp.Title,
    rp.CreationDate,
    us.TotalBounties,
    us.BadgeCount,
    rcp.Title,
    rcp.CloseDetails
ORDER BY 
    us.Reputation DESC, 
    COALESCE(rp.CreationDate, CAST('1970-01-01' AS TIMESTAMP)) DESC;