WITH UserScore AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        u.Reputation, 
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes, 
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        RANK() OVER (ORDER BY COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) - COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) DESC) AS UserRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PopularTags AS (
    SELECT 
        tag AS Tag,
        COUNT(p.Id) AS TagCount
    FROM Posts p,
         UNNEST(string_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '><')) AS t(tag)
    WHERE p.PostTypeId = 1
    GROUP BY tag
    HAVING COUNT(p.Id) > 10
),
RecentPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.CreationDate, 
        p.ViewCount,
        p.Tags,
        COALESCE(SUM(CASE WHEN c.PostId IS NOT NULL THEN 1 ELSE 0 END), 0) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS RecentPostRank,
        p.OwnerUserId,
        p.LastActivityDate
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
    GROUP BY p.Id, p.Title, p.CreationDate, p.ViewCount, p.Tags, p.LastActivityDate, p.OwnerUserId
),
RecentPostTags AS (
    SELECT
        rp.PostId,
        trim(t.tag) AS Tag
    FROM RecentPosts rp,
    LATERAL (
        SELECT x.tag
        FROM UNNEST(string_to_array(substring(rp.Tags FROM 2 FOR (length(rp.Tags) - 2)), '><')) AS x(tag)
    ) AS t
)
SELECT 
    us.DisplayName, 
    us.Reputation, 
    us.UserRank, 
    rp.Title, 
    rp.CreationDate, 
    rp.ViewCount, 
    rp.CommentCount, 
    pt.Tag AS PopularTag,
    pt.TagCount
FROM UserScore us
JOIN RecentPosts rp ON us.UserId = rp.OwnerUserId
JOIN PostLinks pl ON pl.PostId = rp.PostId
LEFT JOIN RecentPostTags rpt ON rpt.PostId = rp.PostId
LEFT JOIN PopularTags pt ON pt.Tag = rpt.Tag
WHERE us.UserRank <= 10 
  AND rp.RecentPostRank = 1
ORDER BY us.UserRank, rp.ViewCount DESC;