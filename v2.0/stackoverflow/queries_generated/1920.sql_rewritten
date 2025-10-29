-- {"query": "1920.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3248} 
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        U.UpVotes AS TotalUpvotesGiven,
        U.DownVotes AS TotalDownvotesGiven,
        U.Views AS ProfileViews,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        SUM(CASE WHEN P.PostTypeId IN (1, 2, 6) THEN COALESCE(P.Score, 0) ELSE 0 END) AS TotalPostsScore,
        SUM(CASE WHEN P.PostTypeId = 1 THEN COALESCE(P.ViewCount, 0) ELSE 0 END) AS TotalQuestionsViewCount,
        SUM(COALESCE(P.FavoriteCount, 0)) AS TotalPostsFavoriteCount,
        MAX(P.LastActivityDate) AS LastPostActivity
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location, U.UpVotes, U.DownVotes, U.Views
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeAwardDate
    FROM Badges AS B
    GROUP BY B.UserId
),
PostHistoryActivity AS (
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 24) THEN 1 ELSE 0 END) AS TotalEdits,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloses,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopens,
        MAX(PH.CreationDate) AS LastHistoryActivityDate
    FROM PostHistory AS PH
    WHERE PH.UserId IS NOT NULL
      AND PH.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '5 year')
    GROUP BY PH.UserId
),
UserAcceptedAnswers AS (
    SELECT
        A.OwnerUserId AS UserId,
        COUNT(DISTINCT Q.Id) AS AcceptedAnswerCount
    FROM Posts AS Q -- Questions
    JOIN Posts AS A ON Q.AcceptedAnswerId = A.Id -- Accepted Answers
    WHERE A.PostTypeId = 2 -- Ensure it's an answer
      AND Q.PostTypeId = 1 -- Ensure it's a question
      AND A.OwnerUserId IS NOT NULL
      AND Q.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '3 year')
    GROUP BY A.OwnerUserId
),
TopTagContributor AS (
    SELECT
        P.OwnerUserId AS UserId,
        TagSplit.TagName,
        COUNT(DISTINCT P.Id) AS TagQuestionsCount,
        SUM(COALESCE(P.Score, 0)) AS TagQuestionsScore,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY SUM(COALESCE(P.Score, 0)) DESC, COUNT(DISTINCT P.Id) DESC) AS TagRank
    FROM Posts AS P
    CROSS JOIN LATERAL (
        SELECT value AS TagName
        FROM UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags) - 2), '><')) AS tags_array(value)
        WHERE P.Tags IS NOT NULL AND P.PostTypeId = 1
    ) AS TagSplit
    JOIN Tags AS T ON TagSplit.TagName = T.TagName
    WHERE P.OwnerUserId IS NOT NULL AND P.PostTypeId = 1 AND P.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '2 year')
    GROUP BY P.OwnerUserId, TagSplit.TagName
),
OverallUserMetrics AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.UserCreationDate,
        UE.LastAccessDate,
        UE.UserLocation,
        UE.TotalUpvotesGiven,
        UE.TotalDownvotesGiven,
        UE.ProfileViews,
        UE.TotalPostsOwned,
        UE.QuestionsAsked,
        UE.AnswersProvided,
        UE.TotalPostsScore,
        UE.TotalQuestionsViewCount,
        UE.TotalPostsFavoriteCount,
        UE.LastPostActivity,
        COALESCE(UAA.AcceptedAnswerCount, 0) AS AcceptedAnswerCount,
        COALESCE(UBS.TotalBadges, 0) AS TotalBadges,
        COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
        COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
        COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
        UBS.LastBadgeAwardDate,
        COALESCE(PHA.TotalEdits, 0) AS TotalEdits,
        COALESCE(PHA.TotalCloses, 0) AS TotalCloses,
        COALESCE(PHA.TotalReopens, 0) AS TotalReopens,
        PHA.LastHistoryActivityDate,
        STRING_AGG(CASE WHEN TPC.TagRank = 1 THEN TPC.TagName ELSE NULL END, ', ') AS TopContributingTag,
        MAX(CASE WHEN TPC.TagRank = 1 THEN TPC.TagQuestionsCount ELSE 0 END) AS TopTagQuestionsCount,
        MAX(CASE WHEN TPC.TagRank = 1 THEN TPC.TagQuestionsScore ELSE 0 END) AS TopTagQuestionsScore,
        -- Window function: Rank users by a composite score
        RANK() OVER (ORDER BY UE.Reputation DESC, UE.TotalPostsScore DESC, COALESCE(UAA.AcceptedAnswerCount, 0) DESC, UE.ProfileViews DESC) AS OverallUserRank,
        -- Window function: Average reputation of users in the same location who joined around the same time
        AVG(UE.Reputation) OVER (PARTITION BY UE.UserLocation, EXTRACT(YEAR FROM UE.UserCreationDate)) AS AvgReputationInLocationYear,
        -- Correlated Subquery: Check if user has received any "Offensive" votes on their posts in the last year
        (SELECT COUNT(V.Id)
         FROM Votes AS V
         JOIN Posts AS P_Inner ON V.PostId = P_Inner.Id
         WHERE P_Inner.OwnerUserId = UE.UserId
           AND V.VoteTypeId = 4 -- Offensive vote type
           AND V.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')) AS RecentOffensiveVotes
    FROM UserEngagement AS UE
    LEFT JOIN UserBadgeSummary AS UBS ON UE.UserId = UBS.UserId
    LEFT JOIN PostHistoryActivity AS PHA ON UE.UserId = PHA.UserId
    LEFT JOIN UserAcceptedAnswers AS UAA ON UE.UserId = UAA.UserId
    LEFT JOIN TopTagContributor AS TPC ON UE.UserId = TPC.UserId AND TPC.TagRank = 1
    GROUP BY
        UE.UserId, UE.DisplayName, UE.Reputation, UE.UserCreationDate, UE.LastAccessDate, UE.UserLocation,
        UE.TotalUpvotesGiven, UE.TotalDownvotesGiven, UE.ProfileViews, UE.TotalPostsOwned, UE.QuestionsAsked,
        UE.AnswersProvided, UE.TotalPostsScore, UE.TotalQuestionsViewCount, UE.TotalPostsFavoriteCount, UE.LastPostActivity,
        COALESCE(UAA.AcceptedAnswerCount, 0),
        COALESCE(UBS.TotalBadges, 0), COALESCE(UBS.GoldBadges, 0), COALESCE(UBS.SilverBadges, 0), COALESCE(UBS.BronzeBadges, 0),
        UBS.LastBadgeAwardDate,
        COALESCE(PHA.TotalEdits, 0), COALESCE(PHA.TotalCloses, 0), COALESCE(PHA.TotalReopens, 0), PHA.LastHistoryActivityDate
)
SELECT
    OUM.UserId,
    OUM.DisplayName,
    OUM.Reputation,
    OUM.OverallUserRank,
    OUM.UserLocation,
    OUM.TotalPostsOwned,
    OUM.QuestionsAsked,
    OUM.AnswersProvided,
    OUM.AcceptedAnswerCount,
    OUM.TotalPostsScore,
    OUM.TotalEdits,
    OUM.TotalCloses,
    OUM.GoldBadges,
    OUM.TopContributingTag,
    OUM.AvgReputationInLocationYear,
    OUM.RecentOffensiveVotes,
    'HighReputationActive' AS UserGroupType,
    -- Complicated expression/calculation for a "performance score"
    (OUM.Reputation * 0.5 + OUM.TotalPostsScore * 0.2 + OUM.AcceptedAnswerCount * 5 + OUM.TotalEdits * 0.8 + OUM.GoldBadges * 10 - OUM.RecentOffensiveVotes * 20) AS PerformanceScore,
    -- String expression and NULL logic
    COALESCE(
        CASE
            WHEN OUM.UserLocation LIKE '%United States%' OR OUM.UserLocation LIKE '%USA%' THEN 'USA'
            WHEN OUM.UserLocation LIKE '%India%' THEN 'IND'
            WHEN OUM.UserLocation LIKE '%Canada%' THEN 'CAN'
            WHEN OUM.UserLocation LIKE '%United Kingdom%' OR OUM.UserLocation LIKE '%UK%' THEN 'GBR'
            WHEN OUM.UserLocation LIKE '%Germany%' THEN 'DEU'
            ELSE NULL
        END, 'Other Country') AS CountryAbbreviation,
    CASE
        WHEN OUM.Reputation > 50000 AND OUM.GoldBadges >= 5 AND OUM.AcceptedAnswerCount > 50 THEN 'Guru'
        WHEN OUM.Reputation > 10000 AND OUM.TotalPostsOwned > 100 AND OUM.AnswersProvided > 50 THEN 'Expert'
        WHEN OUM.Reputation > 1000 AND OUM.TotalPostsOwned > 20 THEN 'Contributor'
        ELSE 'Novice'
    END AS UserLevel,
    OUM.UserCreationDate,
    OUM.LastAccessDate
