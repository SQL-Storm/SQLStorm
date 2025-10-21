-- {"query": "32064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 502} 

WITH ActivePosts AS (
    SELECT
        Posts.Id AS PostId,
        Posts.CreationDate,
        Posts.Score,
        Posts.ViewCount,
        Posts.OwnerUserId,
        Posts.Tags,
        COALESCE(Posts.AnswerCount, 0) AS AnswerCount,
        Posts.CommentCount,
        COALESCE(Posts.FavoriteCount, 0) AS FavoriteCount
    FROM
        Posts
    WHERE
        Posts.CreationDate > current_date - interval '1 year'
        AND Posts.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT
        Users.Id AS UserId,
        Users.Reputation,
        Users.DisplayName,
        COUNT(DISTINCT Comments.Id) AS TotalComments,
        COUNT(DISTINCT Votes.Id) AS TotalVotes,
        COUNT(DISTINCT PostHistory.Id) AS TotalEdits
    FROM
        Users
    LEFT JOIN Comments ON Users.Id = Comments.UserId
    LEFT JOIN Votes ON Users.Id = Votes.UserId
    LEFT JOIN PostHistory ON Users.Id = PostHistory.UserId
    GROUP BY
        Users.Id, Users.Reputation, Users.DisplayName
),
PopularTags AS (
    SELECT
        Tags.TagName,
        SUM(ActivePosts.ViewCount) AS TotalViews,
        SUM(ActivePosts.Score) AS TotalScore
    FROM
        Tags
    JOIN ActivePosts ON Tags.TagName = ANY(string_to_array(ActivePosts.Tags, '>'))
    GROUP BY
        Tags.TagName
    HAVING
        SUM(ActivePosts.ViewCount) > 5000
    ORDER BY
        TotalViews DESC
    LIMIT 10
)
SELECT
    ActivePosts.PostId,
    ActivePosts.CreationDate,
    ActivePosts.Score,
    ActivePosts.ViewCount,
    ActivePosts.AnswerCount,
    ActivePosts.CommentCount,
    ActivePosts.FavoriteCount,
    ActivePosts.Tags,
    Users.DisplayName AS PostOwner,
    PopularTags.TagName AS PopularTag,
    UserActivity.TotalComments,
    UserActivity.TotalVotes,
    UserActivity.TotalEdits
FROM
    ActivePosts
JOIN Users ON ActivePosts.OwnerUserId = Users.Id
LEFT JOIN PopularTags ON PopularTags.TagName = ANY(string_to_array(ActivePosts.Tags, '>'))
LEFT JOIN UserActivity ON ActivePosts.OwnerUserId = UserActivity.UserId
ORDER BY
    ActivePosts.CreationDate DESC;
