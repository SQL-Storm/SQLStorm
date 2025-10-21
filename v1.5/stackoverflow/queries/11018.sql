WITH RecentPosts AS (
    SELECT 
        Posts.Id, 
        Posts.PostTypeId, 
        Posts.AcceptedAnswerId, 
        Posts.ParentId, 
        Posts.CreationDate, 
        Posts.Score, 
        Posts.ViewCount, 
        Posts.Body, 
        Posts.OwnerUserId, 
        Posts.OwnerDisplayName, 
        Posts.LastEditorUserId, 
        Posts.LastEditorDisplayName, 
        Posts.LastEditDate, 
        Posts.LastActivityDate, 
        Posts.Title, 
        Posts.Tags, 
        Posts.AnswerCount, 
        Posts.CommentCount, 
        Posts.FavoriteCount, 
        Posts.ClosedDate, 
        Posts.CommunityOwnedDate, 
        Posts.ContentLicense
    FROM Posts
    WHERE Posts.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
),
UserActivity AS (
    SELECT 
        Users.Id AS UserId, 
        Users.DisplayName, 
        Users.Reputation, 
        COALESCE(SUM(CASE WHEN Votes.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN Votes.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        COUNT(Posts.Id) AS PostsCount,
        COUNT(DISTINCT Comments.Id) AS CommentsCount
    FROM Users
    LEFT JOIN Posts ON Users.Id = Posts.OwnerUserId
    LEFT JOIN Votes ON Users.Id = Votes.UserId
    LEFT JOIN Comments ON Users.Id = Comments.UserId
    GROUP BY Users.Id, Users.DisplayName, Users.Reputation
),
BadgeSummary AS (
    SELECT 
        Badges.UserId, 
        COUNT(*) AS TotalBadges, 
        SUM(CASE WHEN Badges.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges, 
        SUM(CASE WHEN Badges.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges, 
        SUM(CASE WHEN Badges.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY Badges.UserId
)
SELECT 
    RecentPosts.Id AS PostId, 
    RecentPosts.PostTypeId, 
    RecentPosts.AcceptedAnswerId, 
    RecentPosts.ParentId, 
    RecentPosts.CreationDate, 
    RecentPosts.Score, 
    RecentPosts.ViewCount, 
    RecentPosts.Body, 
    RecentPosts.OwnerUserId, 
    RecentPosts.OwnerDisplayName, 
    RecentPosts.LastEditorUserId, 
    RecentPosts.LastEditorDisplayName, 
    RecentPosts.LastEditDate, 
    RecentPosts.LastActivityDate, 
    RecentPosts.Title, 
    RecentPosts.Tags, 
    RecentPosts.AnswerCount, 
    RecentPosts.CommentCount, 
    RecentPosts.FavoriteCount, 
    RecentPosts.ClosedDate, 
    RecentPosts.CommunityOwnedDate, 
    RecentPosts.ContentLicense,
    COALESCE(UserActivity.DisplayName, RecentPosts.OwnerDisplayName) AS OwnerDisplayNameAlias, 
    UserActivity.Reputation, 
    UserActivity.UpVotes, 
    UserActivity.DownVotes, 
    UserActivity.PostsCount, 
    UserActivity.CommentsCount,
    BadgeSummary.TotalBadges, 
    BadgeSummary.GoldBadges, 
    BadgeSummary.SilverBadges, 
    BadgeSummary.BronzeBadges
FROM RecentPosts
LEFT JOIN UserActivity ON RecentPosts.OwnerUserId = UserActivity.UserId
LEFT JOIN BadgeSummary ON UserActivity.UserId = BadgeSummary.UserId
ORDER BY RecentPosts.CreationDate DESC, RecentPosts.Score DESC
LIMIT 100;