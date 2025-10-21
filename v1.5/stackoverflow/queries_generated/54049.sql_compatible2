WITH tagged_posts AS (
    SELECT
        p.Id,
        p.Score,
        p.AnswerCount,
        p.ViewCount,
        t.TagName,
        v.VoteTypeId
    FROM Posts p
    JOIN LATERAL UNNEST(string_to_array(trim(BOTH '>' FROM p.Tags), '><')) AS tl(tag)
        ON p.PostTypeId = 1
    JOIN Tags t ON t.TagName = tl.tag
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
tag_stats AS (
    SELECT
        TagName,
        COUNT(DISTINCT Id)                         AS QuestionCount,
        SUM(Score)                                 AS TotalScore,
        AVG(AnswerCount)                           AS AvgAnswers,
        AVG(ViewCount)                             AS AvgViews,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswers
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