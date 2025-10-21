-- {"query": "11028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 758} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        p.CommentCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (8, 9)
    WHERE p.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, u.DisplayName, u.Reputation
), 
PostTags AS (
    SELECT 
        p.Id AS PostId, 
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><'') AS Tags
    FROM Posts p
), 
TagCounts AS (
    SELECT 
        t.TagName, 
        COUNT(*) AS TagCount
    FROM Tags t
    JOIN PostTags pt ON t.Id = ANY(string_to_array(pt.Tags, ''><'')::int[])
    GROUP BY t.TagName
), 
UserActivity AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS PostsCount, 
        COUNT(DISTINCT c.Id) AS CommentsCount, 
        COUNT(DISTINCT v.Id) AS VotesCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName
)
SELECT 
    rp.Id AS PostId, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.AnswerCount, 
    rp.CommentCount, 
    rp.OwnerDisplayName, 
    rp.Reputation, 
    rp.TotalBounty,
    COUNT(DISTINCT pt.Tags) AS TagCount,
    ua.PostsCount,
    ua.CommentsCount,
    ua.VotesCount
FROM RecentPosts rp
JOIN PostTags pt ON rp.Id = pt.PostId
JOIN UserActivity ua ON rp.OwnerUserId = ua.Id
JOIN TagCounts tc ON tc.TagName = ANY(pt.Tags)
GROUP BY rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.AnswerCount, rp.CommentCount, rp.OwnerDisplayName, rp.Reputation, rp.TotalBounty, ua.PostsCount, ua.CommentsCount, ua.VotesCount
HAVING COUNT(DISTINCT pt.Tags) > 1 AND rp.Score > 10
ORDER BY rp.TotalBounty DESC, rp.Score DESC, rp.ViewCount DESC, rp.CreationDate DESC
LIMIT 10;
