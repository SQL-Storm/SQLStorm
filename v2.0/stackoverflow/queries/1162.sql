WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        DATE_PART('day', CAST('2024-10-01 12:34:56' AS timestamp) - U.CreationDate) AS UserAgeInDays,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE NULL END) AS AvgQuestionScore,
        MAX(P.Score) AS MaxPostScoreByOwner,
        (SELECT COUNT(DISTINCT PH.Id) FROM PostHistory PH WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS TotalEdits
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastEditDate,
        P.ClosedDate,
        P.ParentId,
        P.AcceptedAnswerId,
        P.Tags,
        COALESCE(P.Score * 0.7 + P.ViewCount * 0.05 + P.AnswerCount * 1.5 + P.CommentCount * 0.6 + P.FavoriteCount * 2, 0) AS EngagementIndex,
        SUM(CASE WHEN PV.VoteTypeId = 2 THEN 1 ELSE 0 END) AS PostUpVotesReceived,
        SUM(CASE WHEN PV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS PostDownVotesReceived,
        COUNT(DISTINCT CL.Id) AS TotalPostComments,
        CASE
            WHEN P.PostTypeId = 1 AND P.ClosedDate IS NOT NULL THEN 'Closed Question'
            WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 'Answered Question'
            WHEN P.PostTypeId = 1 THEN 'Open Question'
            WHEN P.PostTypeId = 2 AND P.ParentId IS NOT NULL THEN 'Answer'
            ELSE 'Other Post Type'
        END AS PostStatus,
        DENSE_RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS UserPostRankByScore,
        LAG(P.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate ASC) AS PreviousPostCreationDate
    FROM
        Posts P
    LEFT JOIN Votes PV ON P.Id = PV.PostId AND PV.VoteTypeId IN (2, 3)
    LEFT JOIN Comments CL ON P.Id = CL.PostId
    WHERE P.PostTypeId IN (1, 2) AND P.CreationDate >= CAST('2022-01-01' AS date)
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount,
        P.CommentCount, P.FavoriteCount, P.LastEditDate, P.ClosedDate, P.ParentId, P.AcceptedAnswerId, P.Tags
),
TagAnalysis AS (
    SELECT
        UPPER(TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')))) AS TagName,
        P.Id AS PostId,
        P.OwnerUserId,
        P.Score
    FROM
        Posts P
    WHERE
        P.PostTypeId = 1 AND P.Tags IS NOT NULL AND P.Tags <> ''
),
OverallTagPerformance AS (
    SELECT
        TA.TagName,
        COUNT(DISTINCT TA.PostId) AS TaggedPostCount,
        AVG(TA.Score) AS AvgTagScore,
        RANK() OVER (ORDER BY AVG(TA.Score) DESC, COUNT(DISTINCT TA.PostId) DESC) AS TagPopularityRank,
        (SELECT MAX(T.Count) FROM Tags T WHERE T.TagName = TA.TagName) AS OfficialTagCount
    FROM
        TagAnalysis TA
    GROUP BY
        TA.TagName
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserAgeInDays,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalComments,
    UAS.TotalBadges,
    UAS.UpVotesGiven,
    UAS.DownVotesGiven,
    UAS.AvgQuestionScore,
    UAS.TotalEdits,
    PEM.PostId,
    PEM.PostTypeId,
    PEM.PostCreationDate,
    PEM.Score AS PostScore,
    PEM.ViewCount AS PostViewCount,
    PEM.AnswerCount AS PostAnswerCount,
    PEM.CommentCount AS PostCommentCount,
    PEM.FavoriteCount AS PostFavoriteCount,
    PEM.EngagementIndex,
    PEM.PostUpVotesReceived,
    PEM.PostDownVotesReceived,
    PEM.PostStatus,
    PEM.UserPostRankByScore,
    DATE_PART('day', PEM.PostCreationDate - PEM.PreviousPostCreationDate) AS DaysSincePreviousPost,
    OTP.TagName AS MostImpactfulTagName,
    OTP.AvgTagScore AS MostImpactfulTagAvgScore,
    OTP.TaggedPostCount AS MostImpactfulTagPosts,
    COALESCE(OTP.OfficialTagCount, 0) AS ActualOfficialTagUsage,
    (
        SELECT
            MAX(CommentScore)
        FROM (
            SELECT
                C.Score AS CommentScore,
                ROW_NUMBER() OVER (ORDER BY C.Score DESC, C.CreationDate DESC) as rn
            FROM Comments C
            WHERE C.PostId = PEM.PostId AND C.UserId = UAS.UserId
        ) AS TopCommentSub
        WHERE rn = 1
    ) AS TopCommentScoreOnPost,
    CASE
        WHEN UAS.Reputation > 10000 AND UAS.TotalBadges > 50 AND UAS.TotalEdits > 100 THEN 'Legendary Contributor'
        WHEN UAS.Reputation > 5000 AND UAS.TotalBadges > 20 AND UAS.TotalEdits > 50 THEN 'Veteran Contributor'
        WHEN UAS.Reputation > 1000 AND UAS.TotalBadges > 5 THEN 'Active Contributor'
        ELSE 'Casual Contributor'
    END AS UserContributionTier,
    NTILE(5) OVER (ORDER BY UAS.Reputation DESC, UAS.TotalPosts DESC) AS UserReputationQuintile,
    NULLIF(PEM.PostUpVotesReceived, 0) / NULLIF(PEM.PostDownVotesReceived, 0) AS UpDownVoteRatio,
    (LOWER(SUBSTRING(UAS.DisplayName FROM 1 FOR 1)) = 'a' OR LOWER(SUBSTRING(UAS.DisplayName FROM 1 FOR 1)) = 'z') AS StartsWithAOrZ
FROM
    UserActivitySummary UAS
INNER JOIN
    PostEngagementMetrics PEM ON UAS.UserId = PEM.OwnerUserId
LEFT JOIN LATERAL (
    SELECT
        TA.TagName,
        OTP_Sub.AvgTagScore,
        OTP_Sub.TaggedPostCount,
        OTP_Sub.OfficialTagCount,
        ROW_NUMBER() OVER (ORDER BY OTP_Sub.AvgTagScore DESC, OTP_Sub.TaggedPostCount DESC) AS TagRankForPost
    FROM
        TagAnalysis TA
    INNER JOIN OverallTagPerformance OTP_Sub ON TA.TagName = OTP_Sub.TagName
    WHERE TA.PostId = PEM.PostId
    ORDER BY TagRankForPost
    LIMIT 1
) OTP ON TRUE
WHERE
    UAS.Reputation > 500
    AND PEM.Score > 5
    AND (
        PEM.PostTypeId = 1
        OR (PEM.PostTypeId = 2 AND PEM.ParentId IN (SELECT Q.Id FROM Posts Q WHERE Q.PostTypeId = 1 AND Q.ViewCount > 10000))
    )
    AND UAS.UserAgeInDays > 365
    AND PEM.PostCreationDate > UAS.UserCreationDate + INTERVAL '90 days'
    AND (
        SELECT COUNT(LI.Id)
        FROM PostLinks LI
        WHERE LI.PostId = PEM.PostId AND LI.LinkTypeId = 1
    ) > 0
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory PH
        WHERE PH.PostId = PEM.PostId AND PH.PostHistoryTypeId = 35
    )
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.UserAgeInDays, UAS.TotalPosts, UAS.TotalQuestions,
    UAS.TotalAnswers, UAS.TotalComments, UAS.TotalBadges, UAS.UpVotesGiven, UAS.DownVotesGiven,
    UAS.AvgQuestionScore, UAS.TotalEdits,
    PEM.PostId, PEM.PostTypeId, PEM.PostCreationDate, PEM.Score, PEM.ViewCount, PEM.AnswerCount,
    PEM.CommentCount, PEM.FavoriteCount, PEM.EngagementIndex, PEM.PostUpVotesReceived, PEM.PostDownVotesReceived,
    PEM.PostStatus, PEM.UserPostRankByScore, PEM.PreviousPostCreationDate,
    OTP.TagName, OTP.AvgTagScore, OTP.TaggedPostCount, OTP.OfficialTagCount,
    UAS.UserCreationDate, UAS.DisplayName
ORDER BY
    UserContributionTier DESC,
    UAS.Reputation DESC,
    PEM.EngagementIndex DESC,
    DaysSincePreviousPost ASC
LIMIT 10000;