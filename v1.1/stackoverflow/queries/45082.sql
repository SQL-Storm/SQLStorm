WITH RankedUserQuestions AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId = 1 
        AND p.Score > 10
        AND u.Reputation > 1000
),
PostTags AS (
    SELECT
        p.Id AS PostId,
        -- remove surrounding <> brackets and split by '><'
        TRIM(both '<' FROM TRIM(both '>' FROM p.Tags)) AS TagsStr
    FROM Posts p
),
TagRows AS (
    SELECT
        r.UserId,
        r.DisplayName,
        r.PostId,
        r.Title,
        r.Score,
        r.ViewCount,
        r.AnswerCount,
        t.Tag
    FROM RankedUserQuestions r
    JOIN PostTags pt ON pt.PostId = r.PostId
    CROSS JOIN LATERAL (
        -- split TagsStr into rows; use standard string-split approaches
        -- try regexp_split_to_table where available, otherwise emulate with UNNEST(STRING_TO_ARRAY(...))
        SELECT TRIM(tag) AS Tag
        FROM (
            SELECT regexp_split_to_table(pt.TagsStr, '><') AS tag
        ) s
    ) t
    WHERE r.PostRank <= 3
)
SELECT 
    tr.DisplayName,
    tr.Tag,
    COUNT(DISTINCT tr.PostId) AS TopQuestionCount,
    AVG(tr.Score) AS AvgScore,
    AVG(tr.ViewCount) AS AvgViews,
    AVG(tr.AnswerCount) AS AvgAnswers
FROM 
    TagRows tr
JOIN 
    Tags t ON tr.Tag = t.TagName
GROUP BY 
    tr.DisplayName, tr.Tag
ORDER BY 
    AvgScore DESC, 
    TopQuestionCount DESC, 
    AvgViews DESC
LIMIT 100;