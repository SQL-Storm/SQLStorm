-- {"query": "35020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 720} 
WITH TopAskers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionsAsked,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AvgQuestionScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.CreationDate > NOW() - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
MostActiveTags AS (
    SELECT
        t.TagName,
        SUM(t.Count) AS TotalTagCount
    FROM Tags t
    GROUP BY t.TagName
    ORDER BY TotalTagCount DESC
    LIMIT 20
),
TopQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS TagList,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '2 years'
      AND p.ViewCount > 1000
      AND p.Score >= 5
),
QuestionTagDetails AS (
    SELECT
        tq.QuestionId,
        tq.Title,
        tq.Score,
        tq.ViewCount,
        tag.TagName,
        tq.OwnerUserId
    FROM TopQuestions tq
    JOIN LATERAL (
        SELECT trim(both ' ' from unnest(tq.TagList)) AS TagName
    ) tag ON TRUE
),
JoinedDetails AS (
    SELECT
        ta.UserId,
        ta.DisplayName,
        ta.QuestionsAsked,
        ta.TotalViews,
        ta.AvgQuestionScore,
        qtd.QuestionId,
        qtd.Title AS QuestionTitle,
        qtd.Score AS QuestionScore,
        qtd.ViewCount AS QuestionViews,
        qtd.TagName
    FROM TopAskers ta
    JOIN QuestionTagDetails qtd ON ta.UserId = qtd.OwnerUserId
    WHERE qtd.TagName IN (SELECT TagName FROM MostActiveTags)
)
SELECT
    jd.DisplayName,
    jd.QuestionsAsked,
    jd.TotalViews,
    ROUND(jd.AvgQuestionScore, 2) AS AvgQuestionScore,
    jd.QuestionId,
    jd.QuestionTitle,
    jd.QuestionScore,
    jd.QuestionViews,
    jd.TagName,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
    COUNT(DISTINCT b.Id) AS BadgesEarned
FROM JoinedDetails jd
LEFT JOIN Comments c ON jd.QuestionId = c.PostId
LEFT JOIN Votes v ON jd.QuestionId = v.PostId
LEFT JOIN Badges b ON jd.UserId = b.UserId
GROUP BY
    jd.DisplayName, jd.QuestionsAsked, jd.TotalViews, jd.AvgQuestionScore,
    jd.QuestionId, jd.QuestionTitle, jd.QuestionScore, jd.QuestionViews, jd.TagName
HAVING COUNT(DISTINCT c.Id) > 2
ORDER BY jd.QuestionsAsked DESC, jd.TotalViews DESC, jd.AvgQuestionScore DESC
LIMIT 50;