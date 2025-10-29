-- {"query": "1849.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4037} 

WITH UserComprehensiveMetrics AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS UserGivenUpVotes,
        U.DownVotes AS UserGivenDownVotes,
        U.Views AS UserProfileViews,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LatestBadgeDate,
        (SELECT Name FROM Badges WHERE UserId = U.Id ORDER BY Date DESC LIMIT 1) AS LatestBadgeName, -- Correlated subquery for specific badge name
        (SELECT COUNT(V_sub.Id) FROM Votes V_sub INNER JOIN Posts P_sub ON V_sub.PostId = P_sub.Id WHERE P_sub.OwnerUserId = U.Id AND V_sub.VoteTypeId = 2) AS ReceivedUpVotes,
        (SELECT COUNT(V_sub.Id) FROM Votes V_sub INNER JOIN Posts P_sub ON V_sub.PostId = P_sub.Id WHERE P_sub.OwnerUserId = U.Id AND V_sub.VoteTypeId = 3) AS ReceivedDownVotes,
        (
            SELECT DATE(PH_sub.CreationDate)
            FROM PostHistory PH_sub
            WHERE PH_sub.UserId = U.Id
            GROUP BY DATE(PH_sub.CreationDate)
            ORDER BY COUNT(*) DESC, DATE(PH_sub.CreationDate) DESC
            LIMIT 1
        ) AS MostActiveDayForUser
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Views
),
PostEngagementAndTagInfo AS (
    SELECT
        P.Id AS PostId,
        P.ParentId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastActivityDate,
        P.ClosedDate,
        P.LastEditDate,
        P.Body,
        P.Tags AS RawTags,
        COALESCE(
            ARRAY_TO_STRING(
                ARRAY(SELECT UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'))),
                ', '
            ), ''
        ) AS FormattedTagsString,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpvoteCount,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownvoteCount,
        COALESCE(SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END), 0) AS CloseEventsCount,
        COALESCE(SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END), 0) AS ReopenEventsCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS LastCloseEventDate,
        NTILE(10) OVER (ORDER BY P.Score DESC, P.ViewCount DESC, P.FavoriteCount DESC) AS PostEngagementDecile,
        LAG(P.CreationDate, 1, '1900-01-01'::timestamp) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostCreationDate,
        (P.Score * 0.5 + COALESCE(P.ViewCount, 0) * 0.1 + P.CommentCount * 0.3 + COALESCE(P.FavoriteCount, 0) * 0.2 + (CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 100 ELSE 0 END)) AS CalculatedEngagementScore,
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            ELSE 'Open'
        END AS PostLifeCycleStatus,
        SUBSTRING(COALESCE(P.Body, ''), 1, 100) AS BodyExcerpt
    FROM Posts P
    LEFT JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId IN (10, 11)
    WHERE P.PostTypeId IN (1, 2)
    GROUP BY
        P.Id, P.ParentId, P.PostTypeId, PT.Name, P.OwnerUserId, P.Title, P.CreationDate, P.Score, P.ViewCount,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.LastActivityDate, P.ClosedDate,
        P.LastEditDate, P.Body, P.Tags, P.AcceptedAnswerId, P.CommunityOwnedDate
),
TagDetailedAnalysis AS (
    SELECT
        T.TagName,
        T.Count AS TagUseCount,
        T.IsModeratorOnly,
        T.IsRequired,
        P_Excerpt.Id AS ExcerptPostId,
        P_Excerpt.Title AS ExcerptPostTitle,
        P_Wiki.Id AS WikiPostId,
        P_Wiki.Title AS WikiPostTitle,
        P_Excerpt.CreationDate AS ExcerptCreationDate,
        P_Wiki.CreationDate AS WikiCreationDate,
        ROW_NUMBER() OVER (ORDER BY T.Count DESC, T.TagName) AS TagPopularityRank,
        DENSE_RANK() OVER (ORDER BY T.Count DESC) AS TagDensePopularityRank,
        EXTRACT(YEAR FROM (CURRENT_DATE - COALESCE(P_Wiki.CreationDate, P_Excerpt.CreationDate, '2008-01-01'::timestamp))) AS TagAgeInYears
    FROM Tags T
    LEFT JOIN Posts P_Excerpt ON T.ExcerptPostId = P_Excerpt.Id
    LEFT JOIN Posts P_Wiki ON T.WikiPostId = P_Wiki.Id
)
SELECT
    'Question' AS RecordType,
    UCM.UserId,
    COALESCE(UCM.DisplayName, 'Deleted User [' || UCM.UserId || ']') AS UserDisplayName,
    UCM.Reputation,
    EXTRACT(DAY FROM (CURRENT_TIMESTAMP - UCM.UserCreationDate)) AS UserAccountAgeDays,
    UCM.MostActiveDayForUser,
    UCM.TotalPosts,
    UCM.QuestionsAsked,
    UCM.AnswersGiven,
    UCM.GoldBadges,
    UCM.LatestBadgeName,
    CASE
        WHEN UCM.Reputation > 10000 AND UCM.GoldBadges >= 5 THEN 'Legendary'
        WHEN UCM.Reputation > 5000 AND UCM.TotalPosts > 100 THEN 'Veteran'
        ELSE 'Contributor'
    END AS UserTier,
    PEATI.PostId,
    PEATI.PostTypeName,
    PEATI.Title AS PostTitle,
    PEATI.PostCreationDate,
    EXTRACT(HOUR FROM (PEATI.LastActivityDate - PEATI.PostCreationDate)) AS HoursSinceCreationToLastActivity,
    PEATI.PostScore,
    PEATI.ViewCount,
    PEATI.AnswerCount,
    PEATI.CommentCount,
    PEATI.FavoriteCount,
    PEATI.UpvoteCount,
    PEATI.DownvoteCount,
    CAST(PEATI.UpvoteCount AS NUMERIC) / NULLIF(PEATI.UpvoteCount + PEATI.DownvoteCount, 0) AS PostUpvoteRatio,
    PEATI.FormattedTagsString,
    TRIM(LEADING ',' FROM PEATI.FormattedTagsString) AS CleanedTagsString,
    PEATI.PostLifeCycleStatus,
    PEATI.LastCloseEventDate,
    PEATI.PostEngagementDecile,
    PEATI.CalculatedEngagementScore,
    PEATI.BodyExcerpt,
    LENGTH(PEATI.Body) AS PostBodyLength,
    LOWER(SUBSTRING(COALESCE(PEATI.Title, ''), 1, 10)) AS TitlePrefixLower,
    (SELECT AVG(C_sub.Score) FROM Comments C_sub WHERE C_sub.PostId = PEATI.PostId AND C_sub.Score IS NOT NULL) AS AvgCommentScore,
    (
        SELECT COALESCE(U_sub.DisplayName, 'Anon')
        FROM Comments C_sub
        LEFT JOIN Users U_sub ON C_sub.UserId = U_sub.Id
        WHERE C_sub.PostId = PEATI.PostId
        GROUP BY COALESCE(U_sub.DisplayName, 'Anon')
        ORDER BY COUNT(*) DESC, MAX(C_sub.CreationDate) DESC
        LIMIT 1
    ) AS MostActiveCommenter,
    TDA.TagName AS MatchedTagName,
    TDA.TagUseCount,
    TDA.TagPopularityRank,
    TDA.TagAgeInYears,
    COALESCE(PL_Linked.RelatedPostId, PL_Duplicate.RelatedPostId) AS RelatedPostId,
    COALESCE(P_Related.Title, 'N/A') AS RelatedPostTitle,
    CASE
        WHEN PL_Linked.LinkTypeId = 1 THEN 'Linked'
        WHEN PL_Duplicate.LinkTypeId = 3 THEN 'Duplicate'
        ELSE 'None'
    END AS LinkType,
    ROW_NUMBER() OVER (PARTITION BY UCM.UserId ORDER BY PEATI.PostScore DESC, PEATI.CreationDate DESC) AS UserPostScoreRank,
    RANK() OVER (PARTITION BY PEATI.PostTypeId, DATE_TRUNC('quarter', PEATI.PostCreationDate) ORDER BY COALESCE(PEATI.ViewCount, 0) DESC) AS QuarterPostViewRank
