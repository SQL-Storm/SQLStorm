-- {"query": "39064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 3320} 

WITH QuestionsPerTag AS (
    SELECT 
        TRIM(split.tag)               AS TagName,
        COUNT(*)                      AS TotalQuestions
    FROM Posts p
    CROSS APPLY STRING_SPLIT(
        REPLACE(
            REPLACE(SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2), '><', ','), 
            '<', ''
        ), 
        ','
    ) AS split(tag)
    WHERE p.PostTypeId = 1
    GROUP BY TRIM(split.tag)
),
UserAnswerMetrics AS (
    SELECT
        u.Id                          AS UserId,
        u.DisplayName,
        COUNT(a.Id)                   AS AnswerCount,
        AVG(a.Score)                  AS AvgAnswerScore,
        MAX(a.CreationDate)           AS LastAnswerDate
    FROM Users u
    JOIN Posts a
      ON a.OwnerUserId = u.Id
     AND a.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName
),
TopAnswerers AS (
    SELECT
        TRIM(split.tag)               AS TagName,
        u.Id                          AS UserId,
        u.DisplayName,
        COUNT(*)                      AS AnswersToTag,
        RANK() OVER (
            PARTITION BY TRIM(split.tag)
            ORDER BY COUNT(*) DESC
        )                             AS TagAnswerRank
    FROM Posts a
    CROSS APPLY STRING_SPLIT(
        REPLACE(
            REPLACE(SUBSTRING(a.Tags, 2, LEN(a.Tags) - 2), '><', ','), 
            '<', ''
        ), 
        ','
    ) AS split(tag)
    JOIN Users u
      ON u.Id = a.OwnerUserId
    WHERE a.PostTypeId = 2
    GROUP BY TRIM(split.tag), u.Id, u.DisplayName
),
HotQuestions AS (
    SELECT
        p.Id                         AS QuestionId,
        p.Title,
        p.ViewCount,
        p.Score,
        p.CreationDate,
        RANK() OVER (
            PARTITION BY YEAR(p.CreationDate), MONTH(p.CreationDate)
            ORDER BY (p.ViewCount * p.Score) DESC
        )                            AS MonthlyHotRank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= DATEADD(year, -1, GETDATE())
),
FinalReport AS (
    SELECT
        ua.DisplayName,
        ua.AnswerCount,
        ua.AvgAnswerScore,
        ua.LastAnswerDate,
        qpt.TagName                  AS MostPopularTag,
        qpt.TotalQuestions,
        ta.AnswersToTag,
        ta.TagAnswerRank,
        hq.Title                     AS HottestQuestion,
        hq.ViewCount,
        hq.Score                     AS HotQuestionScore,
        hq.MonthlyHotRank
    FROM UserAnswerMetrics ua
    LEFT JOIN TopAnswerers ta
      ON ta.UserId = ua.UserId
     AND ta.TagAnswerRank = 1
    LEFT JOIN QuestionsPerTag qpt
      ON qpt.TagName = ta.TagName
    LEFT JOIN HotQuestions hq
      ON hq.MonthlyHotRank = 1
)
SELECT *
FROM FinalReport
ORDER BY AvgAnswerScore DESC, AnswerCount DESC
OPTION (MAXDOP 8, RECOMPILE);
