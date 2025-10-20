-- {"query": "28048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1640} 

WITH UserBadgeStats AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(Date) AS LastBadgeDate
    FROM Badges
    GROUP BY UserId
),
ActiveUsers AS (
    SELECT
        U.Id,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        COALESCE(U.Location, 'Unknown') AS Location,
        UBS.GoldBadges,
        UBS.SilverBadges,
        UBS.BronzeBadges,
        UBS.LastBadgeDate,
        (SELECT COUNT(*) 
         FROM Votes V 
         WHERE V.UserId = U.Id 
            AND V.VoteTypeId IN (2, 3, 5)) AS TotalVotes,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM Users U
    LEFT JOIN UserBadgeStats UBS ON U.Id = UBS.UserId
    WHERE U.Reputation > 1000
        AND U.CreationDate BETWEEN '2010-01-01' AND '2020-12-31'
),
PostMetrics AS (
    SELECT
        P.OwnerUserId,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersGiven,
        AVG(P.Score) AS AvgPostScore,
        SUM(LENGTH(P.Body) - LENGTH(REPLACE(P.Body, '<code>', ''))) / 6 AS CodeSnippetsCount,
        COUNT(DISTINCT UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'), NULL)) AS UniqueTagsUsed
    FROM Posts P
    WHERE P.CreationDate BETWEEN '2015-01-01' AND '2020-12-31'
    GROUP BY P.OwnerUserId
)
SELECT 
    AU.Id,
    AU.DisplayName,
    AU.Reputation,
    AU.Location,
    PM.TotalPosts,
    PM.QuestionsAsked,
    PM.AnswersGiven,
    PM.AvgPostScore,
    PM.CodeSnippetsCount,
    PM.UniqueTagsUsed,
    AU.GoldBadges,
    AU.SilverBadges,
    AU.BronzeBadges,
    AU.TotalVotes,
    (SELECT STRING_AGG(SUBSTRING(Text, 1, 50), ' | ')
     FROM PostHistory PH
     WHERE PH.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = AU.Id)
        AND PH.PostHistoryTypeId = 5
     LIMIT 3) AS RecentEditsPreview,
    (SELECT COUNT(*) 
     FROM Comments C 
     WHERE C.UserId = AU.Id 
        AND POSITION('thank' IN LOWER(C.Text)) > 0) AS GratitudeComments
FROM ActiveUsers AU
LEFT JOIN PostMetrics PM ON AU.Id = PM.OwnerUserId
WHERE PM.AvgPostScore > 5
    OR (PM.UniqueTagsUsed >= 5 AND AU.GoldBadges > 0)
UNION ALL
SELECT 
    U.Id,
    U.DisplayName,
    U.Reputation,
    COALESCE(U.Location, 'Unknown'),
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    NULL,
    0
FROM Users U
WHERE U.Id NOT IN (SELECT OwnerUserId FROM Posts)
    AND U.Reputation < 100
ORDER BY Reputation DESC, TotalPosts DESC NULLS LAST;
