-- {"query": "11013.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 863} 
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
    FROM 
        Posts
    WHERE 
        Posts.CreationDate > cast('2024-10-01' as date) - interval '30 days'
),
UserActivity AS (
    SELECT 
        Users.Id AS UserId, 
        Users.DisplayName, 
        Users.Reputation, 
        COUNT(Posts.Id) AS NumberOfPosts, 
        COUNT(DISTINCT CASE WHEN Posts.PostTypeId = 1 THEN Posts.Id END) AS NumberOfQuestions, 
        COUNT(DISTINCT CASE WHEN Posts.PostTypeId = 2 THEN Posts.Id END) AS NumberOfAnswers, 
        COUNT(DISTINCT CASE WHEN Posts.PostTypeId = 3 THEN Posts.Id END) AS NumberOfWikis, 
        SUM(Posts.Score) AS TotalScore
    FROM 
        Users
    LEFT JOIN 
        Posts ON Users.Id = Posts.OwnerUserId
    GROUP BY 
        Users.Id, 
        Users.DisplayName, 
        Users.Reputation
),
BadgeSummary AS (
    SELECT 
        Badges.UserId, 
        COUNT(DISTINCT Badges.Id) AS TotalBadges, 
        SUM(CASE WHEN Badges.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges, 
        SUM(CASE WHEN Badges.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges, 
        SUM(CASE WHEN Badges.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        Badges.UserId
),
PostVotes AS (
    SELECT 
        Votes.PostId, 
        COUNT(DISTINCT CASE WHEN Votes.VoteTypeId = 2 THEN Votes.UserId END) AS UpVotes, 
        COUNT(DISTINCT CASE WHEN Votes.VoteTypeId = 3 THEN Votes.UserId END) AS DownVotes, 
        COUNT(DISTINCT CASE WHEN Votes.VoteTypeId = 10 THEN Votes.UserId END) AS Favorites
    FROM 
        Votes
    GROUP BY 
        Votes.PostId
)
SELECT 
    RecentPosts.Id AS PostId, 
    RecentPosts.PostTypeId, 
    RecentPosts.AcceptedAnswerId, 
    RecentPosts.ParentId, 
    RecentPosts.CreationDate, 
    RecentPosts.Score, 
    RecentPosts.ViewCount, 
    UserActivity.DisplayName AS OwnerDisplayName, 
    UserActivity.NumberOfPosts, 
    UserActivity.NumberOfQuestions, 
    UserActivity.NumberOfAnswers, 
    UserActivity.NumberOfWikis, 
    UserActivity.TotalScore, 
    BadgeSummary.TotalBadges, 
    BadgeSummary.GoldBadges, 
    BadgeSummary.SilverBadges, 
    BadgeSummary.BronzeBadges, 
    PostVotes.UpVotes, 
    PostVotes.DownVotes, 
    PostVotes.Favorites
FROM 
    RecentPosts
LEFT JOIN 
    UserActivity ON RecentPosts.OwnerUserId = UserActivity.UserId
LEFT JOIN 
    BadgeSummary ON UserActivity.UserId = BadgeSummary.UserId
LEFT JOIN 
    PostVotes ON RecentPosts.Id = PostVotes.PostId
ORDER BY 
    RecentPosts.CreationDate DESC, 
    RecentPosts.Score DESC
LIMIT 100;