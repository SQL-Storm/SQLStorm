-- {"query": "16061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2157}

WITH UserEngagementMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        NTILE(10) OVER (ORDER BY EXTRACT(EPOCH FROM u.CreationDate)) AS UserCohort,
        CASE 
            WHEN u.Location IS NULL THEN 'Unknown'
            WHEN LENGTH(TRIM(u.Location)) = 0 THEN 'Empty'
            ELSE SUBSTRING(u.Location, 1, 20)
        END AS LocationCategory
    FROM Users u
    WHERE u.Reputation > 100
),
QuestionAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CreationDate AS QuestionCreationDate,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswererUserId,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST, a.CreationDate) AS AnswerRankByScore,
        LAG(a.CreationDate) OVER (PARTITION BY q.Id ORDER BY a.CreationDate) AS PreviousAnswerTime,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600.0 AS HoursToAnswer
    FROM Posts q
    LEFT OUTER JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= TIMESTAMP '2020-01-01'
        AND q.ClosedDate IS NULL
        AND (q.Tags LIKE '%<sql>%' OR q.Tags LIKE '%<postgresql>%' OR q.Tags LIKE '%<database>%')
),
TagPerformance AS (
    SELECT 
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS MedianViews,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) AS AcceptanceRate
    FROM Posts p
    WHERE p.PostTypeId = 1
        AND p.Tags IS NOT NULL
        AND p.CreationDate >= TIMESTAMP '2019-01-01'
    GROUP BY UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
    HAVING COUNT(DISTINCT p.Id) >= 50
),
UserBadgeAchievements AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ' ORDER BY CASE WHEN b.Class = 1 THEN b.Name END) AS GoldBadgeNames,
        MAX(b.Date) AS LastBadgeDate,
        COUNT(DISTINCT b.Name) AS UniqueBadgeTypes
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    uem.DisplayName,
    uem.Reputation,
    uem.ReputationRank,
    uem.UserCohort,
    uem.LocationCategory,
    COALESCE(uba.GoldBadges, 0) + COALESCE(uba.SilverBadges, 0) * 0.5 + COALESCE(uba.BronzeBadges, 0) * 0.1 AS WeightedBadgeScore,
    COALESCE(uba.GoldBadgeNames, 'None') AS TopBadges,
    COUNT(DISTINCT qas.QuestionId) AS QuestionsParticipated,
    COUNT(DISTINCT CASE WHEN qas.AnswerRankByScore = 1 THEN qas.QuestionId END) AS TopAnswersProvided,
    AVG(CASE WHEN qas.AnswerId IS NOT NULL THEN qas.AnswerScore END) AS AvgAnswerScore,
    SUM(CASE WHEN qas.IsAccepted = 1 THEN 1 ELSE 0 END) AS AcceptedAnswers,
    AVG(CASE WHEN qas.HoursToAnswer IS NOT NULL AND qas.HoursToAnswer < 168 THEN qas.HoursToAnswer END) AS AvgResponseTimeHours,
    (SELECT AVG(tp.AvgScore) 
     FROM QuestionAnswerStats qas2
     INNER JOIN TagPerformance tp ON EXISTS (
         SELECT 1 FROM Posts p2 
         WHERE p2.Id = qas2.QuestionId 
         AND p2.Tags LIKE '%<' || tp.TagName || '>%'
     )
     WHERE qas2.AnswererUserId = uem.Id
    ) AS AvgTagPerformanceScore,
    CASE 
        WHEN uem.Reputation > 10000 AND COALESCE(uba.GoldBadges, 0) >= 3 THEN 'Elite'
        WHEN uem.Reputation > 5000 AND COALESCE(uba.SilverBadges, 0) >= 5 THEN 'Advanced'
        WHEN uem.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserTier,
    ROUND(
        (COALESCE(uem.Reputation, 0)::NUMERIC / NULLIF(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - uem.CreationDate))/86400.0, 0))
    , 2) AS ReputationPerDay,
    (SELECT COUNT(DISTINCT v.Id)
     FROM Votes v
     INNER JOIN Posts p ON v.PostId = p.Id
     WHERE p.OwnerUserId = uem.Id
         AND v.VoteTypeId IN (2, 3, 5)
         AND v.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '90 days'
    ) AS RecentVotesReceived
FROM UserEngagementMetrics uem
LEFT JOIN QuestionAnswerStats qas ON uem.Id = qas.AnswererUserId
LEFT JOIN UserBadgeAchievements uba ON uem.Id = uba.UserId
WHERE uem.ReputationRank <= 5000
    AND (qas.AnswerId IS NULL OR qas.HoursToAnswer IS NULL OR qas.HoursToAnswer >= 0)
GROUP BY 
    uem.Id,
    uem.DisplayName,
    uem.Reputation,
    uem.ReputationRank,
    uem.UserCohort,
    uem.LocationCategory,
    uem.CreationDate,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    uba.GoldBadgeNames
HAVING COUNT(DISTINCT qas.AnswerId) >= 5
    OR COALESCE(SUM(CASE WHEN qas.IsAccepted = 1 THEN 1 ELSE 0 END), 0) >= 2
ORDER BY 
    WeightedBadgeScore DESC,
    uem.Reputation DESC,
    AvgAnswerScore DESC NULLS LAST
LIMIT 100;
