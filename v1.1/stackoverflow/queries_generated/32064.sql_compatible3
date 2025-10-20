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
        Posts.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
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
        Users.Id,
        Users.Reputation,
        Users.DisplayName
),
SplitTags AS (
    SELECT
        ap.PostId,
        TRIM(tag) AS tag
    FROM
        ActivePosts ap,
        UNNEST(string_to_array(REPLACE(REPLACE(ap.Tags, '<', ''), '>', '|'), '|')) AS t(tag)
    WHERE
        ap.Tags IS NOT NULL AND ap.Tags <> ''
),
PopularTags AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        SUM(ap.ViewCount) AS TotalViews,
        SUM(ap.Score) AS TotalScore
    FROM
        Tags t
    JOIN SplitTags st ON st.tag = t.TagName
    JOIN ActivePosts ap ON ap.PostId = st.PostId
    GROUP BY
        t.Id,
        t.TagName
    HAVING
        SUM(ap.ViewCount) > 5000
    ORDER BY
        TotalViews DESC
    LIMIT 10
),
PostPopularTag AS (
    -- produce one popular tag per post (if any) by joining rather than using EXISTS in a non-inner join
    SELECT
        ap.PostId,
        pt.TagName AS PopularTag
    FROM
        ActivePosts ap
    LEFT JOIN SplitTags st ON st.PostId = ap.PostId
    LEFT JOIN PopularTags pt ON st.tag = pt.TagName
    GROUP BY
        ap.PostId,
        pt.TagName
)
SELECT
    ap.PostId,
    ap.CreationDate,
    ap.Score,
    ap.ViewCount,
    ap.AnswerCount,
    ap.CommentCount,
    ap.FavoriteCount,
    ap.Tags,
    u.DisplayName AS PostOwner,
    ppt.PopularTag,
    ua.TotalComments,
    ua.TotalVotes,
    ua.TotalEdits
FROM
    ActivePosts ap
JOIN Users u ON ap.OwnerUserId = u.Id
LEFT JOIN PostPopularTag ppt ON ap.PostId = ppt.PostId
LEFT JOIN UserActivity ua ON ap.OwnerUserId = ua.UserId
ORDER BY
    ap.CreationDate DESC;