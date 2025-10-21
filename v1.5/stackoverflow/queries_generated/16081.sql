-- {"query": "16081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2537}

WITH UserEngagementMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        EXTRACT(YEAR FROM AGE(CURRENT_TIMESTAMP, u.CreationDate)) * 12 + 
            EXTRACT(MONTH FROM AGE(CURRENT_TIMESTAMP, u.CreationDate)) AS MonthsActive,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedQuestions
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '5 years'
        AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes
    HAVING COUNT(DISTINCT p.Id) > 5
),
TagExpertise AS (
    SELECT 
        p.OwnerUserId,
        UNNEST(string_to_array(NULLIF(substring(p.Tags, 2, length(p.Tags)-2), ''), '><')) AS TagName,
        COUNT(*) AS TagPostCount,
        AVG(p.Score) AS AvgTagScore,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC, AVG(p.Score) DESC) AS TagRank
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.Tags IS NOT NULL 
        AND LENGTH(p.Tags) > 2
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
),
AnswerQualityMetrics AS (
    SELECT 
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswererId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        q.Id AS QuestionId,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRankInQuestion,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600.0 AS HoursToAnswer,
        COUNT(c.Id) AS CommentCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvoteCount
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Comments c ON a.Id = c.PostId
    LEFT JOIN Votes v ON a.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE a.PostTypeId = 2 
        AND q.PostTypeId = 1
        AND a.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '3 years'
    GROUP BY a.Id, a.OwnerUserId, a.Score, a.CreationDate, q.Id, q.Score, q.ViewCount, q.AcceptedAnswerId
),
BadgeAchievements AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN b.TagBased = 1 THEN b.Name END) AS UniqueTagBadges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ') AS GoldBadgeNames
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    uem.DisplayName,
    ROUND(uem.Reputation::numeric / NULLIF(uem.MonthsActive, 0), 2) AS ReputationPerMonth,
    uem.TotalPosts,
    uem.QuestionCount,
    uem.AnswerCount,
    ROUND(COALESCE(uem.AvgQuestionScore, 0)::numeric, 2) AS AvgQuestionScore,
    ROUND(COALESCE(uem.AvgAnswerScore, 0)::numeric, 2) AS AvgAnswerScore,
    COALESCE(te.TagName, 'N/A') AS TopTag,
    COALESCE(te.TagPostCount, 0) AS TopTagPostCount,
    ROUND(COALESCE(te.AvgTagScore, 0)::numeric, 2) AS TopTagAvgScore,
    COALESCE(ba.GoldBadges, 0) AS GoldBadges,
    COALESCE(ba.SilverBadges, 0) AS SilverBadges,
    COALESCE(ba.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ba.GoldBadgeNames, 'None') AS GoldBadgesList,
    ROUND(AVG(aqm.AnswerScore)::numeric, 2) AS AvgAnswerScoreDetailed,
    ROUND(AVG(CASE WHEN aqm.IsAccepted = 1 THEN 100.0 ELSE 0.0 END), 2) AS AcceptanceRate,
    COUNT(DISTINCT CASE WHEN aqm.AnswerRankInQuestion = 1 AND aqm.IsAccepted = 0 THEN aqm.AnswerId END) AS TopNotAcceptedCount,
    ROUND(AVG(CASE WHEN aqm.HoursToAnswer <= 24 THEN aqm.HoursToAnswer END)::numeric, 2) AS AvgHoursToAnswerQuickly,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY aqm.AnswerScore) AS MedianAnswerScore,
    (SELECT COUNT(*) 
     FROM PostHistory ph 
     WHERE ph.UserId = uem.UserId 
         AND ph.PostHistoryTypeId IN (4, 5, 6)
         AND ph.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year') AS RecentEdits,
    CASE 
        WHEN uem.Reputation > 50000 AND COALESCE(ba.GoldBadges, 0) >= 5 THEN 'Elite'
        WHEN uem.Reputation > 20000 AND COALESCE(ba.GoldBadges, 0) >= 2 THEN 'Expert'
        WHEN uem.Reputation > 5000 THEN 'Advanced'
        WHEN uem.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserTier,
    DENSE_RANK() OVER (ORDER BY uem.Reputation DESC, COALESCE(ba.GoldBadges, 0) DESC) AS OverallRank
FROM UserEngagementMetrics uem
LEFT JOIN TagExpertise te ON uem.UserId = te.OwnerUserId AND te.TagRank = 1
LEFT JOIN BadgeAchievements ba ON uem.UserId = ba.UserId
LEFT JOIN AnswerQualityMetrics aqm ON uem.UserId = aqm.AnswererId
WHERE (uem.QuestionCount > 0 OR uem.AnswerCount > 3)
    AND uem.MonthsActive > 0
    AND NOT EXISTS (
        SELECT 1 
        FROM Votes v 
        WHERE v.UserId = uem.UserId 
            AND v.VoteTypeId IN (4, 12)
        HAVING COUNT(*) > 5
    )
GROUP BY uem.UserId, uem.DisplayName, uem.Reputation, uem.MonthsActive, uem.TotalPosts, 
         uem.QuestionCount, uem.AnswerCount, uem.AvgQuestionScore, uem.AvgAnswerScore,
         te.TagName, te.TagPostCount, te.AvgTagScore, 
         ba.GoldBadges, ba.SilverBadges, ba.BronzeBadges, ba.GoldBadgeNames
HAVING COUNT(DISTINCT aqm.AnswerId) >= 3
ORDER BY OverallRank ASC, ReputationPerMonth DESC
LIMIT 500;
