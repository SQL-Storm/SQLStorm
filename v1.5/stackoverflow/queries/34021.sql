WITH RecentQuestions AS (
    SELECT p.Id AS QuestionId,
           p.Title,
           p.CreationDate,
           p.OwnerUserId,
           COUNT(a.Id) AS AnswerCount,
           AVG(a.Score) AS AvgAnswerScore,
           MAX(a.Score) AS MaxAnswerScore
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
    GROUP BY p.Id, p.Title, p.CreationDate, p.OwnerUserId
),
TopUsers AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COUNT(b.Id) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionCommentStats AS (
    SELECT p.Id AS QuestionId,
           COUNT(DISTINCT c.Id) AS TotalComments,
           COUNT(DISTINCT c.UserId) AS UniqueCommenters,
           MAX(c.CreationDate) AS LastCommentDate
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
),
TopTags AS (
    SELECT
        tag AS TagName
    FROM (
        SELECT UNNEST(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
    ) AS t
),
AggregatedTagStats AS (
    SELECT t.TagName,
           COUNT(*) AS TagCount,
           AVG(p.Score) AS AvgQuestionScore,
           SUM(p.ViewCount) AS TotalViews,
           COUNT(DISTINCT p.OwnerUserId) AS DistinctAskers
    FROM TopTags t
    JOIN Posts p ON p.PostTypeId = 1
                 AND (p.Tags LIKE '%' || t.TagName || '%' )
    GROUP BY t.TagName
),
LinkedQuestions AS (
    SELECT pl.PostId,
           pl.RelatedPostId,
           lt.Name AS LinkTypeName,
           p1.Title AS PostTitle,
           p2.Title AS RelatedPostTitle
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    JOIN Posts p1 ON p1.Id = pl.PostId
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE p1.PostTypeId = 1 AND p2.PostTypeId = 1
),
UserActivityWindow AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           COUNT(DISTINCT p.Id) AS PostsMade,
           COUNT(DISTINCT c.Id) AS CommentsMade,
           COUNT(DISTINCT b.Id) AS BadgesEarned,
           MIN(p.CreationDate) AS FirstPost,
           MAX(p.CreationDate) AS LastPost
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
                     AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    LEFT JOIN Comments c ON c.UserId = u.Id
                       AND c.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    LEFT JOIN Badges b ON b.UserId = u.Id
                       AND b.Date > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.OwnerUserId,
    ru.DisplayName AS QuestionOwnerDisplayName,
    rq.AnswerCount,
    rq.AvgAnswerScore,
    rq.MaxAnswerScore,
    qc.TotalComments,
    qc.UniqueCommenters,
    qc.LastCommentDate,
    au.Reputation,
    au.BadgeCount,
    au.GoldBadges,
    au.SilverBadges,
    au.BronzeBadges,
    ats.TagName,
    ats.TagCount,
    ats.AvgQuestionScore,
    ats.TotalViews,
    ats.DistinctAskers,
    lq.LinkTypeName,
    lq.RelatedPostId,
    lq.RelatedPostTitle,
    ua.PostsMade,
    ua.CommentsMade,
    ua.BadgesEarned,
    ua.FirstPost,
    ua.LastPost
FROM RecentQuestions rq
LEFT JOIN TopUsers au ON au.Id = rq.OwnerUserId
LEFT JOIN Users ru ON ru.Id = rq.OwnerUserId
LEFT JOIN QuestionCommentStats qc ON qc.QuestionId = rq.QuestionId
LEFT JOIN AggregatedTagStats ats ON ats.TagName = (
    SELECT TagName
    FROM TopTags
    WHERE TagName = (
        SELECT TagName
        FROM TopTags
        LIMIT 1
    )
    LIMIT 1
)
LEFT JOIN LinkedQuestions lq ON lq.PostId = rq.QuestionId AND lq.LinkTypeName = 'Duplicate'
LEFT JOIN UserActivityWindow ua ON ua.UserId = rq.OwnerUserId
WHERE rq.AnswerCount > 0
ORDER BY rq.CreationDate DESC
LIMIT 100;