WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(c.Id) AS TotalComments,
        COALESCE(SUM(p.Score),0) AS TotalPostScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceived,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate
),
PostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COUNT(v.Id) AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        COUNT(c.Id) AS TotalCommentsOnPost,
        p.OwnerUserId,
        p.Tags
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.OwnerUserId, p.Tags
),
TagStatistics AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        COUNT(p.Id) AS PostsWithTag,
        COALESCE(SUM(p.Score),0) AS TotalScoreOfTaggedPosts,
        COALESCE(SUM(p.ViewCount),0) AS TotalViewsOfTaggedPosts,
        AVG(p.Score) AS AverageScoreOfTaggedPosts,
        AVG(p.ViewCount) AS AverageViewsOfTaggedPosts
    FROM
        Tags t
    LEFT JOIN
        Posts p ON POSITION(('<' || t.TagName || '>') IN p.Tags) > 0
    GROUP BY
        t.Id, t.TagName, t.Count
)
SELECT
    ua.UserId,
    ua.Reputation,
    ua.UserCreationDate,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalComments,
    ua.TotalPostScore,
    ua.TotalUpVotesReceived,
    ua.TotalDownVotesReceived,
    ua.LastPostActivityDate,
    ua.LastCommentDate,
    pm.PostId,
    pm.PostTypeId,
    pm.PostCreationDate,
    pm.Score AS PostScore,
    pm.ViewCount,
    pm.AnswerCount,
    pm.CommentCount,
    pm.FavoriteCount,
    pm.TotalVotes,
    pm.TotalUpVotes,
    pm.TotalDownVotes,
    pm.TotalCommentsOnPost,
    ts.TagId,
    ts.TagName,
    ts.TagCount,
    ts.PostsWithTag,
    ts.TotalScoreOfTaggedPosts,
    ts.TotalViewsOfTaggedPosts,
    ts.AverageScoreOfTaggedPosts,
    ts.AverageViewsOfTaggedPosts
FROM
    UserActivity ua
LEFT JOIN
    PostMetrics pm ON ua.UserId = pm.OwnerUserId
LEFT JOIN
    TagStatistics ts ON POSITION(('<' || ts.TagName || '>') IN COALESCE(pm.Tags,'')) > 0
ORDER BY
    ua.Reputation DESC,
    pm.PostCreationDate DESC,
    ts.TagCount DESC
LIMIT 1000;