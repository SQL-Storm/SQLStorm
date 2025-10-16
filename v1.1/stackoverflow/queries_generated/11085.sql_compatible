WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS AuthorDisplayName, 
        u.Reputation AS AuthorReputation,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS HighestBounty,
        (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id) AS AnswerCount,
        (SELECT COUNT(*) FROM Comments WHERE PostId = p.Id) AS CommentCount
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '30 days'
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
), 
BadgeEarners AS (
    SELECT 
        b.UserId, 
        b.Name AS BadgeName, 
        b.Date AS BadgeDate, 
        u.DisplayName, 
        u.Reputation
    FROM Badges b
    JOIN Users u ON b.UserId = u.Id
    WHERE b.Date > CAST('2024-10-01' AS date) - INTERVAL '1 year'
), 
PostTagMetrics AS (
    SELECT 
        p.Id, 
        COUNT(DISTINCT t.Id) AS TagCount,
        STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) AS TagNames
    FROM Posts p
    JOIN Tags t ON p.Id = t.ExcerptPostId
    GROUP BY p.Id
), 
UserActivity AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS PostsCount, 
        COUNT(DISTINCT c.Id) AS CommentsCount, 
        SUM(p.Score) AS TotalScore, 
        SUM(p.ViewCount) AS TotalViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName
)
SELECT 
    r.Id AS PostId, 
    r.Title, 
    r.CreationDate, 
    r.Score, 
    r.ViewCount, 
    r.AuthorDisplayName, 
    r.AuthorReputation, 
    r.VoteCount, 
    r.UpVoteCount, 
    r.DownVoteCount, 
    r.HighestBounty, 
    r.AnswerCount, 
    r.CommentCount, 
    ptm.TagCount, 
    ptm.TagNames, 
    ua.PostsCount, 
    ua.CommentsCount, 
    ua.TotalScore, 
    ua.TotalViews, 
    STRING_AGG(be.BadgeName, ', ' ORDER BY be.BadgeDate) AS EarnedBadges
FROM RecentPosts r
JOIN PostTagMetrics ptm ON r.Id = ptm.Id
JOIN UserActivity ua ON r.Id = ua.Id
LEFT JOIN BadgeEarners be ON ua.Id = be.UserId
GROUP BY 
    r.Id, 
    r.Title, 
    r.CreationDate, 
    r.Score, 
    r.ViewCount, 
    r.AuthorDisplayName, 
    r.AuthorReputation, 
    r.VoteCount, 
    r.UpVoteCount, 
    r.DownVoteCount, 
    r.HighestBounty, 
    r.AnswerCount, 
    r.CommentCount, 
    ptm.TagCount, 
    ptm.TagNames, 
    ua.PostsCount, 
    ua.CommentsCount, 
    ua.TotalScore, 
    ua.TotalViews
ORDER BY 
    r.CreationDate DESC, 
    r.Score DESC, 
    r.ViewCount DESC
LIMIT 100;