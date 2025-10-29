WITH RecentUserActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(U.Views, 0) AS UserProfileViews,
        COALESCE(U.UpVotes, 0) AS UserLifetimeUpVotes,
        COALESCE(U.DownVotes, 0) AS UserLifetimeDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsAuthored,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAuthored,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersAuthored,
        SUM(CASE WHEN P.PostTypeId = 1 AND P.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR) THEN 1 ELSE 0 END) AS RecentQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 AND P.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR) THEN 1 ELSE 0 END) AS RecentAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViewCount,
        SUM(COALESCE(P.AnswerCount, 0)) AS TotalPostAnswerCount,
        SUM(COALESCE(P.FavoriteCount, 0)) AS TotalPostFavoriteCount,
        MAX(P.LastActivityDate) AS LastPostActivityDate
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 ELSE NULL END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadges,
        MAX(B.Date) AS LatestBadgeDate,
        MIN(B.Date) AS EarliestBadgeDate,
        -- Use a portable aggregation for badge names; STRING_AGG with FILTER is supported in several DBs but some may require different syntax.
        STRING_AGG(DISTINCT CASE WHEN B.Class = 1 THEN B.Name ELSE NULL END, '; ') AS GoldBadgeNames
    FROM
        Badges B
    GROUP BY
        B.UserId
),
PostDetailsWithTags AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Title,
        P.Tags,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount AS PostFavoriteCount,
        -- Extract first tag in a more portable way: remove leading '<' and trailing '>' after splitting on '><'
        TRIM(BOTH '<>' FROM SPLIT_PART(P.Tags, '><', 1)) AS PrimaryTag,
        (SELECT COUNT(DISTINCT V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(DISTINCT V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownVoteCount,
        (SELECT COUNT(DISTINCT C.Id) FROM Comments C WHERE C.PostId = P.Id) AS DirectCommentCount
    FROM
        Posts P
    WHERE
        P.PostTypeId IN (1, 2)
        AND P.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '5' YEAR)
        AND P.Tags IS NOT NULL
),
PostLifecycleHistory AS (
    SELECT
        PH.PostId,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloseEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopenEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS TotalDeleteEvents,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosureDate,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate ELSE NULL END) AS LastEditByHistoryDate,
        STRING_AGG(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN COALESCE(CRT.Name, PH.Comment) ELSE NULL END, '; ') AS AggregatedCloseReasons,
        STRING_AGG(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 AND PH.UserId IS NOT NULL THEN U.DisplayName ELSE NULL END, ', ') AS UsersInvolvedInClose
    FROM
        PostHistory PH
    LEFT JOIN CloseReasonTypes CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment = CAST(CRT.Id AS VARCHAR(50))
    LEFT JOIN Users U ON PH.UserId = U.Id
    GROUP BY
        PH.PostId
),
SelfAcceptedAnswerPosts AS (
    SELECT
        P.Id AS QuestionPostId,
        P.AcceptedAnswerId,
        P.OwnerUserId AS QuestionOwnerId
    FROM Posts P
    WHERE P.PostTypeId = 1
      AND P.AcceptedAnswerId IS NOT NULL
      AND EXISTS (SELECT 1 FROM Posts A WHERE A.Id = P.AcceptedAnswerId AND A.OwnerUserId = P.OwnerUserId)
),
HighImpactUserPosts AS (
    SELECT
        P.OwnerUserId AS UserId,
        P.Id AS PostId,
        'TopViewedQuestion' AS ImpactType
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.ViewCount > 500000 AND P.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '7' YEAR)
    UNION ALL
    SELECT
        P.OwnerUserId AS UserId,
        P.Id AS PostId,
        'TopScoredAnswer' AS ImpactType
    FROM Posts P
    WHERE P.PostTypeId = 2 AND P.Score > 750 AND P.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '7' YEAR)
)
SELECT
    RUA.UserId,
    RUA.DisplayName,
    RUA.Reputation,
    RUA.UserCreationDate,
    RUA.UserProfileViews,
    COALESCE(UBS.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS UserBronzeBadges,
    UBS.LatestBadgeDate,
    RUA.RecentQuestions,
    RUA.RecentAnswers,
    PDT.PostId,
    PDT.PostTypeId,
    PDT.Title,
    PDT.PrimaryTag,
    PDT.PostCreationDate,
    PDT.PostScore,
    PDT.PostViewCount,
    PDT.PostCommentCount,
    PDT.PostFavoriteCount,
    COALESCE(PDT.UpVoteCount, 0) AS PostUpVotes,
    COALESCE(PDT.DownVoteCount, 0) AS PostDownVotes,
    PLE.TotalEditEvents AS PostEditCount,
    PLE.TotalCloseEvents AS PostCloseCount,
    PLE.TotalReopenEvents AS PostReopenCount,
    PLE.LastClosureDate,
    PLE.AggregatedCloseReasons,
    PLE.UsersInvolvedInClose,
    HIP.ImpactType,
    CAST((PDT.PostScore * 0.4 + PDT.PostViewCount * 0.001 + PDT.PostCommentCount * 0.2 + PDT.PostFavoriteCount * 0.3) AS NUMERIC) AS PostEngagementScore,
    CASE
        WHEN RUA.Reputation > 50000 AND (RUA.RecentQuestions + RUA.RecentAnswers) > 10 THEN 'Highly Active & Influential'
        WHEN RUA.Reputation > 10000 AND (RUA.RecentQuestions > 2 OR RUA.RecentAnswers > 5) THEN 'Active Contributor'
        WHEN RUA.TotalPostsAuthored > 0 AND RUA.LastAccessDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '6' MONTH) THEN 'Occasional Participant'
        WHEN RUA.TotalPostsAuthored = 0 AND RUA.TotalPostScore = 0 AND RUA.UserProfileViews < 100 AND RUA.UserCreationDate < (CAST('2024-10-01' AS DATE) - INTERVAL '2' YEAR) THEN 'Dormant User'
        ELSE 'New/Passive User'
    END AS UserActivityLevel,
    RANK() OVER (PARTITION BY PDT.PrimaryTag ORDER BY (PDT.PostScore * 0.4 + PDT.PostViewCount * 0.001) DESC, PDT.PostCreationDate DESC) AS TagEngagementRank,
    AVG(CASE WHEN PDT.PostTypeId = 1 AND PDT.PostCreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR) THEN PDT.PostScore ELSE NULL END) OVER (PARTITION BY RUA.UserId) AS AvgRecentQuestionScore,
    (LOWER(PDT.Title) LIKE '%sql%' OR LOWER(PDT.Tags) LIKE '%<sql>%') AS IsSqlRelated,
    (LOWER(PDT.Title) LIKE '%performance%' OR LOWER(PDT.Tags) LIKE '%<performance>%') AS IsPerformanceRelated,
    CASE WHEN SAA.QuestionPostId IS NOT NULL THEN TRUE ELSE FALSE END AS HasOwnerSelfAcceptedAnswer,
    ((CAST(COALESCE(PDT.UpVoteCount, 0) AS NUMERIC) / NULLIF(CAST(COALESCE(PDT.UpVoteCount, 0) + COALESCE(PDT.DownVoteCount, 0) AS NUMERIC), 0) > 0.8 OR PDT.DownVoteCount = 0)
     AND (LENGTH(TRIM(REPLACE(PDT.Title, ' ', ''))) < LENGTH(PDT.Title) - 1)) AS IsHighQualityAndMultiWordTitle
