-- {"query": "46033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 75702, "output_tokens": 60930} 

WITH TopUsersByReputation AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        EXTRACT(YEAR FROM u.CreationDate) AS JoinYear,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS YearRank
    FROM Users u
    WHERE u.Reputation > 1000
),
QuestionMetrics AS (
    SELECT 
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS TagArray,
        EXTRACT(EPOCH FROM (p.ClosedDate - p.CreationDate))/3600 AS HoursToClose
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
),
AnswerQuality AS (
    SELECT 
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswererUserId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/60 AS MinutesToAnswer,
        CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAccepted,
        COUNT(c.Id) AS AnswerComments,
        AVG(c.Score) AS AvgCommentScore
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Comments c ON c.PostId = a.Id
    WHERE a.PostTypeId = 2
        AND a.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.Score, a.CreationDate, q.CreationDate, q.AcceptedAnswerId
),
UserEngagementScores AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT qm.QuestionId) AS QuestionsAsked,
        COUNT(DISTINCT aq.AnswerId) AS AnswersGiven,
        AVG(qm.QuestionScore) AS AvgQuestionScore,
        AVG(aq.AnswerScore) AS AvgAnswerScore,
        SUM(aq.IsAccepted) AS AcceptedAnswers,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        AVG(CASE WHEN aq.MinutesToAnswer IS NOT NULL THEN aq.MinutesToAnswer ELSE NULL END) AS AvgResponseTime
    FROM TopUsersByReputation u
    LEFT JOIN QuestionMetrics qm ON u.Id = qm.OwnerUserId
    LEFT JOIN AnswerQuality aq ON u.Id = aq.AnswererUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    WHERE u.YearRank <= 100
    GROUP BY u.Id, u.DisplayName
),
TagPopularity AS (
    SELECT 
        UNNEST(qm.TagArray) AS TagName,
        COUNT(DISTINCT qm.QuestionId) AS QuestionCount,
        AVG(qm.QuestionScore) AS AvgScore,
        AVG(qm.ViewCount) AS AvgViews,
        AVG(qm.AnswerCount) AS AvgAnswers,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qm.ViewCount) AS MedianViews
    FROM QuestionMetrics qm
    WHERE qm.TagArray IS NOT NULL
    GROUP BY UNNEST(qm.TagArray)
    HAVING COUNT(DISTINCT qm.QuestionId) >= 50
),
CrossTagAnalysis AS (
    SELECT 
        t1.TagName AS Tag1,
        t2.TagName AS Tag2,
        COUNT(*) AS CoOccurrence,
        AVG(qm.QuestionScore) AS AvgCombinedScore
    FROM QuestionMetrics qm
    CROSS JOIN LATERAL UNNEST(qm.TagArray) AS t1(TagName)
    CROSS JOIN LATERAL UNNEST(qm.TagArray) AS t2(TagName)
    WHERE t1.TagName < t2.TagName
    GROUP BY t1.TagName, t2.TagName
    HAVING COUNT(*) >= 20
)
SELECT 
    ues.DisplayName,
    ues.UserId,
    ues.QuestionsAsked,
    ues.AnswersGiven,
    ROUND(ues.AvgQuestionScore::numeric, 2) AS AvgQuestionScore,
    ROUND(ues.AvgAnswerScore::numeric, 2) AS AvgAnswerScore,
    ues.AcceptedAnswers,
    ROUND((ues.AcceptedAnswers::float / NULLIF(ues.AnswersGiven, 0) * 100)::numeric, 2) AS AcceptanceRate,
    ues.GoldBadges,
    ues.SilverBadges,
    ues.BronzeBadges,
    ROUND(ues.AvgResponseTime::numeric, 2) AS AvgResponseTimeMinutes,
    STRING_AGG(DISTINCT tp.TagName, ', ' ORDER BY tp.QuestionCount DESC) FILTER (WHERE tp_rank <= 5) AS TopTags,
    MAX(cta.CoOccurrence) AS MaxTagCoOccurrence
FROM UserEngagementScores ues
LEFT JOIN QuestionMetrics qm ON ues.UserId = qm.OwnerUserId
LEFT JOIN LATERAL UNNEST(qm.TagArray) AS user_tag(TagName) ON true
LEFT JOIN TagPopularity tp ON user_tag.TagName = tp.TagName
LEFT JOIN LATERAL (
    SELECT ROW_NUMBER() OVER (PARTITION BY ues.UserId ORDER BY tp.QuestionCount DESC) AS tp_rank
) ranked ON true
LEFT JOIN CrossTagAnalysis cta ON (cta.Tag1 = user_tag.TagName OR cta.Tag2 = user_tag.TagName)
WHERE ues.QuestionsAsked + ues.AnswersGiven > 10
GROUP BY ues.DisplayName, ues.UserId, ues.QuestionsAsked, ues.AnswersGiven, 
         ues.AvgQuestionScore, ues.AvgAnswerScore, ues.AcceptedAnswers, 
         ues.GoldBadges, ues.SilverBadges, ues.BronzeBadges, ues.AvgResponseTime
ORDER BY (ues.AvgQuestionScore + ues.AvgAnswerScore) DESC, ues.AcceptedAnswers DESC
LIMIT 500;
