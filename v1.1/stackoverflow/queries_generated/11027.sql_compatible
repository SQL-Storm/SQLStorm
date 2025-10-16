WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation AS OwnerReputation
    FROM 
        Posts p
    INNER JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
),
PostVotes AS (
    SELECT 
        PostId, 
        COUNT(*) AS VoteCount, 
        AVG(CASE WHEN VoteTypeId = 2 THEN 1.0 ELSE 0.0 END) AS UpvoteRate
    FROM 
        Votes
    GROUP BY 
        PostId
),
PostTags AS (
    SELECT 
        p.Id, 
        tag AS TagName
    FROM 
        Posts p,
        UNNEST(STRING_TO_ARRAY(p.Tags, ',')) AS t(tag)
    INNER JOIN 
        Tags tt ON t.tag = tt.TagName
),
PostActivity AS (
    SELECT 
        PostId, 
        COUNT(*) AS ActivityCount
    FROM 
        (
            SELECT PostId, CreationDate FROM Comments
            UNION ALL
            SELECT PostId, CreationDate FROM PostHistory
        ) AS Activity
    GROUP BY 
        PostId
)
SELECT 
    rp.Id, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.OwnerDisplayName, 
    rp.OwnerReputation, 
    pv.VoteCount, 
    pv.UpvoteRate, 
    STRING_AGG(pt.TagName, ', ') AS Tags, 
    pa.ActivityCount
FROM 
    RecentPosts rp
LEFT JOIN 
    PostVotes pv ON rp.Id = pv.PostId
LEFT JOIN 
    PostTags pt ON rp.Id = pt.Id
LEFT JOIN 
    PostActivity pa ON rp.Id = pa.PostId
GROUP BY 
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.OwnerDisplayName, rp.OwnerReputation, pv.VoteCount, pv.UpvoteRate, pa.ActivityCount
ORDER BY 
    rp.CreationDate DESC, 
    rp.Score DESC, 
    pa.ActivityCount DESC
LIMIT 10;