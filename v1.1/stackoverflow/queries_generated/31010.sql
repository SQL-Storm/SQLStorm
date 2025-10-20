-- {"query": "31010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 413} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 0) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.CreationDate DESC) AS TagRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 
        AND p.Score > 10
        AND p.CreationDate >= NOW() - INTERVAL '1 year'
),
UserActivities AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        SUM(v.BountyAmount) AS TotalBounty,
        COUNT(DISTINCT v.PostId) AS BountyPosts,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM 
        Users u
    LEFT JOIN 
        Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (8, 9)  -- BountyStart and BountyClose
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    u.DisplayName AS UserDisplayName,
    u.TotalBounty,
    u.BountyPosts,
    u.TotalBadges
FROM 
    RankedPosts rp
JOIN 
    Users p ON rp.CreationDate > p.CreationDate -- Posts created after user account creation
JOIN 
    UserActivities u ON p.Id = u.UserId 
WHERE 
    rp.TagRank <= 5  -- Top 5 posts per tag
ORDER BY 
    rp.Score DESC, rp.ViewCount DESC
LIMIT 50;
