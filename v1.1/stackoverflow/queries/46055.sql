WITH ReputationTiers AS (
    SELECT 
        Id,
        DisplayName,
        Reputation,
        CreationDate,
        NTILE(10) OVER (ORDER BY Reputation DESC) AS ReputationDecile,
        COUNT(*) OVER () AS TotalUsers
    FROM Users
    WHERE Reputation > 1000
),
QuestionMetrics AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(p.AcceptedAnswerId, 0) AS HasAcceptedAnswer,
        DATE_TRUNC('month', p.CreationDate) AS QuestionMonth,
        -- convert tags like '<tag1><tag2>' to array by removing surrounding <> then splitting on '><'
        regexp_split_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '><') AS TagArray
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '3 years'
),
AnswerQuality AS (
    SELECT 
        a.ParentId,
        a.OwnerUserId AS AnswererUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        q.CreationDate AS QuestionDate,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600.0 AS HoursToAnswer,
        CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAccepted,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 
        AND q.PostTypeId = 1
        AND a.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '3 years'
),
UserEngagement AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS QuestionsAsked,
        COUNT(DISTINCT a.Id) AS AnswersGiven,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT v.Id) AS TotalVotesCast,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        AVG(p.Score) AS AvgQuestionScore,
        AVG(a.Score) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    WHERE u.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '5 years'
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 0 OR COUNT(DISTINCT a.Id) > 0
),
TagCombinations AS (
    SELECT 
        t1.tag AS Tag1,
        t2.tag AS Tag2,
        COUNT(*) AS CoOccurrenceCount,
        AVG(qm.Score) AS AvgScore,
        AVG(qm.ViewCount) AS AvgViews,
        AVG(qm.AnswerCount) AS AvgAnswers
    FROM QuestionMetrics qm,
         LATERAL unnest(qm.TagArray) AS t1(tag),
         LATERAL unnest(qm.TagArray) AS t2(tag)
    WHERE t1.tag < t2.tag
    GROUP BY t1.tag, t2.tag
    HAVING COUNT(*) >= 50
),
MonthlyTrends AS (
    SELECT 
        qm.QuestionMonth,
        COUNT(DISTINCT qm.Id) AS QuestionsCount,
        AVG(qm.Score) AS AvgScore,
        SUM(qm.ViewCount) AS TotalViews,
        COUNT(DISTINCT aq.AnswererUserId) AS UniqueAnswerers,
        AVG(aq.HoursToAnswer) AS AvgTimeToFirstAnswer,
        SUM(CASE WHEN aq.IsAccepted = 1 THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT qm.Id), 0) AS AcceptanceRate
    FROM QuestionMetrics qm
    LEFT JOIN AnswerQuality aq ON qm.Id = aq.ParentId AND aq.AnswerRank = 1
    GROUP BY qm.QuestionMonth
)
SELECT 
    rt.ReputationDecile,
    rt.DisplayName,
    rt.Reputation,
    ue.QuestionsAsked,
    ue.AnswersGiven,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.AvgQuestionScore,
    ue.AvgAnswerScore,
    ue.QuestionsWithAcceptedAnswer,
    COALESCE( (ue.QuestionsWithAcceptedAnswer * 1.0) / NULLIF(ue.QuestionsAsked, 0), 0) AS AcceptanceRate,
    mt.AvgScore AS MonthlyAvgScore,
    mt.AvgTimeToFirstAnswer AS MonthlyAvgResponseTime,
    tc.Tag1 AS TopTagCombination1,
    tc.Tag2 AS TopTagCombination2,
    tc.CoOccurrenceCount,
    DENSE_RANK() OVER (ORDER BY ue.Reputation DESC, ue.AnswersGiven DESC) AS OverallRank,
    PERCENT_RANK() OVER (ORDER BY ue.AvgAnswerScore) AS AnswerQualityPercentile
FROM ReputationTiers rt
INNER JOIN UserEngagement ue ON rt.Id = ue.UserId
LEFT JOIN MonthlyTrends mt ON DATE_TRUNC('month', rt.CreationDate) = mt.QuestionMonth
LEFT JOIN LATERAL (
    SELECT tc.Tag1, tc.Tag2, tc.CoOccurrenceCount
    FROM TagCombinations tc
    ORDER BY tc.AvgScore DESC, tc.CoOccurrenceCount DESC
    LIMIT 1
) tc ON true
WHERE ue.QuestionsAsked + ue.AnswersGiven >= 10
    AND rt.ReputationDecile <= 5
ORDER BY ue.Reputation DESC, ue.AnswersGiven DESC, ue.BadgesEarned DESC
LIMIT 500;