FROM UserComprehensiveMetrics UCM
INNER JOIN PostEngagementAndTagInfo PEATI ON UCM.UserId = PEATI.OwnerUserId
LEFT JOIN PostLinks PL_Linked ON PEATI.PostId = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1
LEFT JOIN Posts P_Related ON PL_Linked.RelatedPostId = P_Related.Id
LEFT JOIN PostLinks PL_Duplicate ON PEATI.PostId = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3
LEFT JOIN TagDetailedAnalysis TDA ON PEATI.FormattedTagsString LIKE '%<' || TDA.TagName || '>%' -- Join with tags for detailed analysis
WHERE
    PEATI.PostTypeId = 1
    AND PEATI.PostCreationDate >= '2020-01-01'
    AND PEATI.PostScore > 0
    AND (PEATI.Title LIKE '%performance%' OR PEATI.Body LIKE '%optimization%' OR PEATI.FormattedTagsString LIKE '%<sql>%')
    AND PEATI.PostLifeCycleStatus IN ('Open', 'Answered')
    AND EXISTS (SELECT 1 FROM Comments C_exists WHERE C_exists.PostId = PEATI.PostId AND LENGTH(C_exists.Text) > 50 AND C_exists.Score > 0)
    AND NOT EXISTS (SELECT 1 FROM PostHistory PH_deleted WHERE PH_deleted.PostId = PEATI.PostId AND PH_deleted.PostHistoryTypeId = 12)
    AND UCM.Reputation > 2000

UNION ALL

