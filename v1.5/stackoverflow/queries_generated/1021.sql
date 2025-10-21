-- {"query": "1021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 474} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate >= NOW() - INTERVAL '1 year'
),
UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        COUNT(b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
),
RecentVotes AS (
    SELECT 
        v.PostId,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 4) AS OffensiveVotes,
        MAX(v.CreationDate) AS LastVoteDate
    FROM 
        Votes v
    WHERE 
        v.CreationDate >= NOW() - INTERVAL '30 days'
    GROUP BY 
        v.PostId
)
SELECT 
    p.PostId,
    p.Title,
    p.CreationDate,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    COALESCE(v.OffensiveVotes, 0) AS OffensiveVotes,
    COALESCE(b.BadgeCount, 0) AS UserBadgeCount,
    CASE 
        WHEN p.rn = 1 THEN 'Latest Post'
        ELSE 'Older Post'
    END AS PostStatus
FROM 
    RankedPosts p
LEFT JOIN 
    RecentVotes v ON p.PostId = v.PostId
LEFT JOIN 
    UserBadgeCounts b ON p.OwnerUserId = b.UserId
WHERE 
    b.BadgeCount IS NULL 
    OR b.BadgeCount > 2
ORDER BY 
    p.Score DESC, p.CreationDate DESC;
