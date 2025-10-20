WITH UserPostStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsCount,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS TotalAnswerScore,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END) AS TotalQuestionViewCount,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 AND P_Parent.AcceptedAnswerId = P.Id THEN P.Id END) AS AcceptedAnswersCount,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS AvgAnswerScore,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT PH_Edit.PostId) AS EditsMadeToOwnedPosts,
        COUNT(DISTINCT PH_Close.PostId) AS OwnedPostsClosed,
        MAX(P.CreationDate) AS LastPostCreationDate
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts P_Parent ON P.PostTypeId = 2 AND P.ParentId = P_Parent.Id
    LEFT JOIN PostHistory PH_Edit ON P.Id = PH_Edit.PostId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6, 8, 9)
    LEFT JOIN PostHistory PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    WHERE P.CreationDate >= DATE '2020-01-01'
    GROUP BY U.Id, U.DisplayName
),
UserBadgeStats AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges B
    WHERE B.Date >= DATE '2020-01-01'
    GROUP BY B.UserId
),
UserCommentStats AS (
    SELECT
        C.UserId,
        COUNT(C.Id) AS TotalComments,
        SUM(C.Score) AS TotalCommentScore,
        AVG(C.Score) AS AvgCommentScore
    FROM Comments C
    WHERE C.CreationDate >= DATE '2020-01-01'
    GROUP BY C.UserId
),
UserVoteActivity AS (
    SELECT
        V.UserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
    FROM Votes V
    WHERE V.CreationDate >= DATE '2020-01-01' AND V.UserId IS NOT NULL
    GROUP BY V.UserId
),
UserReceivedVoteStats AS (
    SELECT
        P.OwnerUserId AS UserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
    FROM Posts P
    JOIN Votes V ON P.Id = V.PostId
    WHERE P.CreationDate >= DATE '2020-01-01' AND V.CreationDate >= DATE '2020-01-01' AND P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
TopTagsPerUser AS (
    WITH RECURSIVE Numbers(n) AS (
        SELECT 1
        UNION ALL
        SELECT n + 1 FROM Numbers WHERE n < 100
    ),
    PostTags AS (
        SELECT
            P.OwnerUserId AS UserId,
            CASE
                WHEN P.Tags IS NULL THEN NULL
                WHEN LEFT(P.Tags,1) = '<' AND RIGHT(P.Tags,1) = '>' THEN SUBSTRING(P.Tags FROM 2 FOR (LENGTH(P.Tags) - 2))
                ELSE P.Tags
            END AS tags_only,
            P.CreationDate
        FROM Posts P
        WHERE P.PostTypeId = 1
          AND P.Tags IS NOT NULL
          AND P.Tags <> ''
          AND P.CreationDate >= DATE '2020-01-01'
    ),
    SplitTags AS (
        SELECT
            pt.UserId,
            TRIM(SPLIT_PART(pt.tags_only, '><', n.n)) AS TagName,
            n.n AS idx
        FROM PostTags pt
        JOIN Numbers n ON n.n <= (LENGTH(pt.tags_only) - LENGTH(REPLACE(pt.tags_only, '><', '')) + 1)
        WHERE TRIM(SPLIT_PART(pt.tags_only, '><', n.n)) <> ''
    ),
    TagCounts AS (
        SELECT
            st.UserId,
            st.TagName,
            COUNT(*) AS TagUsageCount
        FROM SplitTags st
        GROUP BY st.UserId, st.TagName
    ),
    RankedTags AS (
        SELECT
            tc.UserId,
            tc.TagName,
            tc.TagUsageCount,
            ROW_NUMBER() OVER (PARTITION BY tc.UserId ORDER BY tc.TagUsageCount DESC, tc.TagName ASC) AS rn
        FROM TagCounts tc
    )
    SELECT
        rt.UserId,
        STRING_AGG(rt.TagName, ', ' ORDER BY rt.TagUsageCount DESC, rt.TagName ASC) AS TopTags
    FROM RankedTags rt
    WHERE rt.rn <= 3
    GROUP BY rt.UserId
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    COALESCE(UPS.QuestionsCount, 0) AS QuestionsCount,
    COALESCE(UPS.AnswersCount, 0) AS AnswersCount,
    COALESCE(UPS.AcceptedAnswersCount, 0) AS AcceptedAnswersCount,
    COALESCE(UPS.TotalQuestionScore, 0) AS TotalQuestionScore,
    COALESCE(UPS.TotalAnswerScore, 0) AS TotalAnswerScore,
    COALESCE(UPS.TotalQuestionViewCount, 0) AS TotalQuestionViewCount,
    COALESCE(UPS.AvgAnswerScore, 0.0) AS AvgAnswerScore,
    COALESCE(UBS.TotalBadges, 0) AS TotalBadges,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UCS.TotalComments, 0) AS TotalComments,
    COALESCE(UCS.AvgCommentScore, 0.0) AS AvgCommentScore,
    COALESCE(UVA.UpVotesGiven, 0) AS UpVotesGiven,
    COALESCE(UVA.DownVotesGiven, 0) AS DownVotesGiven,
    COALESCE(URS.UpVotesReceived, 0) AS UpVotesReceived,
    COALESCE(URS.DownVotesReceived, 0) AS DownVotesReceived,
    COALESCE(UPS.EditsMadeToOwnedPosts, 0) AS EditsMadeToOwnedPosts,
    COALESCE(UPS.OwnedPostsClosed, 0) AS OwnedPostsClosed,
    COALESCE(TTU.TopTags, 'N/A') AS TopUserTags,
    (
        COALESCE(UPS.AcceptedAnswersCount, 0) * 10.0 +
        COALESCE(UPS.TotalAnswerScore, 0) * 0.75 +
        COALESCE(UPS.TotalQuestionScore, 0) * 0.25 +
        COALESCE(UBS.GoldBadges, 0) * 15.0 +
        COALESCE(UBS.SilverBadges, 0) * 5.0 +
        COALESCE(UCS.TotalComments, 0) * 0.1 +
        COALESCE(URS.UpVotesReceived, 0) * 0.5 -
        COALESCE(URS.DownVotesReceived, 0) * 1.0 +
        COALESCE(UPS.TotalQuestionViewCount, 0) * 0.001
    ) AS CompositeImpactScore
FROM Users U
LEFT JOIN UserPostStats UPS ON U.Id = UPS.UserId
LEFT JOIN UserBadgeStats UBS ON U.Id = UBS.UserId
LEFT JOIN UserCommentStats UCS ON U.Id = UCS.UserId
LEFT JOIN UserVoteActivity UVA ON U.Id = UVA.UserId
LEFT JOIN UserReceivedVoteStats URS ON U.Id = URS.UserId
LEFT JOIN TopTagsPerUser TTU ON U.Id = TTU.UserId
WHERE
    U.CreationDate >= DATE '2019-01-01'
    AND (UPS.UserId IS NOT NULL OR UBS.UserId IS NOT NULL OR UCS.UserId IS NOT NULL OR UVA.UserId IS NOT NULL OR URS.UserId IS NOT NULL)
ORDER BY CompositeImpactScore DESC, U.Reputation DESC
LIMIT 100;