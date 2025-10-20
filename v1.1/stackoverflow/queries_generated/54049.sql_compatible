WITH tagged_posts AS (
    SELECT
        p.Id,
        p.Score,
        p.AnswerCount,
        p.ViewCount,
        tl.tag AS TagName,
        v.VoteTypeId
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT value AS tag
        FROM (
            -- split tags like '<tag1><tag2>' into rows by replacing delimiters and splitting on '><'
            SELECT trim(t) AS value
            FROM (
                SELECT unnest(
                    regexp_split_to_array(
                        substr(p.Tags, 2, length(p.Tags) - 2),
                        '\\>\\<'
                    )
                ) AS t
            ) s
        ) s2
    ) tl
    JOIN Tags t ON t.TagName = tl.tag
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
tag_stats AS (
    SELECT
        TagName,
        COUNT(DISTINCT Id)                         AS QuestionCount,
        SUM(Score)                                 AS TotalScore,
        AVG(AnswerCount)                           AS AvgAnswers,
        AVG(ViewCount)                             AS AvgViews,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN VoteTypeId = 1 THEN 1 END) AS AcceptedAnswers
    FROM tagged_posts
    GROUP BY TagName
)
SELECT
    ts.TagName,
    ts.QuestionCount,
    ts.TotalScore,
    ts.AvgAnswers,
    ts.AvgViews,
    ts.UpVotes,
    ts.DownVotes,
    ts.AcceptedAnswers,
    ROUND(ts.TotalScore / NULLIF(ts.QuestionCount, 0), 2) AS AvgScorePerQuestion,
    ROW_NUMBER() OVER (ORDER BY ts.TotalScore DESC) AS Rnk
FROM tag_stats ts
WHERE ts.TotalScore > 0
ORDER BY Rnk
LIMIT 20;