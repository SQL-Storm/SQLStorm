-- {"query": "1490.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3119}
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViews,
        MAX(P.LastActivityDate) AS LastPostActivity,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        (SELECT AVG(C.Score) FROM Comments C WHERE C.UserId = U.Id AND C.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months') AS AvgRecentCommentScore_CorrelatedSubquery
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 0 OR COUNT(DISTINCT B.Id) > 0
),
PostEditActivity AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.Title,
        P.Tags,
        P.PostTypeId,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.Id END) AS MajorEditsCount,
        MAX(PH.CreationDate) AS LastHistoryDate,
        MIN(PH.CreationDate) AS FirstHistoryDate,
        COALESCE(MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment END), 'N/A') AS LastCloseReasonId,
        COUNT(DISTINCT PH.UserId) AS DistinctEditors,
        -- Determine first and last editor per post using distinct subqueries to avoid FILTER on windowed MIN/MAX
        (SELECT ph2.UserId FROM PostHistory ph2 WHERE ph2.PostId = P.Id ORDER BY ph2.CreationDate ASC, ph2.Id ASC LIMIT 1) AS FirstEditorId,
        (SELECT ph3.UserId FROM PostHistory ph3 WHERE ph3.PostId = P.Id ORDER BY ph3.CreationDate DESC, ph3.Id DESC LIMIT 1) AS LastEditorId_Window
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.PostTypeId IN (1, 2)
    GROUP BY P.Id, P.OwnerUserId, P.AcceptedAnswerId, P.CreationDate, P.LastEditDate, P.LastActivityDate, P.Score, P.ViewCount, P.Title, P.Tags, P.PostTypeId
),
TrendingTags AS (
    SELECT
        Tag,
        COUNT(DISTINCT PostId) AS TaggedPostsCount,
        SUM(Score) AS TagTotalScore,
        AVG(Score) AS TagAverageScore,
        MAX(PostCreationDate) AS LatestTagPost,
        DENSE_RANK() OVER (ORDER BY SUM(Score) DESC, COUNT(DISTINCT PostId) DESC) AS TagRankByScoreAndCount
    FROM (
        SELECT
            P.Id AS PostId,
            P.Score,
            P.CreationDate AS PostCreationDate,
            TRIM(SPLIT_PART(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><', s.a)) AS Tag
        FROM Posts P, GENERATE_SERIES(1, LENGTH(P.Tags) - LENGTH(REPLACE(P.Tags, '><', '')) + 1) s(a)
        WHERE P.PostTypeId = 1
          AND P.Tags IS NOT NULL
          AND P.Tags != ''
          AND P.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    ) AS TaggedPosts
    WHERE Tag IS NOT NULL AND Tag != ''
    GROUP BY Tag
    HAVING COUNT(DISTINCT PostId) >= 5 AND SUM(Score) >= 50
),
PostCommentSummary AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalComments,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        AVG(COALESCE(C.Score, 0)) AS AvgCommentScore,
        MAX(C.CreationDate) AS LatestCommentDate,
        CAST(SUM(CASE WHEN C.Score > 0 THEN 1 ELSE 0 END) AS DECIMAL) / NULLIF(COUNT(C.Id), 0) AS PositiveCommentRatio,
        COUNT(DISTINCT C.UserId) AS DistinctCommenters
    FROM Comments C
    GROUP BY C.PostId
),
CategorizedInterestingPosts AS (
    SELECT
        PEA.PostId,
        'HighValueQuestion' AS PostCategory,
        PEA.PostScore AS CategoryMetricValue
    FROM PostEditActivity PEA
    WHERE PEA.PostTypeId = 1 AND PEA.PostScore >= 50 AND PEA.MajorEditsCount >= 3

    UNION ALL

    SELECT
        PEA.PostId,
        'HighlyDiscussedPost' AS PostCategory,
        PCS.TotalComments AS CategoryMetricValue
    FROM PostEditActivity PEA
    JOIN PostCommentSummary PCS ON PEA.PostId = PCS.PostId
    WHERE PCS.TotalComments >= 20 AND PEA.PostScore < 50

    UNION ALL

    SELECT
        PEA.PostId,
        'HighViewClosedQuestion' AS PostCategory,
        PEA.PostViewCount AS CategoryMetricValue
    FROM PostEditActivity PEA
    WHERE PEA.PostTypeId = 1 AND PEA.LastCloseReasonId != 'N/A' AND PEA.PostViewCount >= 5000 AND PEA.LastActivityDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'

    UNION ALL

    SELECT
        P.Id AS PostId,
        'NewUserUpvotedPost' AS PostCategory,
        P.Score AS CategoryMetricValue
    FROM Posts P
    JOIN Users U ON P.OwnerUserId = U.Id
    WHERE U.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year' AND P.Score >= 10 AND P.PostTypeId IN (1,2)
)
SELECT
    UE.UserId,
    UE.DisplayName AS UserDisplayName,
    UE.Reputation,
    UE.UserViews,
    UE.TotalQuestions,
    UE.TotalAnswers,
    PEA.PostId,
    PEA.Title AS PostTitle,
    PEA.PostTypeId,
    PEA.PostCreationDate,
    PEA.PostScore,
    PEA.PostViewCount,
    PEA.TotalHistoryEntries AS PostHistoryCount,
    PEA.MajorEditsCount,
    PEA.DistinctEditors AS PostDistinctEditors,
    PEA.LastCloseReasonId,
    PCS.TotalComments,
    PCS.AvgCommentScore,
    PCS.PositiveCommentRatio,
    CP.PostCategory,
    TT.Tag AS TrendingTag,
    TT.TagRankByScoreAndCount AS TrendingTagRank,
    (UE.Reputation * 0.1 + UE.UserUpVotes * 0.5 - UE.UserDownVotes * 0.2) AS UserImpactScore,
    (PEA.PostScore * 0.7 + PEA.PostViewCount * 0.05 + COALESCE(PCS.TotalComments, 0) * 0.1 + PEA.MajorEditsCount * 0.02) AS PostEngagementIndex,
    EXTRACT(DAY FROM (PEA.LastActivityDate - PEA.PostCreationDate)) AS DaysSinceCreation,
    COALESCE(PCS.AvgCommentScore, 0.0) AS NormalizedAvgCommentScore,
    CASE
        WHEN PEA.MajorEditsCount > 5 AND PEA.PostScore < 10 THEN 'Heavily Edited, Low Score'
        WHEN PEA.PostViewCount > 1000 AND COALESCE(PCS.TotalComments, 0) = 0 AND PEA.LastCloseReasonId = 'N/A' THEN 'High Views, No Comments'
        WHEN PEA.LastCloseReasonId != 'N/A' THEN 'Closed Post'
        WHEN PEA.PostTypeId = 1 AND PEA.AcceptedAnswerId IS NOT NULL THEN 'Question_With_Accepted_Answer'
        ELSE 'Normal'
    END AS PostStatusCategory,
    UPPER(SUBSTRING(PEA.Title FROM 1 FOR 1)) || SUBSTRING(PEA.Title FROM 2 FOR LENGTH(PEA.Title)) AS CapitalizedTitle,
    REPLACE(PEA.Tags, '><', ', ') AS FormattedTags,
    (
        SELECT U2.Reputation
        FROM Users U2
        WHERE U2.Id = PEA.LastEditorId_Window
    ) AS LastEditorReputation,
    RANK() OVER (PARTITION BY UE.UserId ORDER BY PEA.PostScore DESC, PEA.PostViewCount DESC) AS UserPostRank,
    LAG(PEA.PostScore, 1, 0) OVER (PARTITION BY UE.UserId ORDER BY PEA.PostCreationDate ASC) AS PreviousPostScore,
    LEAD(PEA.PostScore, 1, 0) OVER (PARTITION BY UE.UserId ORDER BY PEA.PostCreationDate ASC) AS NextPostScore
FROM UserEngagement UE
LEFT JOIN PostEditActivity PEA ON UE.UserId = PEA.OwnerUserId
LEFT JOIN PostCommentSummary PCS ON PEA.PostId = PCS.PostId
LEFT JOIN (
    SELECT DISTINCT
        p_tags.PostId,
        tt.Tag,
        tt.TagRankByScoreAndCount
    FROM PostEditActivity p_tags,
         GENERATE_SERIES(1, LENGTH(p_tags.Tags) - LENGTH(REPLACE(p_tags.Tags, '><', '')) + 1) s(a)
    JOIN TrendingTags tt ON TRIM(SPLIT_PART(SUBSTRING(p_tags.Tags, 2, LENGTH(p_tags.Tags) - 2), '><', s.a)) = tt.Tag
    WHERE p_tags.Tags IS NOT NULL AND p_tags.Tags != '' AND p_tags.PostTypeId = 1
) TT ON PEA.PostId = TT.PostId
LEFT JOIN CategorizedInterestingPosts CP ON PEA.PostId = CP.PostId
WHERE
    UE.Reputation > 500
    AND (
        CP.PostCategory IS NOT NULL
        OR (TT.Tag IS NOT NULL AND TT.TagRankByScoreAndCount <= 10)
    )
    AND UE.AvgRecentCommentScore_CorrelatedSubquery IS NOT NULL
ORDER BY
    PostEngagementIndex DESC,
    UserImpactScore DESC,
    PEA.LastActivityDate DESC
LIMIT 100;