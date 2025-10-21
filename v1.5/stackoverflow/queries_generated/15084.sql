-- {"query": "15084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 587}
WITH TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgTagScore,
        FIRST_VALUE(p.Title) OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) AS TopPostTitle
    FROM Tags t
    JOIN Posts p ON t.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
    WHERE p.PostTypeId = 1
),
UserContribution AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS QuestionCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianQuestionScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName
)
SELECT 
    tp.TagName,
    uc.DisplayName,
    tp.PostCount,
    tp.AvgTagScore,
    uc.QuestionCount,
    uc.VoteCount,
    CASE 
        WHEN uc.MedianQuestionScore >= 5 THEN 'High Quality'
        WHEN uc.MedianQuestionScore BETWEEN 0 AND 4 THEN 'Medium Quality'
        ELSE 'Low Quality'
    END AS UserQuestionQuality,
    tp.TopPostTitle,
    COALESCE(
        (SELECT COUNT(*) 
         FROM PostLinks pl 
         WHERE pl.LinkTypeId = 3 
           AND pl.PostId IN (
               SELECT p.Id 
               FROM Posts p 
               WHERE p.Tags LIKE '%' || tp.TagName || '%'
           )
        ), 0) AS DuplicatePostCount
FROM TagPopularity tp
JOIN UserContribution uc ON 1=1
WHERE tp.PostCount > 10 
  AND uc.QuestionCount > 5
ORDER BY tp.AvgTagScore DESC, uc.VoteCount DESC
LIMIT 100;
