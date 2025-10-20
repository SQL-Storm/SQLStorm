WITH recursive tag_list AS (
    SELECT
        q.Id AS QuestionId,
        TRIM(BOTH '<>' FROM q.Tags) AS TagsStr
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND q.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
),
split_tags AS (
    SELECT
        QuestionId,
        CASE
            WHEN TagsStr = '' THEN NULL
            ELSE
                SUBSTRING(TagsStr FROM 1 FOR (CASE WHEN POSITION('><' IN TagsStr) = 0 THEN LENGTH(TagsStr) ELSE POSITION('><' IN TagsStr)-1 END))
        END AS Tag,
        CASE
            WHEN POSITION('><' IN TagsStr) = 0 THEN ''
            ELSE SUBSTRING(TagsStr FROM (POSITION('><' IN TagsStr) + 2))
        END AS Rest
    FROM tag_list
    UNION ALL
    SELECT
        QuestionId,
        CASE
            WHEN Rest = '' THEN NULL
            ELSE
                SUBSTRING(Rest FROM 1 FOR (CASE WHEN POSITION('><' IN Rest) = 0 THEN LENGTH(Rest) ELSE POSITION('><' IN Rest)-1 END))
        END AS Tag,
        CASE
            WHEN POSITION('><' IN Rest) = 0 THEN ''
            ELSE SUBSTRING(Rest FROM (POSITION('><' IN Rest) + 2))
        END AS Rest
    FROM split_tags
    WHERE Rest IS NOT NULL AND Rest <> ''
),
recent_questions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
),
top_answerers AS (
    SELECT
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswererId,
        COUNT(*) AS AnswerCount,
        SUM(a.Score) AS TotalScore
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
      AND a.OwnerUserId IS NOT NULL
    GROUP BY a.ParentId, a.OwnerUserId
    HAVING COUNT(*) >= 2
),
popular_tags AS (
    SELECT
        Tag,
        COUNT(*) AS UsageCount
    FROM split_tags
    WHERE Tag IS NOT NULL
    GROUP BY Tag
    HAVING COUNT(*) > 20
),
tagged_questions AS (
    SELECT DISTINCT
        QuestionId,
        Tag
    FROM split_tags
    WHERE Tag IS NOT NULL
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    u.DisplayName AS QuestionOwner,
    ta.AnswererId,
    u2.DisplayName AS TopAnswerer,
    ta.AnswerCount,
    ta.TotalScore,
    COALESCE(b.BadgeCount, 0) AS TopAnswererBadges,
    ARRAY_AGG(tq.Tag ORDER BY tq.Tag) FILTER (WHERE tq.Tag IS NOT NULL) AS TopTags
FROM recent_questions rq
LEFT JOIN top_answerers ta ON ta.QuestionId = rq.QuestionId
LEFT JOIN Users u ON u.Id = rq.OwnerUserId
LEFT JOIN Users u2 ON u2.Id = ta.AnswererId
LEFT JOIN tagged_questions tq ON tq.QuestionId = rq.QuestionId
    AND tq.Tag IN (SELECT Tag FROM popular_tags)
LEFT JOIN (
    SELECT UserId, COUNT(*) AS BadgeCount
    FROM Badges
    WHERE Date > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
    GROUP BY UserId
) b ON b.UserId = ta.AnswererId
WHERE rq.Score > 0 AND rq.ViewCount > 50
GROUP BY
    rq.QuestionId, rq.Title, rq.CreationDate, rq.Score, rq.ViewCount,
    u.DisplayName, ta.AnswererId, u2.DisplayName, ta.AnswerCount, ta.TotalScore, b.BadgeCount
ORDER BY rq.ViewCount DESC, ta.TotalScore DESC
LIMIT 100;