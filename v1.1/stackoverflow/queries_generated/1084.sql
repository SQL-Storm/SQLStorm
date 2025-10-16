-- {"query": "1084.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 519} 

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
        COALESCE(p.ClosedDate, '1970-01-01') AS ClosedDate,
        p.Body,
        STRING_AGG(DISTINCT CONCAT_WS(' - ', ph.UserDisplayName, ph.Comment), '; ') AS CloseDetails
    FROM 
        Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (10, 11)    
    WHERE 
        p.ClosedDate IS NOT NULL
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Body
)
SELECT 
    up.UserId,
    up.DisplayName,
    up.Reputation,
    COALESCE(rp.Title, 'No Recent Questions') AS RecentQuestion,
    COALESCE(rp.CreationDate, 'N/A') AS QuestionDate,
    us.TotalBounties,
    us.BadgeCount,
    rcp.Title AS ClosedPostTitle,
    rcp.CloseDetails
FROM 
    UserStats us
LEFT JOIN RankedPosts rp ON us.UserId = rp.OwnerUserId AND rp.rn = 1
LEFT JOIN RecentClosedPosts rcp ON us.UserId = (SELECT OwnerUserId FROM Posts p WHERE p.Id = rcp.Id)
WHERE 
    us.Reputation > 100
ORDER BY 
    us.Reputation DESC, 
    COALESCE(rp.CreationDate, '1970-01-01') DESC;
