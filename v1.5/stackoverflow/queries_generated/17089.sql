-- {"query": "17089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2312}

WITH UserActivityMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(AVG(p.Score), 0) AS AvgPostScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') FILTER (WHERE p.Tags IS NOT NULL) AS UserTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
EliteBadgeUsers AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        DENSE_RANK() OVER (ORDER BY COUNT(CASE WHEN Class = 1 THEN 1 END) DESC) AS GoldRank
    FROM Badges
    WHERE Date >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY UserId
    HAVING COUNT(CASE WHEN Class = 1 THEN 1 END) > 0
),
QuestionPerformance AS (
    SELECT 
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        CASE 
            WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN q.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Unanswered'
        END AS Status,
        COALESCE(q.ViewCount, 0) / NULLIF(EXTRACT(DAY FROM CURRENT_DATE - q.CreationDate), 0) AS ViewsPerDay,
        (SELECT COUNT(DISTINCT ph.UserId) 
         FROM PostHistory ph 
         WHERE ph.PostId = q.Id 
           AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        EXISTS (
            SELECT 1 
            FROM PostLinks pl 
            WHERE pl.PostId = q.Id 
              AND pl.LinkTypeId = 3
        ) AS IsDuplicate,
        LAG(q.Score) OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate) AS PrevQuestionScore,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC) AS UserScoreRank
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
),
AnswerQuality AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswererId,
        q.OwnerUserId AS QuestionerId,
        a.Score AS AnswerScore,
        q.Score AS QuestionScore,
        CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAccepted,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate) AS AnswerRank,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 AS HoursToAnswer,
        LENGTH(a.Body) - LENGTH(REPLACE(LOWER(a.Body), '<code>', '')) AS CodeBlockCount
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
      AND a.Score >= 0
)
SELECT 
    COALESCE(uam.DisplayName, 'Unknown User') AS UserName,
    uam.Reputation,
    COALESCE(uam.QuestionCount, 0) AS QuestionsAsked,
    COALESCE(uam.AnswerCount, 0) AS AnswersGiven,
    ROUND(COALESCE(uam.AvgPostScore, 0), 2) AS AvgScore,
    COALESCE(uam.MedianPostScore, 0) AS MedianScore,
    COALESCE(ebu.GoldBadges, 0) || '/' || COALESCE(ebu.SilverBadges, 0) || '/' || COALESCE(ebu.BronzeBadges, 0) AS BadgeCount,
    COALESCE(ebu.GoldRank, 999999) AS GoldBadgeRanking,
    COUNT(DISTINCT qp.QuestionId) AS RecentQuestions,
    COUNT(DISTINCT CASE WHEN qp.Status = 'Answered' THEN qp.QuestionId END) AS AcceptedQuestions,
    COALESCE(AVG(qp.ViewsPerDay), 0)::NUMERIC(10,2) AS AvgViewsPerDay,
    COALESCE(MAX(qp.QuestionScore), 0) AS BestQuestionScore,
    COUNT(DISTINCT aq.AnswerId) AS RecentAnswers,
    COUNT(DISTINCT CASE WHEN aq.IsAccepted = 1 THEN aq.AnswerId END) AS AcceptedAnswers,
    COALESCE(AVG(aq.HoursToAnswer) FILTER (WHERE aq.AnswerRank = 1), 0)::NUMERIC(10,2) AS AvgHoursToTopAnswer,
    COALESCE(
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY aq.AnswerScore) 
        FILTER (WHERE aq.AnswererId = uam.Id),
        0
    ) AS Answer75thPercentileScore,
    CASE 
        WHEN uam.Reputation >= 10000 AND COALESCE(ebu.GoldBadges, 0) >= 5 THEN 'Elite'
        WHEN uam.Reputation >= 5000 OR COALESCE(ebu.GoldBadges, 0) >= 1 THEN 'Expert'
        WHEN uam.Reputation >= 1000 THEN 'Experienced'
        WHEN uam.Reputation >= 100 THEN 'Regular'
        ELSE 'Newcomer'
    END AS UserTier,
    SUBSTRING(COALESCE(uam.UserTags, 'No tags'), 1, 100) AS TopTags,
    COALESCE(
        (SELECT STRING_AGG(c.Text, ' | ' ORDER BY c.Score DESC)
         FROM (
             SELECT Text, Score 
             FROM Comments 
             WHERE UserId = uam.Id 
               AND Score > 5
             ORDER BY Score DESC 
             LIMIT 3
         ) c),
        'No top comments'
    ) AS TopComments
FROM UserActivityMetrics uam
LEFT JOIN EliteBadgeUsers ebu ON uam.Id = ebu.UserId
LEFT JOIN QuestionPerformance qp ON uam.Id = qp.OwnerUserId
LEFT JOIN AnswerQuality aq ON uam.Id = aq.AnswererId OR uam.Id = aq.QuestionerId
WHERE uam.Reputation > 50
  AND (uam.QuestionCount > 0 OR uam.AnswerCount > 0)
GROUP BY 
    uam.Id,
    uam.DisplayName,
    uam.Reputation,
    uam.QuestionCount,
    uam.AnswerCount,
    uam.AvgPostScore,
    uam.MedianPostScore,
    uam.UserTags,
    ebu.GoldBadges,
    ebu.SilverBadges,
    ebu.BronzeBadges,
    ebu.GoldRank
HAVING COUNT(DISTINCT qp.QuestionId) + COUNT(DISTINCT aq.AnswerId) > 0
ORDER BY 
    uam.Reputation DESC,
    COALESCE(ebu.GoldBadges, 0) DESC,
    COUNT(DISTINCT CASE WHEN aq.IsAccepted = 1 THEN aq.AnswerId END) DESC
LIMIT 100;
