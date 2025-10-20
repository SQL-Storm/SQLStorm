WITH TopActiveTags AS (
    SELECT
        tag AS TagName,
        COUNT(*) AS QuestionCount
    FROM Posts
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(substring(Tags FROM 2 FOR char_length(Tags) - 2), '><') AS tag
    ) s
    WHERE PostTypeId = 1
      AND Tags IS NOT NULL
    GROUP BY tag
),
TopTags AS (
    SELECT TagName
    FROM TopActiveTags
    ORDER BY QuestionCount DESC
    LIMIT 10
),
QuestionTagPairs AS (
    SELECT
        p.Id AS PostId,
        tag AS TagName,
        p.CreationDate,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><') AS tag
    ) t
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
QuestionStats AS (
    SELECT
        qtp.PostId,
        qtp.CreationDate,
        qtp.Title,
        qtp.Score,
        qtp.ViewCount,
        qtp.AnswerCount,
        qtp.CommentCount,
        qtp.OwnerDisplayName,
        qtp.Reputation,
        string_agg(qtp.TagName, ',') AS TagsArrayStr
    FROM QuestionTagPairs qtp
    WHERE qtp.TagName IN (SELECT TagName FROM TopTags)
    GROUP BY qtp.PostId, qtp.CreationDate, qtp.Title, qtp.Score, qtp.ViewCount, qtp.AnswerCount, qtp.CommentCount, qtp.OwnerDisplayName, qtp.Reputation
),
AnswerCounts AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
DetailedPosts AS (
    SELECT
        qs.PostId,
        qs.CreationDate,
        qs.Title,
        qs.Score,
        qs.ViewCount,
        qs.AnswerCount,
        qs.CommentCount,
        qs.OwnerDisplayName,
        qs.Reputation,
        qs.TagsArrayStr,
        COALESCE(ac.AnswerCount, 0) AS NumberOfAnswers
    FROM QuestionStats qs
    LEFT JOIN AnswerCounts ac ON qs.PostId = ac.QuestionId
),
LatestComments AS (
    SELECT
        c.PostId,
        c.CreationDate AS CommentDate,
        c.UserDisplayName,
        c.Text AS CommentText
    FROM Comments c
    WHERE c.CreationDate = (
        SELECT MAX(c2.CreationDate)
        FROM Comments c2
        WHERE c2.PostId = c.PostId
    )
),
PostOrder AS (
    SELECT
        p.PostId,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS PostRank
    FROM (
        SELECT Id AS PostId, CreationDate FROM Posts WHERE PostTypeId IN (1,2)
        UNION
        SELECT PostId, CreationDate FROM Comments
    ) p
)
SELECT
    dp.PostId,
    dp.Title,
    dp.CreationDate,
    dp.Score,
    dp.ViewCount,
    dp.NumberOfAnswers,
    dp.OwnerDisplayName,
    dp.Reputation,
    dp.TagsArrayStr AS Tags,
    lc.CommentDate,
    lc.UserDisplayName AS CommentAuthor,
    lc.CommentText,
    po.PostRank
FROM
    DetailedPosts dp
LEFT JOIN LatestComments lc ON dp.PostId = lc.PostId
JOIN PostOrder po ON dp.PostId = po.PostId
WHERE
    po.PostRank <= 100
ORDER BY
    dp.CreationDate DESC;