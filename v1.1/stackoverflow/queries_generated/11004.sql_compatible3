WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation AS OwnerReputation
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
        COUNT(p.Id) AS TotalPosts, 
        SUM(p.Score) AS TotalScore, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Posts p
    JOIN 
        Votes v ON p.Id = v.PostId
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
    GROUP BY 
        u.Id
),
PostTags AS (
    SELECT 
        p.Id, 
        -- convert tags like '<tag1><tag2>' into array ['tag1','tag2']
        string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><') AS TagsArray
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
),
TagCounts AS (
    SELECT 
        t.TagName, 
        COUNT(*) AS TagCount
    FROM (
        SELECT unnest(TagsArray) AS TagName
        FROM PostTags
    ) t
    GROUP BY 
        t.TagName
)
SELECT 
    rp.Id, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.OwnerDisplayName, 
    rp.OwnerReputation,
    ua.TotalPosts, 
    ua.TotalScore, 
    ua.UpVotes, 
    ua.DownVotes,
    STRING_AGG(DISTINCT tc.TagName, ', ') AS Tags
FROM 
    RecentPosts rp
JOIN 
    UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN 
    PostTags pt ON rp.Id = pt.Id
LEFT JOIN 
    TagCounts tc ON tc.TagName = ANY (pt.TagsArray)
GROUP BY 
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.OwnerDisplayName, rp.OwnerReputation, ua.TotalPosts, ua.TotalScore, ua.UpVotes, ua.DownVotes
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    ua.TotalScore DESC
LIMIT 10;