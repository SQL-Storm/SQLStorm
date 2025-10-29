WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersProvided,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END), 0) AS TotalQuestionScore,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END), 0) AS TotalAnswerScore,
        COALESCE(AVG(C.Score), 0.0) AS AvgCommentScore,
        MAX(C.CreationDate) AS LastCommentDate,
        MIN(P.CreationDate) AS FirstPostDate,
        COALESCE(UPPER(SUBSTRING(U.DisplayName, 1, 1)) || SUBSTRING(U.DisplayName, 2), 'Anonymous User') AS FormattedDisplayName,
        CAST(U.UpVotes AS NUMERIC) / NULLIF((U.UpVotes + U.DownVotes), 0) AS UpDownVoteRatio
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
PostHistoricalMetrics AS (
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 END) AS CloseEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 END) AS ReopenEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 END) AS DeleteEvents,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastBodyEditDate,
        (
            SELECT PH_INNER.Comment
            FROM PostHistory PH_INNER
            WHERE PH_INNER.PostId = PH.PostId
              AND PH_INNER.PostHistoryTypeId = 10
            ORDER BY PH_INNER.CreationDate DESC
            LIMIT 1
        ) AS LastCloseReasonComment
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 5)
    GROUP BY PH.PostId
),
DailyTagScores AS (
    SELECT
        TRIM(tag) AS TagName,
        DATE_TRUNC('day', P.CreationDate) AS TagDate,
        SUM(P.Score) AS DailyTotalScore,
        COUNT(P.Id) AS DailyPostCount,
        COUNT(DISTINCT P.OwnerUserId) AS DailyDistinctOwners
    FROM Posts P
    CROSS JOIN LATERAL (
      SELECT regexp_split_to_table(
        SUBSTRING(P.Tags FROM 2 FOR (CHAR_LENGTH(P.Tags) - 2)),
        '><'
      ) AS tag
    ) t
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND P.Tags <> ''
    GROUP BY TRIM(tag), DATE_TRUNC('day', P.CreationDate)
),
AggregatedTagPerformance AS (
    SELECT
        TagName,
        TagDate,
        DailyTotalScore,
        DailyPostCount,
        DailyDistinctOwners,
        AVG(DailyTotalScore) OVER (PARTITION BY TagName ORDER BY TagDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS RollingAvg7DayScore,
        RANK() OVER (PARTITION BY TagDate ORDER BY DailyPostCount DESC) AS RankByDailyPosts
    FROM DailyTagScores
),
BadgeMilestones AS (
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate,
        MIN(B.Date) AS FirstBadgeDate,
        COALESCE(EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - MAX(B.Date))), -1) AS DaysSinceLastBadge,
        CASE
            WHEN COUNT(CASE WHEN B.Class = 1 THEN 1 END) > 0 AND COUNT(CASE WHEN B.Class = 2 THEN 1 END) > 5 THEN 'Elite Badge Holder'
            WHEN COUNT(CASE WHEN B.Class = 1 THEN 1 END) > 0 THEN 'Gold Badge Holder'
            WHEN COUNT(CASE WHEN B.Class = 2 THEN 1 END) > 0 THEN 'Silver Badge Holder'
            ELSE 'Bronze/No Gold/Silver'
        END AS BadgeTier
    FROM Badges B
    GROUP BY B.UserId
),
RelatedPostSummary AS (
    SELECT
        PL.PostId,
        PL.RelatedPostId,
        L.Name AS LinkTypeName,
        P_Link.Score AS LinkedPostScore,
        P_Related.Score AS RelatedPostScore,
        P_Related.ViewCount AS RelatedPostViewCount,
        COALESCE(P_Link.Title, 'Untitled Post (' || PL.PostId || ')') || ' <-> ' || COALESCE(P_Related.Title, 'Untitled Related Post (' || PL.RelatedPostId || ')') AS LinkDescription
    FROM PostLinks PL
    JOIN LinkTypes L ON PL.LinkTypeId = L.Id
    LEFT JOIN Posts P_Link ON PL.PostId = P_Link.Id
    LEFT JOIN Posts P_Related ON PL.RelatedPostId = P_Related.Id
    WHERE L.Id = 1
    UNION ALL
    SELECT
        PL.PostId,
        PL.RelatedPostId,
        L.Name AS LinkTypeName,
        P_Link.Score AS LinkedPostScore,
        P_Related.Score AS RelatedPostScore,
        P_Related.ViewCount AS RelatedPostViewCount,
        COALESCE(P_Link.Title, 'Untitled Post (' || PL.PostId || ')') || ' <-- DUPLICATE OF --> ' || COALESCE(P_Related.Title, 'Untitled Related Post (' || PL.RelatedPostId || ')') AS LinkDescription
    FROM PostLinks PL
    JOIN LinkTypes L ON PL.LinkTypeId = L.Id
    LEFT JOIN Posts P_Link ON PL.PostId = P_Link.Id
    LEFT JOIN Posts P_Related ON PL.RelatedPostId = P_Related.Id
    WHERE L.Id = 3
)
SELECT
    UE.UserId,
    UE.FormattedDisplayName,
    UE.Reputation,
    UE.TotalQuestionsAsked,
    UE.TotalAnswersProvided,
    UE.TotalCommentsMade,
    UE.AvgCommentScore,
    COALESCE(UE.UpDownVoteRatio, 0.0) AS UpDownVoteRatio,
    BM.GoldBadges,
    BM.SilverBadges,
    BM.BronzeBadges,
    BM.DaysSinceLastBadge,
    BM.BadgeTier,
    PHM.CloseEvents,
    PHM.ReopenEvents,
    PHM.DeleteEvents,
    PHM.LastCloseReasonComment,
    (
        SELECT C_CORR.Text
        FROM Comments C_CORR
        JOIN Posts P_CORR ON C_CORR.PostId = P_CORR.Id
        WHERE C_CORR.UserId = UE.UserId
          AND P_CORR.OwnerUserId IS NOT NULL
          AND P_CORR.OwnerUserId <> UE.UserId
        ORDER BY C_CORR.Score DESC, C_CORR.CreationDate DESC
        LIMIT 1
    ) AS HighestScoringOtherComment,
    NTILE(10) OVER (ORDER BY UE.Reputation, UE.UpDownVoteRatio DESC) AS ReputationUpDownVoteBin,
    LAG(UE.TotalQuestionsAsked, 1, 0) OVER (ORDER BY UE.Reputation) - UE.TotalQuestionsAsked AS QuestionDiffFromNextLowerRep,
    COALESCE(RPS_Agg.TotalLinkedPosts, 0) AS TotalLinkedPosts,
    COALESCE(RPS_Agg.TotalDuplicatePosts, 0) AS TotalDuplicatePosts,
    COALESCE(RPS_Agg.AvgRelatedPostScore, 0.0) AS AvgRelatedPostScore,
    CASE
        WHEN UE.TotalQuestionsAsked > 100 AND UE.TotalAnswersProvided > 200 AND UE.Reputation > 5000 AND BM.GoldBadges > 0 THEN 'Super Contributor'
        WHEN UE.TotalQuestionsAsked > 50 AND UE.TotalAnswersProvided > 100 AND UE.Reputation > 1000 THEN 'Active Contributor'
        WHEN UE.TotalCommentsMade > 50 AND UE.AvgCommentScore > 2 THEN 'Engaged Commenter'
        WHEN UE.FormattedDisplayName LIKE 'A%' AND UE.CreationDate > '2020-01-01' THEN 'New A-Starter'
        ELSE 'Casual User'
    END AS UserEngagementCategory,
    (
        SELECT ATP.TagName
        FROM AggregatedTagPerformance ATP
        JOIN (
          SELECT P2.Id, TRIM(tag) AS TagName
          FROM Posts P2
          CROSS JOIN LATERAL (
            SELECT regexp_split_to_table(SUBSTRING(P2.Tags FROM 2 FOR (CHAR_LENGTH(P2.Tags) - 2)), '><') AS tag
          ) tt
          WHERE P2.OwnerUserId = UE.UserId AND P2.PostTypeId = 1 AND P2.Tags IS NOT NULL AND P2.Tags <> ''
        ) P_User_Tags ON ATP.TagName = P_User_Tags.TagName
        GROUP BY ATP.TagName
        ORDER BY SUM(ATP.DailyPostCount) DESC, MAX(ATP.RollingAvg7DayScore) DESC
        LIMIT 1
    ) AS MostActiveOwnedTag