FROM OverallUserMetrics AS OUM
WHERE
    OUM.Reputation >= 1000
    AND (OUM.QuestionsAsked + OUM.AnswersProvided >= 10 OR OUM.TotalEdits > 5)
    AND OUM.LastAccessDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
    AND OUM.ProfileViews > 100
    AND (OUM.UserLocation IS NULL OR OUM.UserLocation NOT ILIKE '%[deleted]%')
    AND (OUM.TotalEdits > 0 OR OUM.AcceptedAnswerCount > 0 OR OUM.GoldBadges > 0)
    AND OUM.RecentOffensiveVotes < 5
UNION ALL
SELECT
    OUM.UserId,
    OUM.DisplayName,
    OUM.Reputation,
    OUM.OverallUserRank,
    OUM.UserLocation,
    OUM.TotalPostsOwned,
    OUM.QuestionsAsked,
    OUM.AnswersProvided,
    OUM.AcceptedAnswerCount,
    OUM.TotalPostsScore,
    OUM.TotalEdits,
    OUM.TotalCloses,
    OUM.GoldBadges,
    OUM.TopContributingTag,
    OUM.AvgReputationInLocationYear,
    OUM.RecentOffensiveVotes,
    'EditorModeratorFocus' AS UserGroupType,
    (OUM.TotalEdits * 2 + OUM.TotalCloses * 5 + OUM.TotalReopens * 3 + OUM.GoldBadges * 5 - OUM.RecentOffensiveVotes * 10) AS PerformanceScore,
    COALESCE(
        CASE
            WHEN OUM.UserLocation LIKE '%Germany%' THEN 'DEU'
            WHEN OUM.UserLocation LIKE '%France%' THEN 'FRA'
            WHEN OUM.UserLocation LIKE '%Australia%' THEN 'AUS'
            WHEN OUM.UserLocation LIKE '%China%' THEN 'CHN'
            ELSE NULL
        END, 'Other Country') AS CountryAbbreviation,
    CASE
        WHEN OUM.TotalCloses > 100 OR OUM.TotalEdits > 500 THEN 'ModerationForce'
        WHEN OUM.TotalEdits > 50 AND OUM.TotalPostsOwned < 20 THEN 'SilentEditor'
        ELSE 'CasualEditor'
    END AS UserLevel,
    OUM.UserCreationDate,
    OUM.LastAccessDate
FROM OverallUserMetrics AS OUM
WHERE
    OUM.Reputation < 10000
    AND (OUM.TotalEdits + OUM.TotalCloses + OUM.TotalReopens >= 10)
    AND OUM.UserCreationDate >= (cast('2024-10-01' as date) - INTERVAL '5 year')
    AND OUM.QuestionsAsked = 0 -- Focus on non-question-askers
    AND OUM.AcceptedAnswerCount < 5 -- Not primarily answerers either, or only casually
    AND OUM.ProfileViews < 500
    AND OUM.RecentOffensiveVotes < 2
ORDER BY PerformanceScore DESC, Reputation DESC
LIMIT 1000;