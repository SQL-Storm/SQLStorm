-- {"query": "1407.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3720} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - U.CreationDate)) / 86400 AS AccountAgeDays, -- Convert to days
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(LENGTH(C.Text)) * 1.0 / NULLIF(COUNT(DISTINCT C.Id), 0) AS AvgCommentLength, -- Average length of user's comments
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN V.VoteTypeId IN (2, 8) THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 1 THEN 1 ELSE 0 END) AS TotalAcceptedAnswersByOthers -- Number of times user accepted an answer
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        COALESCE(P.AcceptedAnswerId, -1) AS AcceptedAnswerId, -- -1 if no accepted answer
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - P.LastActivityDate)) / 3600 AS HoursSinceLastActivity,
        LENGTH(P.Body) AS BodyLength,
        LENGTH(P.Title) AS TitleLength,
        (SELECT COUNT(DISTINCT SUBSTRING(T.Tag, 2, LENGTH(T.Tag)-2)) FROM (SELECT UNNEST(string_to_array(SUBSTRING(COALESCE(P.Tags, '<>'), 2, LENGTH(COALESCE(P.Tags, '<>'))-2), '><')) AS Tag) AS T) AS TagCount, -- Count distinct tags
        CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditCount, -- Edits to title, body, tags
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS PostUpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS PostDownVotesReceived
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2,3) -- Only up/down votes for post itself
    WHERE P.PostTypeId IN (1, 2) -- Only consider Questions (1) and Answers (2)
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.LastActivityDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.AcceptedAnswerId, P.Body, P.Title, P.Tags
),
QuestionClosingTrends AS (
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId,
        P.CreationDate AS QuestionCreationDate,
        MAX(PH_Closed.CreationDate) AS LastClosedDate,
        MAX(PH_Reopened.CreationDate) AS LastReopenedDate,
        COUNT(DISTINCT CASE WHEN PH_Closed.PostHistoryTypeId = 10 THEN PH_Closed.Id END) AS CloseEvents, -- Count distinct close events
        COUNT(DISTINCT CASE WHEN PH_Reopened.PostHistoryTypeId = 11 THEN PH_Reopened.Id END) AS ReopenEvents, -- Count distinct reopen events
        COALESCE(MAX(CR.Name) FILTER (WHERE PH_Closed.PostHistoryTypeId = 10 AND PH_Closed.Comment ~ '^[0-9]+$'), 'N/A') AS MostRecentCloseReasonName, -- Safely get close reason name
        MAX(PH_Closed.Comment) FILTER (WHERE PH_Closed.PostHistoryTypeId = 10) AS MostRecentCloseReasonIdText -- Store original comment for ID
    FROM Posts P
    LEFT JOIN PostHistory PH_Closed ON P.Id = PH_Closed.PostId AND PH_Closed.PostHistoryTypeId = 10 -- Post Closed
    LEFT JOIN PostHistory PH_Reopened ON P.Id = PH_Reopened.PostId AND PH_Reopened.PostHistoryTypeId = 11 -- Post Reopened
    LEFT JOIN CloseReasonTypes CR ON PH_Closed.Comment ~ '^[0-9]+$' AND PH_Closed.Comment::smallint = CR.Id -- Join only if comment is a numeric ID
    WHERE P.PostTypeId = 1 -- Only questions
    GROUP BY P.Id, P.OwnerUserId, P.CreationDate
),
UserPostTagStats AS (
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        Tag.TagName, -- Tag name from the lateral join
        COUNT(DISTINCT PEM.PostId) AS UserQuestionsWithTag,
        AVG(PEM.Score) AS UserAvgScoreForTag,
        AVG(PEM.ViewCount) AS UserAvgViewCountForTag,
        SUM(PEM.HasAcceptedAnswer) AS UserQuestionsWithAcceptedAnswerForTag,
        ROW_NUMBER() OVER (PARTITION BY UAS.UserId ORDER BY COUNT(DISTINCT PEM.PostId) DESC, AVG(PEM.Score) DESC) AS TagRankForUser -- Rank tags by user
    FROM UserActivitySummary UAS
    INNER JOIN PostEngagementMetrics PEM ON UAS.UserId = PEM.OwnerUserId
    INNER JOIN Posts P ON PEM.PostId = P.Id AND P.PostTypeId = 1 -- Ensure it's a question
    CROSS JOIN LATERAL ( -- Lateral join to unnest tags
        SELECT UNNEST(string_to_array(SUBSTRING(COALESCE(P.Tags, '<>'), 2, LENGTH(COALESCE(P.Tags, '<>'))-2), '><')) AS TagName
    ) AS Tag
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 -- Filter posts with actual tags
    GROUP BY UAS.UserId, UAS.DisplayName, Tag.TagName
),
MainQueryData AS (
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        UAS.Reputation,
        UAS.TotalQuestions,
        UAS.TotalAnswers,
        UAS.TotalCommentsMade,
        COALESCE(UAS.AvgCommentLength, 0.0) AS AverageCommentBodyLength,
        UAS.GoldBadges,
        UAS.SilverBadges,
        UAS.BronzeBadges,
        UAS.TotalAcceptedAnswersByOthers,
        SUM(PEM.Score) AS TotalPostScoreOwned,
        AVG(PEM.Score) AS AvgPostScoreOwned,
        AVG(PEM.ViewCount) AS AvgPostViewCountOwned,
        SUM(PEM.AnswerCount) AS TotalAnswersReceivedOnQuestions,
        SUM(PEM.FavoriteCount) AS TotalFavoritesReceived,
        SUM(QCT.CloseEvents) AS TotalQuestionCloseEvents,
        SUM(QCT.ReopenEvents) AS TotalQuestionReopenEvents,
        CAST(SUM(QCT.CloseEvents) AS DECIMAL) / NULLIF(SUM(UAS.TotalQuestions), 0) AS CloseRatePerQuestion,
        MAX(CASE WHEN UPTS.TagRankForUser = 1 THEN UPTS.TagName ELSE NULL END) AS TopTagByQuestions,
        MAX(CASE WHEN UPTS.TagRankForUser = 1 THEN UPTS.UserQuestionsWithTag ELSE NULL END) AS TopTagQuestionCount,
        ( -- Non-correlated subquery for linked questions
            SELECT COUNT(DISTINCT PL_Inner.RelatedPostId)
            FROM PostLinks PL_Inner
            WHERE PL_Inner.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = UAS.UserId AND PostTypeId = 1)
        ) AS UserLinkedQuestionCount,
        NTILE(10) OVER (ORDER BY UAS.Reputation DESC) AS ReputationDecile, -- Divide users into 10 reputation groups
        RANK() OVER (ORDER BY SUM(COALESCE(PEM.Score, 0)) DESC, UAS.Reputation DESC) AS OverallScoreRank,
        ( -- Correlated subquery: Most recent close reason for the user's highest scoring question
            SELECT CR.Name
            FROM QuestionClosingTrends QCT_corr
            LEFT JOIN CloseReasonTypes CR ON QCT_corr.MostRecentCloseReasonIdText ~ '^[0-9]+$' AND QCT_corr.MostRecentCloseReasonIdText::smallint = CR.Id
            WHERE QCT_corr.OwnerUserId = UAS.UserId
            AND QCT_corr.QuestionId = (
                SELECT PostId
                FROM PostEngagementMetrics
                WHERE OwnerUserId = UAS.UserId AND PostTypeId = 1 -- Ensure it's a question owned by the user
                ORDER BY Score DESC, ViewCount DESC
                LIMIT 1
            )
            ORDER BY QCT_corr.LastClosedDate DESC
            LIMIT 1
        ) AS TopQuestionCloseReason,
        (UAS.TotalUpVotesGiven * 1.0) / NULLIF(UAS.TotalDownVotesGiven, 0) AS UpToDownVoteRatioGiven, -- User's voting ratio
        'HighReputationWithQuestionActivity' AS UserSegment -- Segment identifier
    FROM UserActivitySummary UAS
    LEFT JOIN PostEngagementMetrics PEM ON UAS.UserId = PEM.OwnerUserId AND PEM.PostTypeId = 1 -- Only questions for user's owned posts stats
    LEFT JOIN QuestionClosingTrends QCT ON UAS.UserId = QCT.OwnerUserId
    LEFT JOIN UserPostTagStats UPTS ON UAS.UserId = UPTS.UserId AND UPTS.TagRankForUser = 1 -- Join only for the top ranked tag
    WHERE UAS.Reputation > 5000 -- High reputation users
      AND UAS.TotalQuestions > 10 -- Active question posters
      AND EXISTS (SELECT 1 FROM PostEngagementMetrics sub_pem WHERE sub_pem.OwnerUserId = UAS.UserId AND sub_pem.PostTypeId = 1 AND sub_pem.Score > 0) -- At least one positive score question
    GROUP BY UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.TotalQuestions, UAS.TotalAnswers, UAS.TotalCommentsMade, UAS.AvgCommentLength, UAS.GoldBadges, UAS.SilverBadges, UAS.BronzeBadges, UAS.TotalAcceptedAnswersByOthers, UAS.TotalUpVotesGiven, UAS.TotalDownVotesGiven
    HAVING SUM(COALESCE(QCT.CloseEvents, 0)) > 0 OR SUM(COALESCE(QCT.ReopenEvents, 0)) > 0 -- Must have some closing/reopening activity
),
SecondaryUserData AS (
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        UAS.Reputation,
        UAS.TotalQuestions,
        UAS.TotalAnswers,
        UAS.TotalCommentsMade,
        COALESCE(UAS.AvgCommentLength, 0.0) AS AverageCommentBodyLength,
        UAS.GoldBadges,
        UAS.SilverBadges,
        UAS.BronzeBadges,
        UAS.TotalAcceptedAnswersByOthers,
        SUM(PEM.Score) AS TotalPostScoreOwned,
        AVG(PEM.Score) AS AvgPostScoreOwned,
        AVG(PEM.ViewCount) AS AvgPostViewCountOwned,
        SUM(PEM.AnswerCount) AS TotalAnswersReceivedOnQuestions,
        SUM(PEM.FavoriteCount) AS TotalFavoritesReceived,
        SUM(QCT.CloseEvents) AS TotalQuestionCloseEvents,
        SUM(QCT.ReopenEvents) AS TotalQuestionReopenEvents,
        CAST(SUM(QCT.CloseEvents) AS DECIMAL) / NULLIF(SUM(UAS.TotalQuestions), 0) AS CloseRatePerQuestion,
        MAX(CASE WHEN UPTS.TagRankForUser = 1 THEN UPTS.TagName ELSE NULL END) AS TopTagByQuestions,
        MAX(CASE WHEN UPTS.TagRankForUser = 1 THEN UPTS.UserQuestionsWithTag ELSE NULL END) AS TopTagQuestionCount,
        (
            SELECT COUNT(DISTINCT PL_Inner.RelatedPostId)
            FROM PostLinks PL_Inner
            WHERE PL_Inner.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = UAS.UserId AND PostTypeId = 1)
        ) AS UserLinkedQuestionCount,
        NTILE(10) OVER (ORDER BY UAS.Reputation DESC) AS ReputationDecile,
        RANK() OVER (ORDER BY SUM(COALESCE(PEM.Score, 0)) DESC, UAS.Reputation DESC) AS OverallScoreRank,
        (
            SELECT CR.Name
            FROM QuestionClosingTrends QCT_corr
            LEFT JOIN CloseReasonTypes CR ON QCT_corr.MostRecentCloseReasonIdText ~ '^[0-9]+$' AND QCT_corr.MostRecentCloseReasonIdText::smallint = CR.Id
            WHERE QCT_corr.OwnerUserId = UAS.UserId
            AND QCT_corr.QuestionId = (
                SELECT PostId
                FROM PostEngagementMetrics
                WHERE OwnerUserId = UAS.UserId AND PostTypeId = 1
                ORDER BY Score DESC, ViewCount DESC
                LIMIT 1
            )
            ORDER BY QCT_corr.LastClosedDate DESC
            LIMIT 1
        ) AS TopQuestionCloseReason,
        (UAS.TotalUpVotesGiven * 1.0) / NULLIF(UAS.TotalDownVotesGiven, 0) AS UpToDownVoteRatioGiven,
        'HighAcceptedAnswersWithPositiveVoting' AS UserSegment
    FROM UserActivitySummary UAS
    LEFT JOIN PostEngagementMetrics PEM ON UAS.UserId = PEM.OwnerUserId AND PEM.PostTypeId = 1
    LEFT JOIN QuestionClosingTrends QCT ON UAS.UserId = QCT.OwnerUserId
    LEFT JOIN UserPostTagStats UPTS ON UAS.UserId = UPTS.UserId AND UPTS.TagRankForUser = 1
    WHERE UAS.TotalAnswers > 50 -- At least 50 answers
      AND UAS.TotalAcceptedAnswersByOthers > 5 -- At least 5 accepted answers
      AND (UAS.TotalUpVotesGiven * 1.0) / NULLIF(UAS.TotalDownVotesGiven, 0) > 3.0 -- Upvote ratio given > 3:1
    GROUP BY UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.TotalQuestions, UAS.TotalAnswers, UAS.TotalCommentsMade, UAS.AvgCommentLength, UAS.GoldBadges, UAS.SilverBadges, UAS.BronzeBadges, UAS.TotalAcceptedAnswersByOthers, UAS.TotalUpVotesGiven, UAS.TotalDownVotesGiven
)
SELECT * FROM MainQueryData
UNION ALL
SELECT * FROM SecondaryUserData
ORDER BY UserSegment, OverallScoreRank ASC
LIMIT 200;
