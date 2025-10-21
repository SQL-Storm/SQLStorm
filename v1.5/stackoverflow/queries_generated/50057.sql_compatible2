WITH TaggedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        EXTRACT(YEAR FROM p.CreationDate) AS QuestionYear,
        p.OwnerUserId AS AskerId,
        p.Score AS QuestionScore,
        p.AnswerCount,
        u.Reputation AS AskerReputation,
        tag.TagName
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    CROSS JOIN LATERAL
        unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag(TagName)
    WHERE
        p.PostTypeId = 1
        AND p.ClosedDate IS NULL
        AND p.AnswerCount > 0
),
YearlyTagStats AS (
    SELECT
        QuestionYear,
        TagName,
        COUNT(*) AS NumQuestions,
        AVG(AskerReputation) AS AvgAskerReputation,
        AVG(QuestionScore) AS AvgQuestionScore,
        SUM(AnswerCount) AS TotalAnswers,
        corr(AskerReputation, QuestionScore) AS RepScoreCorrelation
    FROM
        TaggedQuestions
    GROUP BY
        QuestionYear,
        TagName
    HAVING
        COUNT(*) > 50 AND SUM(AnswerCount) > 100
),
RankedYearlyTags AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY QuestionYear ORDER BY AvgAskerReputation DESC, NumQuestions DESC) AS ReputationRank,
        RANK() OVER (PARTITION BY QuestionYear ORDER BY RepScoreCorrelation DESC NULLS LAST, NumQuestions DESC) AS CorrelationRank
    FROM
        YearlyTagStats
),
AnswerDetails AS (
    SELECT
        tq.QuestionYear,
        tq.TagName,
        ans.OwnerUserId AS AnswererId,
        ans.Score AS AnswerScore,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ans.Id AND v.VoteTypeId = 2) AS Upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ans.Id AND v.VoteTypeId = 3) AS Downvotes,
        ROW_NUMBER() OVER(PARTITION BY tq.QuestionId ORDER BY ans.Score DESC, ans.CreationDate ASC) as AnswerRank
    FROM
        TaggedQuestions tq
    JOIN
        Posts ans ON tq.QuestionId = ans.ParentId
    WHERE
        ans.PostTypeId = 2
        AND ans.OwnerUserId IS NOT NULL
),
TopAnswererStats AS (
    SELECT
        ad.QuestionYear,
        ad.TagName,
        ad.AnswererId,
        u.DisplayName AS AnswererDisplayName,
        COUNT(*) AS NumTopAnswers,
        SUM(ad.Upvotes) AS TotalUpvotes,
        SUM(ad.Downvotes) AS TotalDownvotes,
        AVG(ad.AnswerScore) AS AvgAnswerScore,
        ROW_NUMBER() OVER (PARTITION BY ad.QuestionYear, ad.TagName ORDER BY COUNT(*) DESC, SUM(ad.Upvotes) DESC) AS AnswererRank
    FROM
        AnswerDetails ad
    JOIN
        Users u ON ad.AnswererId = u.Id
    WHERE
        ad.AnswerRank = 1
    GROUP BY
        ad.QuestionYear,
        ad.TagName,
        ad.AnswererId,
        u.DisplayName
)
SELECT
    ryt.QuestionYear,
    ryt.TagName,
    ryt.ReputationRank,
    ryt.CorrelationRank,
    ryt.NumQuestions,
    ryt.TotalAnswers,
    ryt.AvgAskerReputation,
    ryt.AvgQuestionScore,
    ryt.RepScoreCorrelation,
    tas.AnswererDisplayName AS TopContributor,
    tas.NumTopAnswers,
    tas.TotalUpvotes,
    tas.AvgAnswerScore
FROM
    RankedYearlyTags ryt
JOIN
    TopAnswererStats tas ON ryt.QuestionYear = tas.QuestionYear
                       AND ryt.TagName = tas.TagName
                       AND tas.AnswererRank = 1
WHERE
    ryt.ReputationRank <= 5 OR ryt.CorrelationRank <= 5
ORDER BY
    ryt.QuestionYear DESC,
    ryt.ReputationRank ASC,
    ryt.CorrelationRank ASC;