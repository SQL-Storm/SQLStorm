WITH RecentPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        p.OwnerUserId
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')
        AND p.PostTypeId = 1
),
UserActivity AS (
    SELECT 
        u.Id AS UserId, 
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END), 0) AS BountyStarts
    FROM 
        Users u
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    WHERE 
        v.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')
    GROUP BY 
        u.Id
),
PostTags AS (
    SELECT 
        p.Id AS PostId, 
        string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), ',') AS Tags
    FROM 
        Posts p
    WHERE 
        p.Tags IS NOT NULL
),
PostTagCounts AS (
    SELECT 
        pt.PostId, 
        COUNT(*) AS TagCount
    FROM 
        PostTags pt
    GROUP BY 
        pt.PostId
)
SELECT 
    rp.Id AS PostId, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.OwnerDisplayName, 
    rp.OwnerReputation, 
    ua.UpVotes, 
    ua.DownVotes, 
    ua.BountyStarts, 
    ptc.TagCount
FROM 
    RecentPosts rp
LEFT JOIN 
    UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN 
    PostTagCounts ptc ON rp.Id = ptc.PostId
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    ptc.TagCount DESC
LIMIT 10;