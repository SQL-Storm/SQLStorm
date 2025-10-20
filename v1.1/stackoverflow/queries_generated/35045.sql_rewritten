-- {"query": "35045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 677} 
WITH
TopTags AS (
    SELECT
        t.TagName,
        t.Count
    FROM
        Tags t
    WHERE
        t.Count > 1000
    ORDER BY
        t.Count DESC
    LIMIT 10
),
PopularQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.OwnerUserId
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
        AND p.Score > 5
        AND p.ViewCount > 1000
),
TagQuestions AS (
    SELECT
        tq.TagName,
        q.Id AS QuestionId,
        q.OwnerUserId
    FROM
        TopTags tq
        JOIN PopularQuestions q ON POSITION('<' || tq.TagName || '>' IN q.Tags) > 0
),
AnswerStats AS (
    SELECT
        tq.TagName,
        COUNT(DISTINCT a.Id) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore
    FROM
        TagQuestions tq
        JOIN Posts a ON a.ParentId = tq.QuestionId AND a.PostTypeId = 2
    GROUP BY
        tq.TagName
),
TopContributors AS (
    SELECT
        tq.TagName,
        a.OwnerUserId,
        u.DisplayName,
        COUNT(*) AS AnswerCount,
        SUM(a.Score) AS TotalScore
    FROM
        TagQuestions tq
        JOIN Posts a ON a.ParentId = tq.QuestionId AND a.PostTypeId = 2
        JOIN Users u ON u.Id = a.OwnerUserId
    GROUP BY
        tq.TagName, a.OwnerUserId, u.DisplayName
    HAVING
        COUNT(*) > 5
),
CommentStats AS (
    SELECT
        tq.TagName,
        COUNT(c.Id) FILTER (WHERE c.Score > 0) AS PositiveComments,
        AVG(c.Score) FILTER (WHERE c.Score IS NOT NULL) AS AvgCommentScore
    FROM
        TagQuestions tq
        JOIN Comments c ON c.PostId = tq.QuestionId
    GROUP BY
        tq.TagName
)
SELECT
    t.TagName,
    t.Count AS TagUsage,
    a.TotalAnswers,
    a.AvgAnswerScore,
    a.MaxAnswerScore,
    c.PositiveComments,
    c.AvgCommentScore,
    tc.OwnerUserId AS TopAnswererId,
    tc.DisplayName AS TopAnswerer,
    tc.AnswerCount AS TopAnswererAnswers,
    tc.TotalScore AS TopAnswererScore
FROM
    TopTags t
    LEFT JOIN AnswerStats a ON t.TagName = a.TagName
    LEFT JOIN CommentStats c ON t.TagName = c.TagName
    LEFT JOIN LATERAL (
        SELECT
            tc.OwnerUserId,
            tc.DisplayName,
            tc.AnswerCount,
            tc.TotalScore
        FROM
            TopContributors tc
        WHERE
            tc.TagName = t.TagName
        ORDER BY
            tc.TotalScore DESC
        LIMIT 1
    ) tc ON TRUE
ORDER BY
    t.Count DESC;