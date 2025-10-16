-- {"query": "1013.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 476} 

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
        AND p.CreationDate >= NOW() - INTERVAL '1 year'
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
        ARRAY_AGG(b.Name) AS BadgeNames
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
    COALESCE(STRING_AGG(fr.BadgeNames::text, ', '), 'No Badges') AS UserBadges
FROM 
    FinalReport fr
ORDER BY 
    fr.Score DESC, fr.Title;