SELECT
    'Answer' AS RecordType,
    UCM.UserId,
    COALESCE(UCM.DisplayName, 'Deleted User [' || UCM.UserId || ']') AS UserDisplayName,
    UCM.Reputation,
    EXTRACT(DAY FROM (CURRENT_TIMESTAMP - UCM.UserCreationDate)) AS UserAccountAgeDays,
    UCM.MostActiveDayForUser,
    UCM.TotalPosts,
    UCM.QuestionsAsked,
    UCM.AnswersGiven,
    UCM.GoldBadges,
    UCM.LatestBadgeName,
    CASE
        WHEN UCM.Reputation > 10000 AND UCM.GoldBadges >= 5 THEN 'Legendary'
        WHEN UCM.Reputation > 5000 AND UCM.TotalPosts > 100 THEN 'Veteran'
        ELSE 'Contributor'
    END AS UserTier,
    PEATI.PostId,
    PEATI.PostTypeName,
    NULL AS PostTitle, -- Answers don't have titles, so explicitly NULL
    PEATI.PostCreationDate,
    EXTRACT(HOUR FROM (PEATI.LastActivityDate - PEATI.PostCreationDate)) AS HoursSinceCreationToLastActivity,
    PEATI.PostScore,
    NULL AS ViewCount, -- Answers don't have view counts, so explicitly NULL
    NULL AS AnswerCount, -- Answers don't have answer counts, so explicitly NULL
    PEATI.CommentCount,
    NULL AS FavoriteCount, -- Answers typically don't track favorites directly
    PEATI.UpvoteCount,
    PEATI.DownvoteCount,
    CAST(PEATI.UpvoteCount AS NUMERIC) / NULLIF(PEATI.UpvoteCount + PEATI.DownvoteCount, 0) AS PostUpvoteRatio,
    NULL AS FormattedTagsString, -- Answers don't have tags, so explicitly NULL
    NULL AS CleanedTagsString,
    PEATI.PostLifeCycleStatus,
    PEATI.LastCloseEventDate,
    PEATI.PostEngagementDecile,
    PEATI.CalculatedEngagementScore,
    PEATI.BodyExcerpt,
    LENGTH(PEATI.Body) AS PostBodyLength,
    NULL AS TitlePrefixLower, -- Matches column type for Question branch (will be NULL anyway)
    (SELECT AVG(C_sub.Score) FROM Comments C_sub WHERE C_sub.PostId = PEATI.PostId AND C_sub.Score IS NOT NULL) AS AvgCommentScore,
    (
        SELECT COALESCE(U_sub.DisplayName, 'Anon')
        FROM Comments C_sub
        LEFT JOIN Users U_sub ON C_sub.UserId = U_sub.Id
        WHERE C_sub.PostId = PEATI.PostId
        GROUP BY COALESCE(U_sub.DisplayName, 'Anon')
        ORDER BY COUNT(*) DESC, MAX(C_sub.CreationDate) DESC
        LIMIT 1
    ) AS MostActiveCommenter,
    TDA.TagName AS MatchedTagName,
    TDA.TagUseCount,
    TDA.TagPopularityRank,
    TDA.TagAgeInYears,
    PEATI.ParentId AS RelatedPostId,
    (SELECT P_parent.Title FROM Posts P_parent WHERE P_parent.Id = PEATI.ParentId) AS RelatedPostTitle, -- Correlated subquery for parent question title
    'AnswerToQuestion' AS LinkType,
    ROW_NUMBER() OVER (PARTITION BY UCM.UserId ORDER BY PEATI.PostScore DESC, PEATI.CreationDate DESC) AS UserPostScoreRank,
    RANK() OVER (PARTITION BY PEATI.PostTypeId, DATE_TRUNC('quarter', PEATI.PostCreationDate) ORDER BY PEATI.PostScore DESC) AS QuarterPostViewRank
FROM UserComprehensiveMetrics UCM
INNER JOIN PostEngagementAndTagInfo PEATI ON UCM.UserId = PEATI.OwnerUserId
LEFT JOIN PostLinks PL_Linked ON PEATI.PostId = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1
LEFT JOIN Posts P_Related ON PL_Linked.RelatedPostId = P_Related.Id
LEFT JOIN PostLinks PL_Duplicate ON PEATI.PostId = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3
LEFT JOIN Posts P_ParentTags ON PEATI.ParentId = P_ParentTags.Id -- To get tags for parent question
LEFT JOIN TagDetailedAnalysis TDA ON P_ParentTags.Tags LIKE '%<' || TDA.TagName || '>%' -- Tags of parent question
WHERE
    PEATI.PostTypeId = 2
    AND PEATI.PostCreationDate >= '2020-01-01'
    AND PEATI.PostScore > 0
    AND (LENGTH(PEATI.Body) > 200 OR PEATI.UpvoteCount > 5 OR PEATI.DownvoteCount < 0)
    AND PEATI.ParentId IS NOT NULL
    AND UCM.Reputation > 1000
ORDER BY UserDisplayName, PostCreationDate DESC, CalculatedEngagementScore DESC
LIMIT 2000;