FROM UserEngagement UE
LEFT JOIN BadgeMilestones BM ON UE.UserId = BM.UserId
LEFT JOIN (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT CASE WHEN RPS.LinkTypeName = 'Linked' THEN RPS.PostId END) AS TotalLinkedPosts,
        COUNT(DISTINCT CASE WHEN RPS.LinkTypeName = 'Duplicate' THEN RPS.PostId END) AS TotalDuplicatePosts,
        AVG(RPS.RelatedPostScore) AS AvgRelatedPostScore
    FROM RelatedPostSummary RPS
    JOIN Posts P ON RPS.PostId = P.Id
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
) RPS_Agg ON UE.UserId = RPS_Agg.UserId
LEFT JOIN (
    SELECT
        P.OwnerUserId AS UserId,
        PHM.CloseEvents,
        PHM.ReopenEvents,
        PHM.DeleteEvents,
        PHM.LastCloseReasonComment,
        P.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.LastActivityDate DESC, P.CreationDate DESC) as rn
    FROM Posts P
    JOIN PostHistoricalMetrics PHM ON P.Id = PHM.PostId
    WHERE P.PostTypeId = 1
) PHM ON UE.UserId = PHM.UserId AND PHM.rn = 1
WHERE
    UE.Reputation > 500
    AND (UE.TotalQuestionsAsked + UE.TotalAnswersProvided > 10 OR UE.TotalCommentsMade > 20)
    AND (BM.DaysSinceLastBadge IS NULL OR BM.DaysSinceLastBadge > 30 OR BM.DaysSinceLastBadge = -1)
    AND UE.FormattedDisplayName NOT LIKE '%admin%'
    AND (
        (PHM.CloseEvents > 0 AND PHM.ReopenEvents = 0 AND PHM.LastCloseReasonComment IS NOT NULL)
        OR
        (UE.UpDownVoteRatio > 0.7 AND UE.TotalCommentsMade > 10 AND UE.AvgCommentScore > 1)
        OR
        (UE.FirstPostDate IS NOT NULL AND UE.FirstPostDate > '2015-01-01' AND UE.Reputation > 2000)
    )
ORDER BY
    UE.Reputation DESC, UE.LastCommentDate DESC
LIMIT 1000;