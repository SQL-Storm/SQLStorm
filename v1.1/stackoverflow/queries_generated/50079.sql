-- {"query": "50079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 816} 

WITH GoldBadgeHolders AS (
    SELECT
        u.Id,
        u.Reputation
    FROM
        Users u
    WHERE
        u.LastAccessDate > u.CreationDate + interval '2 year'
        AND EXISTS (
            SELECT 1
            FROM Badges b
            WHERE b.UserId = u.Id AND b.Class = 1
        )
),
QuestionTagDetails AS (
    SELECT
        p.Id AS PostId,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.ViewCount,
        EXTRACT(YEAR FROM p.CreationDate) AS QuestionYear,
        gbh.Reputation AS AskerReputation,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM
        Posts p
    JOIN
        GoldBadgeHolders gbh ON p.OwnerUserId = gbh.Id
    WHERE
        p.PostTypeId = 1
        AND p.Tags IS NOT NULL
),
AggregatedTagStats AS (
    SELECT
        QuestionYear,
        TagName,
        COUNT(DISTINCT PostId) AS NumQuestions,
        SUM(AnswerCount) AS TotalAnswers,
        SUM(CommentCount) AS TotalComments,
        AVG(Score) AS AvgQuestionScore,
        AVG(ViewCount) AS AvgViewCount,
        AVG(AskerReputation) AS AvgAskerReputation
    FROM
        QuestionTagDetails
    GROUP BY
        QuestionYear,
        TagName
    HAVING
        COUNT(DISTINCT PostId) > 20
),
RankedTagPerformance AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY QuestionYear ORDER BY (AvgAskerReputation * 0.5 + AvgQuestionScore * 0.3 + AvgViewCount * 0.2) DESC) as PerformanceRank
    FROM
        AggregatedTagStats
)
SELECT
    rtp.QuestionYear,
    rtp.PerformanceRank,
    rtp.TagName,
    rtp.NumQuestions,
    rtp.TotalAnswers,
    CAST(rtp.TotalAnswers AS DECIMAL) / rtp.NumQuestions AS AnswersPerQuestion,
    rtp.AvgAskerReputation,
    rtp.AvgQuestionScore,
    rtp.AvgViewCount,
    (SELECT u.DisplayName
     FROM Users u
     JOIN Posts a ON u.Id = a.OwnerUserId
     JOIN Posts q ON a.ParentId = q.Id
     WHERE a.PostTypeId = 2
       AND EXTRACT(YEAR FROM q.CreationDate) = rtp.QuestionYear
       AND q.Tags LIKE '%<' || rtp.TagName || '>%'
     GROUP BY u.DisplayName
     ORDER BY COUNT(a.Id) DESC, AVG(a.Score) DESC
     LIMIT 1) AS TopAnswerer,
    (SELECT MAX(ph.CreationDate)
     FROM PostHistory ph
     JOIN Posts p_hist ON ph.PostId = p_hist.Id
     WHERE ph.PostHistoryTypeId IN (4, 5, 6)
       AND EXTRACT(YEAR FROM p_hist.CreationDate) = rtp.QuestionYear
       AND p_hist.Tags LIKE '%<' || rtp.TagName || '>%'
    ) AS LastEditDate
FROM
    RankedTagPerformance rtp
WHERE
    rtp.PerformanceRank <= 5
ORDER BY
    rtp.QuestionYear DESC,
    rtp.PerformanceRank ASC;
