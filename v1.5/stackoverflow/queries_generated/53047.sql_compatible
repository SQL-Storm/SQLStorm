WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RankInLocation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.Location
    HAVING COUNT(DISTINCT p.Id) > 10
),
TopTags AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagUsage,
        COUNT(DISTINCT p.Id) AS TaggedPosts,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesOnTaggedPosts
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE CONCAT('%', t.TagName, '%')
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE t.Count > 500
    GROUP BY t.Id, t.TagName, t.Count
),
QuestionAnalysis AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN a.Score > q.Score THEN 1 ELSE 0 END) AS BetterAnswers
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Comments c ON q.Id = c.PostId
    WHERE q.PostTypeId = 1 AND q.ViewCount > 10000
    GROUP BY q.Id, q.Title, q.ViewCount, q.AnswerCount, q.FavoriteCount
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.PostCount,
    ua.TotalScore,
    ua.AvgScore,
    ua.LastPostDate,
    ua.RankInLocation,
    tt.TagName,
    tt.TagUsage,
    tt.TaggedPosts,
    tt.UpvotesOnTaggedPosts,
    qa.Title,
    qa.ViewCount,
    qa.AnswerCount,
    qa.FavoriteCount,
    qa.CommentCount,
    qa.BetterAnswers
FROM UserActivity ua
INNER JOIN Posts p ON ua.UserId = p.OwnerUserId
INNER JOIN TopTags tt ON p.Tags LIKE CONCAT('%', tt.TagName, '%')
LEFT JOIN QuestionAnalysis qa ON p.Id = qa.QuestionId
WHERE ua.RankInLocation <= 5
AND tt.UpvotesOnTaggedPosts > 100
ORDER BY ua.Reputation DESC, tt.TagUsage DESC
LIMIT 1000;