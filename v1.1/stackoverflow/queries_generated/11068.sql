-- {"query": "11068.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 651} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation AS OwnerReputation,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS HighestBounty,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate > NOW() - INTERVAL '30 days' 
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
),
BadgeEarners AS (
    SELECT 
        b.UserId, 
        COUNT(b.Id) AS BadgeCount
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
PostTags AS (
    SELECT 
        p.Id, 
        t.TagName
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Id = t.ExcerptPostId
    WHERE 
        p.PostTypeId = 1
),
PostTagCounts AS (
    SELECT 
        pt.Id, 
        COUNT(pt.TagName) AS TagCount
    FROM 
        PostTags pt
    GROUP BY 
        pt.Id
)
SELECT 
    rp.Id AS PostId, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.OwnerDisplayName, 
    rp.OwnerReputation, 
    rp.VoteCount, 
    rp.UpVoteCount, 
    rp.DownVoteCount, 
    rp.HighestBounty, 
    rp.CommentCount, 
    COALESCE(be.BadgeCount, 0) AS BadgeCount, 
    COALESCE(ptc.TagCount, 0) AS TagCount
FROM 
    RecentPosts rp
LEFT JOIN 
    BadgeEarners be ON rp.OwnerUserId = be.UserId
LEFT JOIN 
    PostTagCounts ptc ON rp.Id = ptc.Id
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.BadgeCount DESC, 
    rp.TagCount DESC
LIMIT 10;
