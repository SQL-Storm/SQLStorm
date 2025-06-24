WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn,
        COUNT(c.Id) AS CommentCount
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.PostTypeId
),
UserReputation AS (
    SELECT 
        u.Id AS UserId,
        COALESCE(SUM(b.Class), 0) AS TotalBadges,
        MAX(u.Reputation) AS Reputation
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
),
PostEngagement AS (
    SELECT 
        p.Id AS PostId,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        p.Id
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    ue.Reputation,
    ue.TotalBadges,
    pe.VoteCount,
    pe.UpVotes,
    pe.DownVotes
FROM 
    RankedPosts rp
JOIN 
    UserReputation ue ON ue.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = rp.PostId)
LEFT JOIN 
    PostEngagement pe ON pe.PostId = rp.PostId
WHERE 
    rp.rn <= 5 AND 
    (rp.ViewCount IS NULL OR rp.ViewCount > 100) AND 
    (ue.Reputation > 50 OR ue.TotalBadges > 2)
ORDER BY 
    rp.Score DESC,
    rp.CreationDate ASC;

-- Additional complexity with string expressions and NULL logic
SELECT 
    rp.PostId,
    CONCAT('Post Title: ', COALESCE(rp.Title, 'Untitled'), ', Created on: ', TO_CHAR(rp.CreationDate, 'YYYY-MM-DD HH24:MI:SS')) AS FormattedTitle,
    CASE 
        WHEN ue.Reputation IS NULL THEN 'Reputation data unavailable'
        WHEN ue.Reputation >= 1000 THEN 'High Reputation'
        ELSE 'Moderate Reputation'
    END AS ReputationCategory
FROM 
    RankedPosts rp
JOIN 
    UserReputation ue ON ue.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = rp.PostId)
WHERE 
    rp.ViewCount IS NOT NULL AND rp.ViewCount > 50
UNION ALL
SELECT 
    rp.PostId,
    'Post Title: ' || COALESCE(rp.Title, 'Untitled') || ', Created on: ' || TO_CHAR(rp.CreationDate, 'YYYY-MM-DD HH24:MI:SS'),
    CASE 
        WHEN ue.Reputation IS NULL THEN 'Reputation data unavailable'
        WHEN ue.Reputation >= 1000 THEN 'High Reputation'
        ELSE 'Moderate Reputation'
    END
FROM 
    RankedPosts rp
LEFT JOIN 
    UserReputation ue ON ue.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = rp.PostId)
WHERE 
    rp.ViewCount IS NULL AND COALESCE(rp.ViewCount, -1) <= 50
ORDER BY 
    FormattedTitle ASC;
