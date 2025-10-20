-- {"query": "49002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2678} 
WITH TagRelevantPosts AS (
    SELECT
        P.Id,
        P.PostTypeId,
        P.OwnerUserId,
        P.Score,
        P.AcceptedAnswerId,
        P.ParentId,
        P.CommunityOwnedDate,
        P.ClosedDate
    FROM Posts AS P
    WHERE P.OwnerUserId IS NOT NULL
      AND (P.Tags LIKE '%<sql>%' OR P.Tags LIKE '%<database>%')
),
UserTagContributions AS (
    SELECT
        U.Id AS UserId,
        SUM(CASE WHEN TRP.PostTypeId = 1 THEN TRP.Score ELSE 0 END) AS TotalTagQuestionScore,
        SUM(CASE WHEN TRP.PostTypeId = 2 THEN TRP.Score ELSE 0 END) AS TotalTagAnswerScore,
        COUNT(TRP.Id) AS TotalRelevantPosts,
        COUNT(DISTINCT CASE WHEN TRP.PostTypeId = 1 THEN TRP.Id END) AS RelevantQuestionsAsked,
        COUNT(DISTINCT CASE WHEN TRP.PostTypeId = 2 THEN TRP.Id END) AS RelevantAnswersGiven,
        COUNT(DISTINCT CASE WHEN TRP.PostTypeId = 1 AND TRP.AcceptedAnswerId IS NOT NULL THEN TRP.Id END) AS TaggedQuestionsAskedWithAcceptedAnswer
    FROM Users AS U
    LEFT JOIN TagRelevantPosts AS TRP ON U.Id = TRP.OwnerUserId
    GROUP BY U.Id
),
UserAcceptedTagAnswers AS (
    SELECT
        A.OwnerUserId AS UserId,
        COUNT(DISTINCT A.Id) AS TaggedAnswersAccepted
    FROM Posts AS Q -- Q for Question
    JOIN Posts AS A ON Q.AcceptedAnswerId = A.Id -- A for Accepted Answer
    WHERE Q.PostTypeId = 1
      AND A.PostTypeId = 2
      AND (Q.Tags LIKE '%<sql>%' OR Q.Tags LIKE '%<database>%')
      AND A.OwnerUserId IS NOT NULL
    GROUP BY A.OwnerUserId
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges AS B
    GROUP BY B.UserId
),
UserPostHistorySummary AS (
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.Id END) AS MajorEdits, -- Edit Title, Body, Tags
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (10, 11) THEN PH.Id END) AS CloseReopenEvents, -- Post Closed, Post Reopened
        COUNT(DISTINCT CASE WHEN PH.PostId IN (SELECT Id FROM TagRelevantPosts WHERE OwnerUserId = PH.UserId) AND PH.PostHistoryTypeId = 50 THEN PH.Id END) AS CommunityBumpsOnOwnedTagPosts
    FROM PostHistory AS PH
    WHERE PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
