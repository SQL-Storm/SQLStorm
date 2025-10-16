-- {"query": "11057.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 1171} 
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
        Posts.CreationDate > cast('2024-10-01' as date) - INTERVAL '30' DAY
),
UserActivity AS (
    SELECT 
        Users.Id AS UserId, 
        Users.DisplayName, 
        COALESCE(SUM(CASE WHEN Posts.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsPosted, 
        COALESCE(SUM(CASE WHEN Posts.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersPosted, 
        COALESCE(SUM(CASE WHEN Posts.PostTypeId = 2 THEN Posts.Score ELSE 0 END), 0) AS AnswerScore, 
        COALESCE(SUM(CASE WHEN Posts.PostTypeId = 1 THEN Posts.ViewCount ELSE 0 END), 0) AS QuestionViews, 
        COALESCE(COUNT(DISTINCT CASE WHEN Posts.PostTypeId = 1 THEN Posts.Id END), 0) AS UniqueQuestions, 
        COALESCE(COUNT(DISTINCT CASE WHEN Posts.PostTypeId = 2 THEN Posts.Id END), 0) AS UniqueAnswers
    FROM 
        Users
    LEFT JOIN 
        Posts ON Users.Id = Posts.OwnerUserId
    GROUP BY 
        Users.Id, Users.DisplayName
),
BadgeEarnings AS (
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
PostTags AS (
    SELECT 
        Posts.Id, 
        Tags.TagName, 
        Posts.Title, 
        Posts.Body
    FROM 
        Posts
    JOIN 
        Tags ON Posts.Tags LIKE '%' || Tags.TagName || '%'
    WHERE 
        Posts.PostTypeId = 1
),
PostVotes AS (
    SELECT 
        Votes.PostId, 
        Votes.VoteTypeId, 
        COUNT(Votes.Id) AS VoteCount, 
        SUM(CASE WHEN Votes.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes, 
        SUM(CASE WHEN Votes.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM 
        Votes
    GROUP BY 
        Votes.PostId, Votes.VoteTypeId
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
    UserActivity.DisplayName, 
    UserActivity.QuestionsPosted, 
    UserActivity.AnswersPosted, 
    UserActivity.AnswerScore, 
    UserActivity.QuestionViews, 
    UserActivity.UniqueQuestions, 
    UserActivity.UniqueAnswers, 
    BadgeEarnings.TotalBadges, 
    BadgeEarnings.GoldBadges, 
    BadgeEarnings.SilverBadges, 
    BadgeEarnings.BronzeBadges, 
    PostTags.TagName, 
    PostVotes.VoteCount, 
    PostVotes.Upvotes, 
    PostVotes.Downvotes
FROM 
    RecentPosts
LEFT JOIN 
    UserActivity ON RecentPosts.OwnerUserId = UserActivity.UserId
LEFT JOIN 
    BadgeEarnings ON UserActivity.UserId = BadgeEarnings.UserId
LEFT JOIN 
    PostTags ON RecentPosts.Id = PostTags.Id
LEFT JOIN 
    PostVotes ON RecentPosts.Id = PostVotes.PostId
ORDER BY 
    RecentPosts.CreationDate DESC, 
    RecentPosts.Score DESC;