-- {"query": "19062.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3335} 
WITH UserPostStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        COUNT(P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostViews,
        MAX(P.CreationDate) AS LastPostActivity,
        COALESCE(CAST(SUM(P.Score) AS NUMERIC) / NULLIF(COUNT(P.Id), 0), 0) AS AvgPostScore,
        -- Complicated string expression and array handling for tags
        COUNT(DISTINCT tag_val) FILTER (WHERE P.Tags IS NOT NULL AND P.PostTypeId = 1) AS UniqueTagsUsedCount
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN LATERAL UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')) AS t(tag_val) ON P.Tags IS NOT NULL AND P.PostTypeId = 1
    WHERE P.PostTypeId IN (1, 2, 4, 5) -- Include Questions, Answers, TagWikiExcerpt, TagWiki for comprehensive post analysis
    GROUP BY U.Id, U.DisplayName
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
        MIN(B.Date) AS FirstBadgeDate,
        MAX(B.Date) AS LastBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
UserPostStateActions AS (
    SELECT
        PH.UserId,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN PH.PostId END) AS PostsUserHelpedClose,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.PostId END) AS PostsUserHelpedReopen,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (35, 36) THEN PH.PostId END) AS PostsUserInvolvedInMigration
    FROM PostHistory PH
    WHERE PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
