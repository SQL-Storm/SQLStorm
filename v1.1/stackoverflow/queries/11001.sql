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
        p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
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
        AND v.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
    GROUP BY 
        u.Id
),
PostTags AS (
    SELECT 
        p.Id AS PostId, 
        -- convert tags like '<tag1><tag2>' into an array of tags using standard SQL string functions
        CASE
          WHEN p.Tags IS NULL OR p.Tags = '' THEN NULL
          ELSE
            -- remove leading '<' and trailing '>' if present, then split on '><'
            (
              SELECT regexp_split_to_array(
                -- normalize edges so splitting on '><' yields tag texts
                TRIM(BOTH '<>' FROM p.Tags),
                '><'
              )
            )
        END AS Tags
    FROM 
        Posts p
    WHERE 
        p.Tags IS NOT NULL
),
PostTagCounts AS (
    SELECT 
        pt.PostId, 
        COALESCE(COUNT(t.tag), 0) AS TagCount
    FROM 
        PostTags pt
    LEFT JOIN LATERAL (
        SELECT unnest(pt.Tags) AS tag
    ) t ON pt.Tags IS NOT NULL
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
GROUP BY
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.OwnerUserId,
    ua.UpVotes,
    ua.DownVotes,
    ua.BountyStarts,
    ptc.TagCount
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    ptc.TagCount DESC
LIMIT 10;