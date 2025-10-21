-- {"query": "17082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2835}

WITH UserActivityMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') AS UserTags,
        EXTRACT(EPOCH FROM (NOW() - u.CreationDate))/86400 AS AccountAgeDays,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS YearlyRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostCountRank,
        LAG(u.Reputation, 1) OVER (ORDER BY u.CreationDate) AS PrevUserReputation,
        LEAD(u.Reputation, 1) OVER (ORDER BY u.CreationDate) AS NextUserReputation
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2020-01-01'
        AND (u.Location IS NOT NULL OR u.AboutMe IS NOT NULL)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopContributors AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        QuestionCount,
        AnswerCount,
        AvgPostScore,
        UserTags,
        AccountAgeDays,
        YearlyRank,
        PostCountRank,
        CASE 
            WHEN Reputation > COALESCE(PrevUserReputation, 0) * 1.5 
                AND Reputation > COALESCE(NextUserReputation, 0) * 1.5 
            THEN 'Exceptional Growth'
            WHEN Reputation > 10000 THEN 'Expert'
            WHEN Reputation > 5000 THEN 'Advanced'
            WHEN Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS UserTier,
        NTILE(10) OVER (ORDER BY Reputation DESC) AS ReputationDecile
    FROM UserActivityMetrics
    WHERE PostCount > 0
),
BadgeAnalysis AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN b.TagBased = 1 THEN b.Name END) AS UniqueTagBadges,
        MAX(b.Date) AS LastBadgeDate,
        MIN(b.Date) AS FirstBadgeDate,
        STRING_AGG(CASE WHEN b.Class = 1 THEN b.Name END, ', ' ORDER BY b.Date DESC) AS GoldBadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
PostInteractions AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(p.Title, 'No Title') AS PostTitle,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Has Accepted Answer'
            ELSE 'Open'
        END AS PostStatus,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = p.Id 
            AND v.VoteTypeId IN (2, 3)
            AND v.CreationDate >= p.CreationDate 
            AND v.CreationDate <= COALESCE(p.ClosedDate, NOW())) AS TotalVotes,
        (SELECT COUNT(DISTINCT ph.UserId) 
         FROM PostHistory ph 
         WHERE ph.PostId = p.Id 
            AND ph.PostHistoryTypeId IN (4, 5, 6)
            AND ph.UserId != p.OwnerUserId) AS UniqueEditors,
        EXISTS (
            SELECT 1 
            FROM PostLinks pl 
            WHERE (pl.PostId = p.Id OR pl.RelatedPostId = p.Id)
                AND pl.LinkTypeId = 3
        ) AS IsDuplicateRelated
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= '2020-01-01'
        AND p.Score != 0
)
SELECT DISTINCT
    tc.DisplayName,
    tc.Reputation,
    tc.UserTier,
    tc.ReputationDecile,
    tc.PostCount,
    tc.QuestionCount,
    tc.AnswerCount,
    ROUND(tc.AvgPostScore::numeric, 2) AS AvgPostScore,
    ROUND(tc.AccountAgeDays::numeric, 0) AS AccountAgeDays,
    tc.YearlyRank,
    tc.PostCountRank,
    COALESCE(ba.GoldBadges, 0) AS GoldBadges,
    COALESCE(ba.SilverBadges, 0) AS SilverBadges,
    COALESCE(ba.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ba.UniqueTagBadges, 0) AS UniqueTagBadges,
    COALESCE(LEFT(ba.GoldBadgeNames, 100), 'None') AS GoldBadgesSample,
    COALESCE(
        (SELECT STRING_AGG(SUBSTRING(pi.PostTitle, 1, 50), ' | ' ORDER BY pi.Score DESC)
         FROM (SELECT * FROM PostInteractions WHERE OwnerUserId = tc.UserId LIMIT 3) pi),
        'No Posts'
    ) AS TopPostTitles,
    COALESCE(
        (SELECT SUM(pi2.TotalVotes) 
         FROM PostInteractions pi2 
         WHERE pi2.OwnerUserId = tc.UserId),
        0
    ) AS TotalVotesReceived,
    COALESCE(
        (SELECT AVG(pi3.ViewCount)::int 
         FROM PostInteractions pi3 
         WHERE pi3.OwnerUserId = tc.UserId 
            AND pi3.ViewCount IS NOT NULL),
        0
    ) AS AvgPostViews,
    CASE 
        WHEN tc.QuestionCount > 0 AND tc.AnswerCount > 0 
        THEN ROUND((tc.AnswerCount::numeric / tc.QuestionCount::numeric), 2)
        WHEN tc.QuestionCount = 0 AND tc.AnswerCount > 0 THEN 999.99
        ELSE 0
    END AS AnswerToQuestionRatio,
    COALESCE(LEFT(tc.UserTags, 200), 'No Tags') AS UserTagsSample,
    (SELECT COUNT(DISTINCT c.Id) 
     FROM Comments c 
     WHERE c.UserId = tc.UserId 
        AND c.Score > 0) AS HighScoredComments,
    EXISTS (
        SELECT 1 
        FROM PostHistory ph 
        WHERE ph.UserId = tc.UserId 
            AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15)
    ) AS HasModeratorActivity
