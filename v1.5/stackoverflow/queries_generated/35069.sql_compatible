WITH HighlyViewedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.ViewCount >= (
          SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ViewCount) FROM Posts WHERE PostTypeId = 1
      )
),
TopContributors AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        SUM(p.Score) AS TotalScore,
        COUNT(p.Id) AS NumPosts
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1,2)
    WHERE u.CreationDate < CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
    HAVING SUM(p.Score) > 1000
),
TagPopularity AS (
    SELECT
        TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM t.TagName)) AS TagName,
        COUNT(*) AS UsageCount
    FROM (
        SELECT unnest(string_to_array(substring(Tags, 2, length(Tags) - 2), '><')) AS TagName
        FROM Posts
        WHERE PostTypeId = 1 AND Tags IS NOT NULL
    ) AS t
    GROUP BY TagName
),
MostPopularTags AS (
    SELECT TagName
    FROM TagPopularity
    ORDER BY UsageCount DESC
    LIMIT 10
)
SELECT
    q.QuestionId,
    q.Title,
    q.ViewCount,
    q.CreationDate,
    q.Score,
    q.AnswerCount,
    u.DisplayName AS QuestionOwner,
    COUNT(DISTINCT a.Id) AS NumAnswersFromTopContributors,
    (
        SELECT ARRAY_AGG(DISTINCT t.TagName)
        FROM MostPopularTags t
        WHERE CONCAT('<', t.TagName, '>') = ANY(string_to_array(qp.Tags, '><'))
    ) AS PopularTagsOnQuestion
FROM HighlyViewedQuestions q
LEFT JOIN Users u ON q.OwnerUserId = u.Id
LEFT JOIN Posts qp ON q.QuestionId = qp.Id
LEFT JOIN Posts a ON a.ParentId = q.QuestionId AND a.PostTypeId = 2
LEFT JOIN TopContributors tc ON a.OwnerUserId = tc.UserId
GROUP BY
    q.QuestionId, q.Title, q.ViewCount, q.CreationDate, q.Score, q.AnswerCount, u.DisplayName, qp.Tags
ORDER BY
    q.ViewCount DESC,
    q.Score DESC
LIMIT 50;