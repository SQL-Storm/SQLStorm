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
        p.OwnerUserId
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY)
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation, p.OwnerUserId
),
PostTags AS (
    SELECT 
        Id AS PostId,
        -- convert from format like '<tag1><tag2>' to array ['tag1','tag2']
        -- use generic functions: remove leading/trailing angle brackets then split by '><'
        SUBSTRING(Tags FROM 2 FOR CHAR_LENGTH(Tags)-2) AS TagsStr
    FROM Posts
    WHERE Tags IS NOT NULL
),
PostTagPairs AS (
    -- normalize tags into rows
    SELECT
        pt.PostId,
        TRIM(tag) AS TagName
    FROM PostTags pt,
    -- split the tag string into rows using a generic method: regexp_split_to_table where available, else emulate with simple split
    -- use regexp_split_to_table name but also support systems that provide it; if not available replace accordingly
    regexp_split_to_table(pt.TagsStr, '><') AS tag
),
TagCounts AS (
    SELECT 
        TagName, 
        COUNT(*) AS PostCount
    FROM PostTagPairs
    GROUP BY TagName
),
UserActivity AS (
    SELECT 
        u.Id AS UserId, 
        COUNT(DISTINCT p.Id) AS PostsCreated, 
        COUNT(DISTINCT c.Id) AS CommentsCreated, 
        SUM(COALESCE(p.Score,0)) AS TotalScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id
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
    ua.PostsCreated, 
    ua.CommentsCreated, 
    ua.TotalScore,
    tp.TagName, 
    tc.PostCount
FROM RecentPosts rp
JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
-- join to tag pairs first, then aggregate counts to avoid non-inner join on subquery
LEFT JOIN PostTagPairs tp ON tp.PostId = rp.Id
LEFT JOIN TagCounts tc ON tc.TagName = tp.TagName
ORDER BY rp.CreationDate DESC, rp.Score DESC, ua.TotalScore DESC
LIMIT 100;