FROM
    RecentUserActivity RUA
LEFT JOIN UserBadgeSummary UBS ON RUA.UserId = UBS.UserId
LEFT JOIN PostDetailsWithTags PDT ON RUA.UserId = PDT.OwnerUserId
LEFT JOIN PostLifecycleHistory PLE ON PDT.PostId = PLE.PostId
LEFT JOIN SelfAcceptedAnswerPosts SAA ON PDT.PostId = SAA.QuestionPostId AND RUA.UserId = SAA.QuestionOwnerId
LEFT JOIN HighImpactUserPosts HIP ON RUA.UserId = HIP.UserId AND PDT.PostId = HIP.PostId
WHERE
    RUA.Reputation > 5000
    AND RUA.LastAccessDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
    AND PDT.PostId IS NOT NULL
    AND PDT.PostTypeId IN (1, 2)
    AND PDT.PostScore >= 0
    AND PDT.PrimaryTag IS NOT NULL AND PDT.PrimaryTag NOT IN ('discussion', 'meta', 'bug', 'feature-request')
    AND (
        PDT.Tags LIKE '%<sql>%' OR PDT.Tags LIKE '%<database>%' OR PDT.Tags LIKE '%<query>%'
        OR LOWER(PDT.Title) LIKE '%index%' OR LOWER(PDT.Title) LIKE '%optimization%' OR LOWER(PDT.Title) LIKE '%performance%'
    )
    AND (
        (RUA.RecentQuestions + RUA.RecentAnswers > 0)
        OR (COALESCE(UBS.GoldBadges, 0) > 0)
        OR (PDT.PostScore > 50 AND PDT.PostViewCount > 10000)
    )
ORDER BY
    RUA.Reputation DESC,
    UserActivityLevel DESC,
    PostEngagementScore DESC,
    RUA.UserId,
    PDT.PostCreationDate DESC;