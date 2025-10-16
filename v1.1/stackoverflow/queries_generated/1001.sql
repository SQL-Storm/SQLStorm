-- {"query": "1001.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 570} 

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
    GROUP BY u.Id
),
PopularTags AS (
    SELECT 
        unnest(string_to_array(substring(Tags, 2, length(Tags) - 2), '><')) AS Tag,
        COUNT(p.Id) AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY Tag
    HAVING COUNT(p.Id) > 10
),
RecentPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.CreationDate, 
        p.ViewCount,
        COALESCE(SUM(CASE WHEN c.PostId IS NOT NULL THEN 1 ELSE 0 END), 0) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS RecentPostRank
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
    GROUP BY p.Id
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
JOIN RecentPosts rp ON us.UserId = rp.PostId
JOIN PostLinks pl ON pl.PostId = rp.PostId
LEFT JOIN PopularTags pt ON pt.Tag = ANY(string_to_array(rp.Tags, ','))
WHERE us.UserRank <= 10 
AND rp.RecentPostRank = 1
ORDER BY us.UserRank, rp.ViewCount DESC;
