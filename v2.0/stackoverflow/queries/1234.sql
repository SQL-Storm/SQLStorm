-- {"query": "1234.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3675}
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        CASE
            WHEN U.Reputation >= 20000 THEN 'Veteran'
            WHEN U.Reputation >= 5000 THEN 'Expert'
            WHEN U.Reputation >= 500 THEN 'Established'
            WHEN U.Reputation >= 50 THEN 'Contributor'
            ELSE 'Novice'
        END AS ReputationTier,
        COALESCE(CAST(U.UpVotes AS NUMERIC) / NULLIF(U.DownVotes, 0), U.UpVotes) AS UpDownVoteRatio,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 2) AS SilverBadges,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 3) AS BronzeBadges,
        LAG(U.LastAccessDate, 1, U.CreationDate) OVER (PARTITION BY U.Id ORDER BY U.LastAccessDate) AS PrevAccessDate
    FROM
        Users U
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Tags,
        (P.Score * 0.5) + (P.ViewCount * 0.01) + (COALESCE(P.AnswerCount, 0) * 2) + (P.CommentCount * 0.75) + (COALESCE(P.FavoriteCount, 0) * 1.5) AS EngagementScore,
        EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 3600.0 AS HoursSinceCreationToLastActivity,
        (
            SELECT COUNT(DISTINCT PH.UserId)
            FROM PostHistory PH
            WHERE PH.PostId = P.Id
              AND PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24)
        ) AS UniqueEditorsCount,
        (
            SELECT MAX(PH.CreationDate)
            FROM PostHistory PH
            WHERE PH.PostId = P.Id
              AND PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24)
        ) AS LastEditHistoryDate
    FROM
        Posts P
    WHERE
        P.OwnerUserId IS NOT NULL
),
ExplodedPostTags AS (
    SELECT
        PEM.PostId,
        PEM.OwnerUserId,
        TRIM(tag_val) AS TagName
    FROM
        PostEngagementMetrics PEM,
        LATERAL (
            SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(PEM.Tags FROM 2 FOR LENGTH(PEM.Tags) - 2), '><')) AS tag_val
        ) AS T
    WHERE
        PEM.PostTypeId = 1
        AND PEM.Tags IS NOT NULL
        AND LENGTH(PEM.Tags) > 2
        AND TRIM(T.tag_val) IS NOT NULL AND TRIM(T.tag_val) != ''
),
UserPostInteraction AS (
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        UAS.ReputationTier,
        UAS.GoldBadges,
        UAS.SilverBadges,
        UAS.BronzeBadges,
        P.Id AS PostId,
        P.Title,
        P.PostTypeId,
        PEM.EngagementScore,
        PEM.UniqueEditorsCount,
        EXTRACT(EPOCH FROM (P.LastEditDate - P.CreationDate)) / 86400.0 AS DaysToFirstEdit,
        EXTRACT(EPOCH FROM (P.ClosedDate - P.CreationDate)) / 86400.0 AS DaysToClose,
        COALESCE(LENGTH(P.Body), 0) AS BodyLength,
        C.Id AS CommentId,
        C.Score AS CommentScore,
        C.CreationDate AS CommentCreationDate,
        (SELECT COUNT(P2.Id) FROM Posts P2 WHERE P2.OwnerUserId = UAS.UserId AND P2.PostTypeId = 1) AS TotalQuestionsByOwner,
        (SELECT COUNT(P2.Id) FROM Posts P2 WHERE P2.OwnerUserId = UAS.UserId AND P2.PostTypeId = 2) AS TotalAnswersByOwner,
        (SELECT SUM(V.BountyAmount) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 8) AS TotalBountyOnPost,
        DENSE_RANK() OVER (PARTITION BY UAS.UserId ORDER BY PEM.EngagementScore DESC, P.CreationDate DESC) AS UserPostEngagementRank,
        ROW_NUMBER() OVER (PARTITION BY UAS.UserId, P.PostTypeId ORDER BY P.CreationDate DESC) AS PostTypeCreationSequence,
        UAS.PrevAccessDate,
        P.CreationDate AS PostCreationDate
    FROM
        UserActivitySummary UAS
    LEFT JOIN
        Posts P ON UAS.UserId = P.OwnerUserId
    LEFT JOIN
        PostEngagementMetrics PEM ON P.Id = PEM.PostId
    LEFT JOIN
        Comments C ON P.Id = C.PostId AND C.UserId = UAS.UserId
    WHERE
        P.PostTypeId IN (1, 2)
        AND UAS.ReputationTier IS NOT NULL
),
AggregatedUserMetrics AS (
    SELECT
        UPI.UserId,
        UPI.DisplayName,
        UPI.ReputationTier,
        UPI.GoldBadges,
        UPI.SilverBadges,
        UPI.BronzeBadges,
        COUNT(DISTINCT UPI.PostId) AS TotalPosts,
        SUM(CASE WHEN UPI.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN UPI.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(UPI.EngagementScore) AS AvgPostEngagementScore,
        MAX(UPI.EngagementScore) AS MaxPostEngagementScore,
        SUM(UPI.UniqueEditorsCount) AS TotalUniqueEditorsAcrossPosts,
        AVG(UPI.DaysToFirstEdit) AS AvgDaysToFirstEdit,
        AVG(UPI.DaysToClose) AS AvgDaysToClose,
        SUM(UPI.BodyLength) AS TotalBodyLength,
        MAX(UPI.CommentCreationDate) AS LastCommentByOwnerDate,
        SUM(COALESCE(UPI.TotalBountyOnPost, 0)) AS TotalBountyReceived,
        COUNT(DISTINCT C2.UserId) FILTER (WHERE C2.PostId IN (SELECT PostId FROM UserPostInteraction WHERE UserId = UPI.UserId)) AS UniqueCommentersOnUserPosts,
        (
            SELECT SUM(V.BountyAmount)
            FROM Votes V
            WHERE V.UserId = UPI.UserId AND V.VoteTypeId = 8
        ) AS TotalBountyGivenByOwner,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY UPI.EngagementScore) AS MedianEngagementScore
    FROM
        UserPostInteraction UPI
    LEFT JOIN
        Comments C2 ON C2.PostId = UPI.PostId AND C2.UserId IS NOT NULL AND C2.UserId != UPI.UserId
    GROUP BY
        UPI.UserId, UPI.DisplayName, UPI.ReputationTier, UPI.GoldBadges, UPI.SilverBadges, UPI.BronzeBadges
),
RecentSignificantActivity AS (
    SELECT
        UserId,
        MAX(ActivityDate) AS LastSignificantActivityDate
    FROM (
        SELECT
            P.OwnerUserId AS UserId,
            P.CreationDate AS ActivityDate
        FROM
            Posts P
        WHERE
            P.AcceptedAnswerId IS NOT NULL OR P.Score > 100
        UNION ALL
        SELECT
            C.UserId AS UserId,
            C.CreationDate AS ActivityDate
        FROM
            Comments C
        WHERE
            C.Score > 5
    ) AS CombinedActivities
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
UserTopTags AS (
    SELECT
        OwnerUserId AS UserId,
        STRING_AGG(TagName, ', ' ORDER BY TagCount DESC) AS Top5Tags
    FROM (
        SELECT
            OwnerUserId,
            TagName,
            COUNT(*) AS TagCount,
            ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY COUNT(*) DESC, TagName ASC) as rn
        FROM
            ExplodedPostTags
        GROUP BY
            OwnerUserId, TagName
    ) AS RankedTags
    WHERE rn <= 5
    GROUP BY
        OwnerUserId
),
FinalBase AS (
    SELECT
        AUM.*,
        UAS.UserCreationDate,
        UAS.UserLastAccessDate,
        UAS.UserProfileViews,
        UAS.UpDownVoteRatio,
        UAS.PrevAccessDate,
        RSA.LastSignificantActivityDate,
        UTT.Top5Tags,
        -- counts for tags per user
        SUM(CASE WHEN TA_sql.TagName = 'sql' THEN 1 ELSE 0 END) OVER (PARTITION BY AUM.UserId) AS QuestionsWithSqlTag,
        SUM(CASE WHEN TA_perf.TagName = 'performance' THEN 1 ELSE 0 END) OVER (PARTITION BY AUM.UserId) AS QuestionsWithPerformanceTag,
        (SELECT P_HighEngage.Title FROM UserPostInteraction P_HighEngage WHERE P_HighEngage.UserId = AUM.UserId ORDER BY P_HighEngage.EngagementScore DESC, P_HighEngage.PostCreationDate DESC LIMIT 1) AS TopEngagementPostTitle,
        (SELECT AVG(C_User.Score) FROM Comments C_User WHERE C_User.UserId = AUM.UserId) AS AvgCommentScoreByUser,
        -- window functions computed here so they are not referenced in GROUP BY
        RANK() OVER (ORDER BY AUM.AvgPostEngagementScore DESC, AUM.TotalPosts DESC) AS GlobalEngagementRank,
        NTILE(10) OVER (ORDER BY AUM.TotalBountyReceived DESC) AS BountyReceiverDecile
    FROM
        AggregatedUserMetrics AUM
    JOIN
        UserActivitySummary UAS ON AUM.UserId = UAS.UserId
    LEFT JOIN
        RecentSignificantActivity RSA ON AUM.UserId = RSA.UserId
    LEFT JOIN
        UserTopTags UTT ON AUM.UserId = UTT.UserId
    LEFT JOIN
        ExplodedPostTags TA_sql ON AUM.UserId = TA_sql.OwnerUserId AND TA_sql.TagName = 'sql'
    LEFT JOIN
        ExplodedPostTags TA_perf ON AUM.UserId = TA_perf.OwnerUserId AND TA_perf.TagName = 'performance'
)
SELECT
    FB.UserId,
    FB.DisplayName,
    FB.ReputationTier,
    FB.GoldBadges,
    FB.SilverBadges,
    FB.BronzeBadges,
    FB.TotalPosts,
    FB.TotalQuestions,
    FB.TotalAnswers,
    FB.AvgPostEngagementScore,
    FB.MaxPostEngagementScore,
    FB.TotalUniqueEditorsAcrossPosts,
    FB.AvgDaysToFirstEdit,
    FB.AvgDaysToClose,
    FB.TotalBodyLength,
    FB.LastCommentByOwnerDate,
    FB.TotalBountyReceived,
    FB.TotalBountyGivenByOwner,
    FB.UniqueCommentersOnUserPosts,
    FB.LastSignificantActivityDate,
    FB.UserCreationDate,
    FB.UserLastAccessDate,
    FB.UserProfileViews,
    FB.UpDownVoteRatio AS UpdownVoteRatio,
    EXTRACT(EPOCH FROM (FB.UserLastAccessDate - FB.UserCreationDate)) / 86400.0 AS UserAccountAgeDays,
    ROUND(CAST(FB.TotalAnswers AS NUMERIC) / NULLIF(FB.TotalQuestions, 0), 2) AS AnswerQuestionRatio,
    FB.QuestionsWithSqlTag,
    FB.QuestionsWithPerformanceTag,
    FB.TopEngagementPostTitle,
    FB.AvgCommentScoreByUser,
    FB.GlobalEngagementRank,
    FB.BountyReceiverDecile,
    FB.Top5Tags,
    FB.PrevAccessDate,
    (FB.UserLastAccessDate - FB.PrevAccessDate) AS TimeSincePrevAccess
FROM
    FinalBase FB
WHERE
    FB.TotalPosts > 5
    AND (FB.ReputationTier IN ('Expert', 'Veteran') OR FB.GoldBadges > 0 OR FB.SilverBadges > 0)
    AND FB.AvgPostEngagementScore IS NOT NULL
ORDER BY
    FB.GlobalEngagementRank ASC, FB.DisplayName
LIMIT 1000;