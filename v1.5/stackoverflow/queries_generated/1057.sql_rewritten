-- {"query": "1057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 403} 
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        COALESCE(bp.BadgeCount, 0) AS BadgeCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS Rank
    FROM 
        Posts p
    LEFT JOIN (
        SELECT 
            UserId, 
            COUNT(*) AS BadgeCount 
        FROM 
            Badges 
        GROUP BY 
            UserId
    ) bp ON p.OwnerUserId = bp.UserId
    WHERE 
        p.PostTypeId IN (1, 2) -- only Questions and Answers
), RecentActivity AS (
    SELECT 
        PostId,
        COUNT(*) AS RecentVotes,
        MAX(CreationDate) AS LastVoteDate
    FROM 
        Votes v
    WHERE 
        v.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days' 
    GROUP BY 
        PostId
), CombinedData AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.BadgeCount,
        ra.RecentVotes,
        ra.LastVoteDate
    FROM 
        RankedPosts rp
    LEFT JOIN 
        RecentActivity ra ON rp.PostId = ra.PostId
    WHERE 
        rp.Rank = 1
)
SELECT 
    cd.PostId,
    cd.Title,
    cd.CreationDate,
    cd.Score,
    cd.BadgeCount,
    COALESCE(cd.RecentVotes, 0) AS RecentVotes,
    CASE 
        WHEN cd.LastVoteDate IS NULL THEN 'No Votes in Last 30 Days'
        ELSE 'Votes Received'
    END AS VoteActivity
FROM 
    CombinedData cd
ORDER BY 
    cd.Score DESC, 
    cd.BadgeCount DESC;