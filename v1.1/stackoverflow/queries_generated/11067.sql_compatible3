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
    JOIN 
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
        p.Id AS PostId, 
        TRIM(BOTH '<' FROM tag) AS TagName
    FROM 
        Posts p,
        LATERAL (
          SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags)-2)), '><')) AS tag
        ) s
),
PostTagCounts AS (
    SELECT 
        PostId, 
        COUNT(*) AS TagCount
    FROM 
        PostTags
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
    COALESCE(pv.VoteCount, 0) AS VoteCount, 
    COALESCE(pv.UpvoteRate, 0) AS UpvoteRate, 
    COALESCE(ptc.TagCount, 0) AS TagCount
FROM 
    RecentPosts rp
LEFT JOIN 
    PostVotes pv ON rp.Id = pv.PostId
LEFT JOIN 
    PostTagCounts ptc ON rp.Id = ptc.PostId
GROUP BY
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    pv.VoteCount,
    pv.UpvoteRate,
    ptc.TagCount
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.CreationDate DESC
LIMIT 100;