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
        rqp.UserId,
        rqp.DisplayName,
        rqp.PostId,
        rqp.Title,
        rqp.Score,
        rqp.AnswerCount,
        rqp.ViewCount,
        UNNEST(string_to_array(substr((SELECT Tags FROM Posts WHERE Id = rqp.PostId), 2, LENGTH((SELECT Tags FROM Posts WHERE Id = rqp.PostId)) - 2), '><')) AS Tag
    FROM 
        RankedUserQuestions rqp
    WHERE 
        rqp.PostRank <= 3
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
    AVG(ta.Score) DESC, 
    COUNT(DISTINCT ta.PostId) DESC, 
    AVG(ta.ViewCount) DESC
LIMIT 100;