FROM TopContributors tc
LEFT OUTER JOIN BadgeAnalysis ba ON tc.UserId = ba.UserId
WHERE tc.Reputation > 100
    AND (tc.QuestionCount > 5 OR tc.AnswerCount > 10)
    AND tc.ReputationDecile <= 3

UNION ALL

SELECT 
    'SUMMARY_ROW' AS DisplayName,
    AVG(tc2.Reputation)::int AS Reputation,
    'Summary' AS UserTier,
    NULL AS ReputationDecile,
    SUM(tc2.PostCount) AS PostCount,
    SUM(tc2.QuestionCount) AS QuestionCount,
    SUM(tc2.AnswerCount) AS AnswerCount,
    AVG(tc2.AvgPostScore)::numeric(10,2) AS AvgPostScore,
    AVG(tc2.AccountAgeDays)::numeric(10,0) AS AccountAgeDays,
    NULL AS YearlyRank,
    NULL AS PostCountRank,
    SUM(COALESCE(ba2.GoldBadges, 0)) AS GoldBadges,
    SUM(COALESCE(ba2.SilverBadges, 0)) AS SilverBadges,
    SUM(COALESCE(ba2.BronzeBadges, 0)) AS BronzeBadges,
    AVG(COALESCE(ba2.UniqueTagBadges, 0))::int AS UniqueTagBadges,
    'AGGREGATED' AS GoldBadgesSample,
    'AGGREGATED' AS TopPostTitles,
    SUM((SELECT SUM(pi4.TotalVotes) FROM PostInteractions pi4 WHERE pi4.OwnerUserId = tc2.UserId)) AS TotalVotesReceived,
    AVG((SELECT AVG(pi5.ViewCount) FROM PostInteractions pi5 WHERE pi5.OwnerUserId = tc2.UserId))::int AS AvgPostViews,
    NULL AS AnswerToQuestionRatio,
    'AGGREGATED' AS UserTagsSample,
    SUM((SELECT COUNT(DISTINCT c2.Id) FROM Comments c2 WHERE c2.UserId = tc2.UserId AND c2.Score > 0)) AS HighScoredComments,
    NULL AS HasModeratorActivity
FROM TopContributors tc2
LEFT OUTER JOIN BadgeAnalysis ba2 ON tc2.UserId = ba2.UserId
WHERE tc2.Reputation > 100
    AND (tc2.QuestionCount > 5 OR tc2.AnswerCount > 10)
    AND tc2.ReputationDecile <= 3

ORDER BY 
    CASE WHEN DisplayName = 'SUMMARY_ROW' THEN 1 ELSE 0 END,
    Reputation DESC,
    PostCount DESC
LIMIT 100;
