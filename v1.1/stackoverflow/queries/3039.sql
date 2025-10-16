WITH PostStats AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        u.DisplayName AS OwnerName,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS PostRank
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
),
RecentPostTypes AS (
    SELECT DISTINCT
        pts.PostTypeId
    FROM
        PostStats pts
    WHERE
        pts.PostRank <= 5
),
ActiveQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplay,
        p.Score,
        p.Tags,
        p.AnswerCount,
        p.CommentCount
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
        AND p.Tags IS NOT NULL
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore
    FROM
        Posts a
    WHERE
        a.PostTypeId = 2
    GROUP BY
        a.ParentId
),
QuestionDetails AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.CreationDate,
        q.OwnerDisplay,
        q.Score,
        q.Tags,
        q.AnswerCount,
        q.CommentCount,
        COALESCE(a.AnswerCount, 0) AS TotalAnswers,
        COALESCE(a.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(a.MaxAnswerScore, 0) AS MaxAnswerScore
    FROM
        ActiveQuestions q
    LEFT JOIN
        AnswerStats a ON q.QuestionId = a.QuestionId
),
RecentQuestions AS (
    SELECT
        *
    FROM
        QuestionDetails
    WHERE
        CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.OwnerDisplay,
    rq.Score,
    string_agg(trim(t.TagName), ', ' ORDER BY trim(t.TagName)) AS Tags,
    rq.AnswerCount,
    rq.CommentCount,
    rq.TotalAnswers,
    rq.AvgAnswerScore,
    rq.MaxAnswerScore,
    CASE WHEN rs.PostTypeId IS NULL THEN 'Other' ELSE 'Question/Answer' END AS TypeCategory
FROM
    RecentQuestions rq
LEFT JOIN
    Posts p ON rq.QuestionId = p.Id
-- expand tags into rows using a standard split approach: split on commas and trim; emulate UNNEST by using a derived table with numbers up to a reasonable max (e.g., 50)
LEFT JOIN (
    SELECT
        qid,
        CASE WHEN pos = 1 THEN split_part(tags, ',', 1)
             WHEN pos = 2 THEN split_part(tags, ',', 2)
             WHEN pos = 3 THEN split_part(tags, ',', 3)
             WHEN pos = 4 THEN split_part(tags, ',', 4)
             WHEN pos = 5 THEN split_part(tags, ',', 5)
             WHEN pos = 6 THEN split_part(tags, ',', 6)
             WHEN pos = 7 THEN split_part(tags, ',', 7)
             WHEN pos = 8 THEN split_part(tags, ',', 8)
             WHEN pos = 9 THEN split_part(tags, ',', 9)
             WHEN pos = 10 THEN split_part(tags, ',', 10)
             WHEN pos = 11 THEN split_part(tags, ',', 11)
             WHEN pos = 12 THEN split_part(tags, ',', 12)
             WHEN pos = 13 THEN split_part(tags, ',', 13)
             WHEN pos = 14 THEN split_part(tags, ',', 14)
             WHEN pos = 15 THEN split_part(tags, ',', 15)
             WHEN pos = 16 THEN split_part(tags, ',', 16)
             WHEN pos = 17 THEN split_part(tags, ',', 17)
             WHEN pos = 18 THEN split_part(tags, ',', 18)
             WHEN pos = 19 THEN split_part(tags, ',', 19)
             WHEN pos = 20 THEN split_part(tags, ',', 20)
        END AS TagName
    FROM (
        SELECT
            rq.QuestionId AS qid,
            rq.Tags AS tags,
            1 AS pos FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 2 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 3 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 4 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 5 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 6 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 7 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 8 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 9 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 10 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 11 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 12 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 13 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 14 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 15 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 16 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 17 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 18 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 19 FROM RecentQuestions rq
        UNION ALL SELECT rq.QuestionId, rq.Tags, 20 FROM RecentQuestions rq
    ) s
    WHERE split_part(tags, ',', pos) IS NOT NULL AND split_part(tags, ',', pos) <> ''
) t ON t.qid = rq.QuestionId
LEFT JOIN
    RecentPostTypes rs ON p.PostTypeId = rs.PostTypeId
WHERE
    (p.PostTypeId IN (1, 2))
GROUP BY
    rq.QuestionId, rq.Title, rq.CreationDate, rq.OwnerDisplay, rq.Score, rq.AnswerCount, rq.CommentCount, rq.TotalAnswers, rq.AvgAnswerScore, rq.MaxAnswerScore, rs.PostTypeId;