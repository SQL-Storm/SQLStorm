-- {"query": "16001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 4670, "output_tokens": 4218} 

WITH UserEngagementMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS YearlyRepRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostCountRank
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100
        AND u.CreationDate >= TIMESTAMP '2015-01-01'
        AND (u.Location IS NULL OR LENGTH(u.Location) > 0)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5
),
BadgeAggregation AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END, ', ') AS GoldBadgeNames,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    WHERE b.TagBased = 0
    GROUP BY b.UserId
),
QuestionAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerId,
        q.Title,
        q.Score AS QuestionScore,
        q.AnswerCount,
        q.ViewCount,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerId,
        a.Score AS AnswerScore,
        CASE 
            WHEN q.AcceptedAnswerId = a.Id THEN 1 
            ELSE 0 
        END AS IsAccepted,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 AS HoursToAnswer,
        LAG(a.Score) OVER (PARTITION BY q.Id ORDER BY a.CreationDate) AS PrevAnswerScore,
        LEAD(a.CreationDate) OVER (PARTITION BY q.Id ORDER BY a.CreationDate) AS NextAnswerTime
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 
        AND a.PostTypeId = 2
        AND q.ClosedDate IS NULL
        AND q.CreationDate >= TIMESTAMP '2018-01-01'
        AND q.Score >= 5
),
VotePatterns AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS Favorites,
        AVG(CASE WHEN v.VoteTypeId IN (2, 3) THEN EXTRACT(EPOCH FROM (v.CreationDate - p.CreationDate))/86400 ELSE NULL END) AS AvgDaysToVote,
        MAX(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS MaxBounty
    FROM Votes v
    INNER JOIN Posts p ON v.PostId = p.Id
    GROUP BY v.PostId
)
SELECT 
    uem.UserId,
    COALESCE(uem.DisplayName, 'Unknown User') AS UserName,
    uem.Reputation,
    uem.QuestionCount,
    uem.AnswerCount,
    ROUND(uem.AvgPostScore::numeric, 2) AS AvgScore,
    ba.TotalBadges,
    ba.GoldBadges,
    COALESCE(ba.GoldBadgeNames, 'None') AS TopBadges,
    COUNT(DISTINCT qas.QuestionId) AS QuestionsAnswered,
    AVG(CASE WHEN qas.IsAccepted = 1 THEN qas.AnswerScore ELSE NULL END) AS AvgAcceptedAnswerScore,
    SUM(CASE WHEN qas.IsAccepted = 1 THEN 1 ELSE 0 END)::float / NULLIF(COUNT(DISTINCT qas.AnswerId), 0) AS AcceptanceRate,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qas.HoursToAnswer) AS MedianResponseTime,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = uem.UserId 
         AND c.Score > 0 
         AND c.CreationDate >= TIMESTAMP '2020-01-01') AS HighQualityComments,
    vp.UpVotes - vp.DownVotes AS NetVotes,
    CASE 
        WHEN uem.Reputation > 10000 THEN 'Elite'
        WHEN uem.Reputation > 5000 THEN 'Advanced'
        WHEN uem.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserTier,
    EXTRACT(YEAR FROM AGE(CURRENT_TIMESTAMP, uem.UserCreationDate)) AS YearsActive,
    ROW_NUMBER() OVER (ORDER BY uem.Reputation * ba.TotalBadges DESC) AS CompositeRank
FROM UserEngagementMetrics uem
LEFT OUTER JOIN BadgeAggregation ba ON uem.UserId = ba.UserId
LEFT OUTER JOIN QuestionAnswerStats qas ON uem.UserId = qas.AnswerOwnerId
LEFT OUTER JOIN VotePatterns vp ON qas.AnswerId = vp.PostId
WHERE (ba.GoldBadges > 0 OR uem.Reputation > 5000)
    AND EXISTS (
        SELECT 1 
        FROM Posts p2 
        WHERE p2.OwnerUserId = uem.UserId 
            AND p2.Score > 10 
            AND p2.CommentCount > 2
    )
GROUP BY 
    uem.UserId, uem.DisplayName, uem.Reputation, uem.QuestionCount, 
    uem.AnswerCount, uem.AvgPostScore, uem.UserCreationDate,
    ba.TotalBadges, ba.GoldBadges, ba.GoldBadgeNames,
    vp.UpVotes, vp.DownVotes
HAVING COUNT(DISTINCT qas.AnswerId) > 3
    AND AVG(qas.AnswerScore) > 2
ORDER BY CompositeRank, uem.Reputation DESC, ba.TotalBadges DESC
LIMIT 500;
