-- {"query": "45082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 188108, "output_tokens": 32998} 
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
TagAnalytics AS (
    SELECT 
        UserId,
        DisplayName,
        PostId,
        Title,
        Score,
        AnswerCount,
        ViewCount,
        UNNEST(STRING_TO_ARRAY(SUBSTRING((SELECT Tags FROM Posts WHERE Id = PostId), 2, LENGTH((SELECT Tags FROM Posts WHERE Id = PostId))-2), '><')) AS Tag
    FROM 
        RankedUserQuestions
    WHERE 
        PostRank <= 3
)
SELECT 
    ta.DisplayName,
    ta.Tag,
    COUNT(DISTINCT ta.PostId) AS TopQuestionCount,
    AVG(ta.Score) AS AvgScore,
    AVG(ta.ViewCount) AS AvgViews,
    AVG(ta.AnswerCount) AS AvgAnswers
FROM 
    TagAnalytics ta
JOIN 
    Tags t ON ta.Tag = t.TagName
GROUP BY 
    ta.DisplayName, ta.Tag
ORDER BY 
    AvgScore DESC, 
    TopQuestionCount DESC, 
    AvgViews DESC
LIMIT 100;