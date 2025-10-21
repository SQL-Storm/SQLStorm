-- {"query": "57024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1081} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(v.CreationDate) AS LastVoteDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
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
        u.Id AS OwnerUserId,
        u.Reputation AS OwnerReputation,
        COUNT(v.Id) AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
        MAX(ph.CreationDate) AS LastEditDate
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, u.Id, u.Reputation
),
TagMetrics AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        COUNT(p.Id) AS PostsWithTag,
        SUM(p.Score) AS TotalScoreForTag,
        SUM(p.ViewCount) AS TotalViewsForTag,
        AVG(p.Score) AS AverageScoreForTag,
        AVG(p.ViewCount) AS AverageViewsForTag
    FROM
        Tags t
    LEFT JOIN
        Posts p ON t.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><''))
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
    ua.LastPostDate,
    ua.LastCommentDate,
    ua.LastVoteDate,
    pm.PostId,
    pm.PostTypeId,
    pm.PostCreationDate,
    pm.Score,
    pm.ViewCount,
    pm.AnswerCount,
    pm.CommentCount,
    pm.FavoriteCount,
    pm.TotalVotes,
    pm.TotalUpvotes,
    pm.TotalDownvotes,
    pm.LastEditDate,
    tm.TagId,
    tm.TagName,
    tm.TagCount,
    tm.PostsWithTag,
    tm.TotalScoreForTag,
    tm.TotalViewsForTag,
    tm.AverageScoreForTag,
    tm.AverageViewsForTag
FROM
    UserActivity ua
LEFT JOIN
    PostMetrics pm ON ua.UserId = pm.OwnerUserId
LEFT JOIN
    TagMetrics tm ON pm.PostId = tm.TagId
ORDER BY
    ua.Reputation DESC,
    pm.Score DESC,
    tm.TotalScoreForTag DESC
LIMIT 1000;