UserCommentInteraction AS (
    SELECT
        C.UserId,
        COUNT(C.Id) AS CommentsMade,
        AVG(C.Score) AS AvgCommentScore,
        COUNT(DISTINCT CASE WHEN P.OwnerUserId IS NOT NULL AND P.OwnerUserId != C.UserId AND (P.Tags LIKE '%<sql>%' OR P.Tags LIKE '%<database>%') THEN C.Id END) AS CommentsOnOthersTagPosts
    FROM Comments AS C
    JOIN Posts AS P ON C.PostId = P.Id
    WHERE C.UserId IS NOT NULL
    GROUP BY C.UserId
),
UserVoteBehavior AS (
    SELECT
        V.UserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesGiven, -- Favorite (AKA bookmark)
        COUNT(DISTINCT CASE WHEN V.VoteTypeId IN (6, 7) THEN V.Id END) AS CloseReopenVotesMade,
        COUNT(DISTINCT CASE WHEN V.VoteTypeId IN (2,3) AND P.CommunityOwnedDate IS NOT NULL THEN V.Id END) AS VotesOnCommunityOwnedPosts
    FROM Votes AS V
    JOIN Posts AS P ON V.PostId = P.Id
    WHERE V.UserId IS NOT NULL
    GROUP BY V.UserId
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.UpVotes AS TotalUpvotesReceived,
    U.DownVotes AS TotalDownvotesReceived,
    U.Views AS ProfileViews,
    COALESCE(UTC.TotalTagQuestionScore, 0) AS TotalTagQuestionScore,
    COALESCE(UTC.TotalTagAnswerScore, 0) AS TotalTagAnswerScore,
    COALESCE(UTC.TotalRelevantPosts, 0) AS TotalRelevantPosts,
    COALESCE(UTC.RelevantQuestionsAsked, 0) AS RelevantQuestionsAsked,
    COALESCE(UTC.RelevantAnswersGiven, 0) AS RelevantAnswersGiven,
    COALESCE(UTC.TaggedQuestionsAskedWithAcceptedAnswer, 0) AS TaggedQuestionsAskedWithAcceptedAnswer,
    COALESCE(UATA.TaggedAnswersAccepted, 0) AS TaggedAnswersAccepted,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(UPHS.MajorEdits, 0) AS MajorEdits,
    COALESCE(UPHS.CloseReopenEvents, 0) AS CloseReopenEvents,
    COALESCE(UPHS.CommunityBumpsOnOwnedTagPosts, 0) AS CommunityBumpsOnOwnedTagPosts,
    COALESCE(UCI.CommentsMade, 0) AS CommentsMade,
    COALESCE(UCI.AvgCommentScore, 0) AS AvgCommentScore,
    COALESCE(UCI.CommentsOnOthersTagPosts, 0) AS CommentsOnOthersTagPosts,
    COALESCE(UVB.UpvotesGiven, 0) AS UpvotesGiven,
    COALESCE(UVB.DownvotesGiven, 0) AS DownvotesGiven,
    COALESCE(UVB.FavoritesGiven, 0) AS FavoritesGiven,
    COALESCE(UVB.CloseReopenVotesMade, 0) AS CloseReopenVotesMade,
    COALESCE(UVB.VotesOnCommunityOwnedPosts, 0) AS VotesOnCommunityOwnedPosts,
    -- Composite Score Calculation
    (
        U.Reputation * 0.1
        + COALESCE(UTC.TotalTagQuestionScore, 0) * 0.5
        + COALESCE(UTC.TotalTagAnswerScore, 0) * 0.4
        + COALESCE(UTC.RelevantQuestionsAsked, 0) * 2
        + COALESCE(UTC.RelevantAnswersGiven, 0) * 1.5
        + COALESCE(UTC.TaggedQuestionsAskedWithAcceptedAnswer, 0) * 5
        + COALESCE(UATA.TaggedAnswersAccepted, 0) * 6
        + COALESCE(UBS.GoldBadges, 0) * 10
        + COALESCE(UBS.SilverBadges, 0) * 5
        + COALESCE(UPHS.MajorEdits, 0) * 0.8
        + COALESCE(UPHS.CloseReopenEvents, 0) * 3
        + COALESCE(UCI.CommentsMade, 0) * 0.2
        + COALESCE(UCI.AvgCommentScore, 0) * 0.5
        + COALESCE(UCI.CommentsOnOthersTagPosts, 0) * 1
        + COALESCE(UVB.UpvotesGiven, 0) * 0.1
        - COALESCE(UVB.DownvotesGiven, 0) * 0.2
        + COALESCE(UVB.CloseReopenVotesMade, 0) * 2
    ) AS CompositeScore,
    -- Window functions for ranking and distribution
    RANK() OVER (ORDER BY
        (
            U.Reputation * 0.1
            + COALESCE(UTC.TotalTagQuestionScore, 0) * 0.5
            + COALESCE(UTC.TotalTagAnswerScore, 0) * 0.4
            + COALESCE(UTC.RelevantQuestionsAsked, 0) * 2
            + COALESCE(UTC.RelevantAnswersGiven, 0) * 1.5
            + COALESCE(UTC.TaggedQuestionsAskedWithAcceptedAnswer, 0) * 5
            + COALESCE(UATA.TaggedAnswersAccepted, 0) * 6
            + COALESCE(UBS.GoldBadges, 0) * 10
            + COALESCE(UBS.SilverBadges, 0) * 5
            + COALESCE(UPHS.MajorEdits, 0) * 0.8
            + COALESCE(UPHS.CloseReopenEvents, 0) * 3
            + COALESCE(UCI.CommentsMade, 0) * 0.2
            + COALESCE(UCI.AvgCommentScore, 0) * 0.5
            + COALESCE(UCI.CommentsOnOthersTagPosts, 0) * 1
            + COALESCE(UVB.UpvotesGiven, 0) * 0.1
            - COALESCE(UVB.DownvotesGiven, 0) * 0.2
            + COALESCE(UVB.CloseReopenVotesMade, 0) * 2
        ) DESC, U.CreationDate ASC
    ) AS OverallRank,
    NTILE(10) OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) AS ReputationDecile,
    ROW_NUMBER() OVER (PARTITION BY COALESCE(UBS.GoldBadges, 0) > 0 ORDER BY U.Reputation DESC) AS RankWithinGoldBadgeGroup
FROM Users AS U
LEFT JOIN UserTagContributions AS UTC ON U.Id = UTC.UserId
LEFT JOIN UserAcceptedTagAnswers AS UATA ON U.Id = UATA.UserId
LEFT JOIN UserBadgeSummary AS UBS ON U.Id = UBS.UserId
LEFT JOIN UserPostHistorySummary AS UPHS ON U.Id = UPHS.UserId
LEFT JOIN UserCommentInteraction AS UCI ON U.Id = UCI.UserId
LEFT JOIN UserVoteBehavior AS UVB ON U.Id = UVB.UserId
WHERE
    U.Reputation > 500
    AND (COALESCE(UBS.GoldBadges, 0) > 0 OR COALESCE(UBS.SilverBadges, 0) > 0)
    AND (COALESCE(UTC.RelevantQuestionsAsked, 0) > 0 OR COALESCE(UTC.RelevantAnswersGiven, 0) > 0)
    AND U.LastAccessDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year')
ORDER BY CompositeScore DESC, U.Reputation DESC
LIMIT 100;