PostEventSequence AS (
    SELECT
        PH.PostId,
        PH.UserId,
        PH.CreationDate AS EventDate,
        PHT.Name AS EventType,
        LAG(PHT.Name, 1, 'INITIAL') OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousEventType,
        LEAD(PHT.Name, 1, 'FINAL') OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS NextEventType
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
),
UserPostLifecyclePatterns AS (
    SELECT
        PES.UserId,
        COUNT(DISTINCT PES.PostId) FILTER (WHERE PES.EventType = 'Post Closed' AND PES.NextEventType = 'Post Reopened') AS ClosedThenReopenedPostsCount,
        COUNT(DISTINCT PES.PostId) FILTER (WHERE PES.EventType = 'Post Reopened' AND PES.PreviousEventType = 'Post Closed') AS ReopenedAfterClosedPostsCount,
        COUNT(DISTINCT PES.PostId) FILTER (WHERE PES.EventType = 'Post Deleted' AND PES.NextEventType = 'Post Undeleted') AS DeletedThenUndeletedPostsCount
    FROM PostEventSequence PES
    WHERE PES.UserId IS NOT NULL
    GROUP BY PES.UserId
),
UserCommentActivity AS (
    SELECT
        C.UserId,
        COUNT(C.Id) AS CommentsMade,
        COALESCE(SUM(C.Score), 0) AS TotalCommentsScoreMade,
        MIN(C.CreationDate) AS FirstCommentMade,
        MAX(C.CreationDate) AS LastCommentMade
    FROM Comments C
    WHERE C.UserId IS NOT NULL
    GROUP BY C.UserId
),
PostCommentsSummary AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(C.Id) AS TotalCommentsOnMyPosts,
        COALESCE(SUM(C.Score), 0) AS TotalScoreOnMyPostsComments,
        COALESCE(CAST(SUM(C.Score) AS NUMERIC) / NULLIF(COUNT(C.Id), 0), 0) AS AvgScoreOnMyPostsComments
    FROM Posts P
    JOIN Comments C ON P.Id = C.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserVoteMetrics AS (
    SELECT
        U.Id AS UserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesMade,
        SUM(CASE WHEN V.VoteTypeId = 8 THEN V.BountyAmount ELSE 0 END) AS TotalBountyOffered,
        SUM(CASE WHEN V.VoteTypeId = 9 THEN V.BountyAmount ELSE 0 END) AS TotalBountyReceivedOnMyPosts
    FROM Users U
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id
),
AcceptedAnswersSummary AS (
    SELECT
        A.OwnerUserId AS UserId,
        COUNT(Q.Id) AS AcceptedAnswersCount
    FROM Posts Q -- Question post
    JOIN Posts A ON Q.AcceptedAnswerId = A.Id -- Answer post
    WHERE Q.PostTypeId = 1 AND A.PostTypeId = 2
    GROUP BY A.OwnerUserId
),
-- Set operator example: Combine users who have either created a significant number of questions
-- OR have received a significant number of accepted answers.
HighImpactUsers_Set AS (
    SELECT UserId FROM UserPostStats WHERE QuestionsAsked > 50 OR AnswersProvided > 100
    UNION
    SELECT UserId FROM AcceptedAnswersSummary WHERE AcceptedAnswersCount > 20
),
FinalUserRanking AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        UPS.TotalPosts,
        UPS.QuestionsAsked,
        UPS.AnswersProvided,
        UPS.TotalPostScore,
        UPS.TotalPostViews,
        UPS.AvgPostScore,
        UPS.UniqueTagsUsedCount,
        UBS.TotalBadges,
        UBS.GoldBadges,
        UBS.SilverBadges,
        UBS.BronzeBadges,
        UBS.TagBasedBadges,
        UPSA.PostsUserHelpedClose,
        UPSA.PostsUserHelpedReopen,
        UPLP.ClosedThenReopenedPostsCount,
        UPLP.ReopenedAfterClosedPostsCount,
        UPLP.DeletedThenUndeletedPostsCount,
        UCA.CommentsMade,
        UCA.TotalCommentsScoreMade,
        PCS.TotalCommentsOnMyPosts,
        PCS.AvgScoreOnMyPostsComments,
        UVM.UpVotesGiven,
        UVM.DownVotesGiven,
        AAS.AcceptedAnswersCount,
        -- Complicated calculation combining multiple metrics with COALESCE for NULL safety
        (
            (COALESCE(UPS.TotalPostScore, 0) * 0.5) +
            (COALESCE(UPS.TotalPostViews, 0) * 0.01) +
            (COALESCE(UBS.GoldBadges, 0) * 100) +
            (COALESCE(UBS.SilverBadges, 0) * 50) +
            (COALESCE(UBS.BronzeBadges, 0) * 10) +
            (COALESCE(AAS.AcceptedAnswersCount, 0) * 75) +
            (COALESCE(UCA.TotalCommentsScoreMade, 0) * 0.5) +
            (COALESCE(U.UpVotes, 0) * 0.1) - -- User's received upvotes directly from Users table
            (COALESCE(U.DownVotes, 0) * 0.2) -- User's received downvotes directly from Users table
            + (COALESCE(UPLP.ReopenedAfterClosedPostsCount, 0) * 20) -- Bonus for helping reopen posts
            - (COALESCE(UPSA.PostsUserHelpedDelete, 0) * 5) -- Penalty for deletion actions
        ) AS CompositeActivityScore,
        -- NULL Logic and String Expressions in CASE statement for UserTier
        CASE
            WHEN U.DisplayName IS NULL OR LENGTH(TRIM(U.DisplayName)) = 0 THEN 'Anonymous Contributor'
            WHEN U.Reputation > 50000 AND COALESCE(UBS.GoldBadges, 0) >= 5 AND COALESCE(UPS.TotalPosts, 0) > 100 AND COALESCE(UPS.AvgPostScore, 0) > 5 THEN 'Legendary'
            WHEN U.Reputation > 10000 AND COALESCE(UBS.SilverBadges, 0) >= 5 AND COALESCE(UPS.TotalPosts, 0) > 50 AND COALESCE(UPS.AvgPostScore, 0) > 2 THEN 'Veteran'
            WHEN U.Reputation > 1000 AND COALESCE(UPS.TotalPosts, 0) > 10 THEN 'Active'
            ELSE 'Novice/Casual'
        END AS UserTier,
        -- Correlated Subquery 1: Check for users who have been the last editor of a post that later became involved in a duplicate link.
        (
            SELECT COUNT(DISTINCT PH_inner.PostId)
            FROM PostHistory PH_inner
            WHERE PH_inner.UserId = U.Id
              AND PH_inner.PostHistoryTypeId = 5 -- Edit Body
              AND PH_inner.CreationDate = (SELECT MAX(PH2.CreationDate) FROM PostHistory PH2 WHERE PH2.PostId = PH_inner.PostId AND PH2.PostHistoryTypeId = 5) -- Last editor
              AND EXISTS (SELECT 1 FROM PostLinks PL_inner WHERE (PL_inner.PostId = PH_inner.PostId OR PL_inner.RelatedPostId = PH_inner.PostId) AND PL_inner.LinkTypeId = 3)
        ) AS LastEditedDuplicateRelatedPostCount,
        -- Correlated Subquery 2: Count comments made by this user on posts owned by other 'Veteran' users (simplified criteria for 'Veteran')
        (
            SELECT COUNT(DISTINCT C_inner.PostId)
            FROM Comments C_inner
            JOIN Posts P_inner ON C_inner.PostId = P_inner.Id
            JOIN Users U_inner ON P_inner.OwnerUserId = U_inner.Id
            WHERE C_inner.UserId = U.Id
              AND U_inner.Reputation > 10000 -- Simplified 'Veteran' reputation check
              AND U_inner.Id != U.Id -- Not commenting on their own posts
        ) AS CommentsOnHighRepUserPosts
    FROM Users U
    LEFT JOIN UserPostStats UPS ON U.Id = UPS.UserId
    LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
    LEFT JOIN UserPostStateActions UPSA ON U.Id = UPSA.UserId
    LEFT JOIN UserPostLifecyclePatterns UPLP ON U.Id = UPLP.UserId
    LEFT JOIN UserCommentActivity UCA ON U.Id = UCA.UserId
    LEFT JOIN PostCommentsSummary PCS ON U.Id = PCS.UserId
    LEFT JOIN UserVoteMetrics UVM ON U.Id = UVM.UserId
    LEFT JOIN AcceptedAnswersSummary AAS ON U.Id = AAS.UserId
    WHERE U.Id IN (SELECT UserId FROM HighImpactUsers_Set) -- Filter users by the results of a set operation
      AND U.LastAccessDate >= (NOW() - INTERVAL '1 year') -- Only active users in the last year
      AND (U.AboutMe LIKE '%SQL%' OR U.AboutMe LIKE '%database%' OR U.AboutMe IS NULL) -- Users interested in SQL/DB or with no 'AboutMe'
),
-- Window function example: Rank users within their tier and assign an overall quintile
RankedUsers AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY UserTier ORDER BY CompositeActivityScore DESC, Reputation DESC) AS RankInTier,
        NTILE(5) OVER (ORDER BY CompositeActivityScore DESC, Reputation DESC) AS OverallActivityQuintile
    FROM FinalUserRanking
)
SELECT
    UserId,
    DisplayName,
    Reputation,
    UserTier,
    RankInTier,
    OverallActivityQuintile,
    CompositeActivityScore,
    TotalPosts,
    QuestionsAsked,
    AnswersProvided,
    TotalPostScore,
    TotalPostViews,
    AvgPostScore,
    UniqueTagsUsedCount,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TotalBadges,
    PostsUserHelpedClose,
    PostsUserHelpedReopen,
    ClosedThenReopenedPostsCount,
    ReopenedAfterClosedPostsCount,
    DeletedThenUndeletedPostsCount,
    CommentsMade,
    TotalCommentsScoreMade,
    TotalCommentsOnMyPosts,
    AvgScoreOnMyPostsComments,
    UpVotesGiven,
    DownVotesGiven,
    AcceptedAnswersCount,
    LastEditedDuplicateRelatedPostCount,
    CommentsOnHighRepUserPosts
FROM RankedUsers
WHERE CompositeActivityScore > 500 -- Filter for users with a meaningful activity score
ORDER BY OverallActivityQuintile ASC, RankInTier ASC, Reputation DESC;