-- {"query": "50099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1026} 

WITH QuestionTags AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        t.TagName
    FROM Posts p,
         unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL AND p.DeletionDate IS NULL
),
TagPerformance AS (
    SELECT
        qt.TagName,
        EXTRACT(YEAR FROM qt.CreationDate) AS Year,
        COUNT(*) AS QuestionsAsked,
        SUM(qt.Score) AS TotalScore,
        AVG(qt.Score) AS AvgScore,
        SUM(qt.ViewCount) AS TotalViews,
        AVG(qt.AnswerCount) AS AvgAnswers,
        COUNT(DISTINCT qt.OwnerUserId) AS UniqueAskers
    FROM QuestionTags qt
    GROUP BY qt.TagName, EXTRACT(YEAR FROM qt.CreationDate)
    HAVING COUNT(*) > 100 AND SUM(qt.ViewCount) > 50000
),
RankedTagPerformance AS (
    SELECT
        tp.*,
        RANK() OVER (PARTITION BY tp.Year ORDER BY tp.TotalScore DESC, tp.TotalViews DESC) AS ScoreRank,
        LAG(tp.TotalScore, 1, 0) OVER (PARTITION BY tp.TagName ORDER BY tp.Year) AS PreviousYearScore,
        LEAD(tp.TotalScore, 1, 0) OVER (PARTITION BY tp.TagName ORDER BY tp.Year) AS NextYearScore
    FROM TagPerformance tp
),
TopUsersPerTag AS (
    SELECT
        qt.TagName,
        qt.OwnerUserId,
        COUNT(*) AS QuestionsByUser,
        SUM(qt.Score) AS ScoreByUser,
        ROW_NUMBER() OVER (PARTITION BY qt.TagName ORDER BY SUM(qt.Score) DESC, COUNT(*) DESC) AS UserRankInTag
    FROM QuestionTags qt
    JOIN Users u ON qt.OwnerUserId = u.Id
    WHERE u.Reputation > 5000
    GROUP BY qt.TagName, qt.OwnerUserId
),
FinalTagAnalysis AS (
    SELECT
        rtp.Year,
        rtp.TagName,
        rtp.ScoreRank,
        rtp.QuestionsAsked,
        CAST(rtp.AvgScore AS DECIMAL(10, 2)) AS AvgScore,
        rtp.TotalViews,
        CAST(rtp.AvgAnswers AS DECIMAL(10, 2)) AS AvgAnswers,
        rtp.UniqueAskers,
        (rtp.TotalScore - rtp.PreviousYearScore) AS YearOverYearScoreGrowth,
        tu.TopUserDisplayName,
        tu.TopUserReputation,
        tu.TopUserQuestionsInTag
    FROM RankedTagPerformance rtp
    LEFT JOIN (
        SELECT
            tup.TagName,
            u.DisplayName AS TopUserDisplayName,
            u.Reputation AS TopUserReputation,
            tup.QuestionsByUser AS TopUserQuestionsInTag
        FROM TopUsersPerTag tup
        JOIN Users u ON tup.OwnerUserId = u.Id
        WHERE tup.UserRankInTag = 1
    ) AS tu ON rtp.TagName = tu.TagName
    WHERE rtp.ScoreRank <= 5
)
SELECT
    fta.Year,
    fta.ScoreRank,
    fta.TagName,
    fta.QuestionsAsked,
    fta.AvgScore,
    fta.TotalViews,
    fta.AvgAnswers,
    fta.UniqueAskers,
    fta.YearOverYearScoreGrowth,
    fta.TopUserDisplayName,
    fta.TopUserReputation,
    fta.TopUserQuestionsInTag,
    (
        SELECT COUNT(DISTINCT a.OwnerUserId)
        FROM Posts q
        JOIN Posts a ON q.Id = a.ParentId
        WHERE q.PostTypeId = 1 AND string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><') @> ARRAY[fta.TagName]
          AND EXTRACT(YEAR FROM q.CreationDate) = fta.Year
          AND a.OwnerUserId IS NOT NULL
    ) AS UniqueAnswerers
FROM FinalTagAnalysis fta
ORDER BY fta.Year DESC, fta.ScoreRank ASC;
