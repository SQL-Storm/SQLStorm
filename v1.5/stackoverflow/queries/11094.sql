-- {"query": "11094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 965} 
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
        COUNT(Posts.Id) AS PostCount, 
        SUM(Posts.Score) AS TotalScore, 
        COUNT(DISTINCT Posts.Id) AS UniquePosts, 
        SUM(CASE WHEN Posts.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked, 
        SUM(CASE WHEN Posts.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven
    FROM 
        Users
    LEFT JOIN 
        Posts ON Users.Id = Posts.OwnerUserId
    GROUP BY 
        Users.Id, Users.DisplayName, Users.Reputation
),
BadgeSummary AS (
    SELECT 
        Badges.UserId, 
        COUNT(Badges.Id) AS TotalBadges, 
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
        COUNT(Votes.Id) AS VoteCount, 
        SUM(CASE WHEN Votes.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
        SUM(CASE WHEN Votes.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
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
    UserActivity.DisplayName AS UserDisplayName, 
    UserActivity.Reputation, 
    UserActivity.PostCount, 
    UserActivity.TotalScore, 
    UserActivity.UniquePosts, 
    UserActivity.QuestionsAsked, 
    UserActivity.AnswersGiven, 
    BadgeSummary.TotalBadges, 
    BadgeSummary.GoldBadges, 
    BadgeSummary.SilverBadges, 
    BadgeSummary.BronzeBadges, 
    PostVotes.VoteCount, 
    PostVotes.UpVotes, 
    PostVotes.DownVotes
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
    RecentPosts.Score DESC;