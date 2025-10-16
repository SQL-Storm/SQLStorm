WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank,
        COALESCE(u.Reputation, 0) AS UserReputation
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
),
PopularPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.Score,
        rp.UserReputation,
        COUNT(v.Id) AS VoteCount
    FROM 
        RankedPosts rp
    LEFT JOIN 
        Votes v ON rp.PostId = v.PostId
    GROUP BY 
        rp.PostId, rp.Title, rp.CreationDate, rp.OwnerUserId, rp.Score, rp.UserReputation
    HAVING 
        COUNT(v.Id) > 10
),
UserBadges AS (
    SELECT 
        b.UserId,
        -- ARRAY_AGG is not supported in all dialects; use string aggregation as a fallback
        -- Produce a comma-separated list of badge names for compatibility
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
FinalReport AS (
    SELECT 
        pp.PostId,
        pp.Title,
        pp.OwnerUserId,
        pp.Score,
        pp.VoteCount,
        ub.BadgeNames
    FROM 
        PopularPosts pp
    LEFT JOIN 
        UserBadges ub ON pp.OwnerUserId = ub.UserId
    WHERE 
        pp.UserReputation > 100 
        AND pp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
)
SELECT 
    fr.PostId,
    fr.Title,
    fr.OwnerUserId,
    fr.Score,
    COALESCE(fr.VoteCount, 0) AS VoteCount,
    COALESCE(fr.BadgeNames, 'No Badges') AS UserBadges
FROM 
    FinalReport fr
ORDER BY 
    fr.Score DESC, fr.Title;