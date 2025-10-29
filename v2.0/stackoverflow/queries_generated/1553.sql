-- {"query": "1553.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3098} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT Q.Id) AS QuestionsAsked,
        COUNT(DISTINCT A.Id) AS AnswersGiven,
        COUNT(DISTINCT C.Id) AS CommentsMade,
        COALESCE(SUM(Q.Score), 0) + COALESCE(SUM(A.Score), 0) AS TotalPostScore,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / 86400 AS DaysSinceCreation,
        AVG(CASE WHEN Q.Id IS NOT NULL THEN Q.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
        MAX(PH_user.CreationDate) AS LastUserHistoryEventDate
    FROM
        Users U
    LEFT JOIN
        Posts Q ON U.Id = Q.OwnerUserId AND Q.PostTypeId = 1
    LEFT JOIN
        Posts A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        PostHistory PH_user ON U.Id = PH_user.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING
        COUNT(DISTINCT Q.Id) > 0 OR COUNT(DISTINCT A.Id) > 0
),
PostInteractionSummary AS (
    SELECT
        V.PostId,
        V.CreationDate,
        V.UserId,
        'Vote' AS InteractionType,
        V.VoteTypeId AS TypeId,
        V.BountyAmount AS Amount
    FROM
        Votes V
    WHERE
        V.VoteTypeId IN (2, 3, 5, 8, 9) -- UpMod, DownMod, Favorite, BountyStart, BountyClose
    UNION ALL
    SELECT
        C.PostId,
        C.CreationDate,
        C.UserId,
        'Comment' AS InteractionType,
        NULL AS TypeId,
        C.Score AS Amount
    FROM
        Comments C
    WHERE
        C.Score > 0 AND C.UserId IS NOT NULL
),
PostEvolutionMetrics AS (
    SELECT
        P.Id AS PostId,
        P.Title AS PostTitle,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.OwnerUserId,
        P.LastEditDate,
        P.ClosedDate,
        P.FavoriteCount,
        P.AnswerCount,
        ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'), 1) AS NumberOfTags,
        COUNT(DISTINCT PH.RevisionGUID) AS DistinctHistoryRevisions,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) AS LastEditHistoryDate,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVoteCount,
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostScoreRankByOwner,
        COALESCE(EXTRACT(EPOCH FROM (P.LastEditDate - P.CreationDate)) / 86400, 0) AS DaysUntilLastEdit,
        EXISTS (
            SELECT 1
            FROM PostHistory PH_sub
            WHERE PH_sub.PostId = P.Id AND PH_sub.PostHistoryTypeId = 8
        ) AS HasRollbackBody,
        (SELECT PH_latest.UserDisplayName
         FROM PostHistory PH_latest
         WHERE PH_latest.PostId = P.Id AND PH_latest.PostHistoryTypeId IN (5, 8)
         ORDER BY PH_latest.CreationDate DESC
         LIMIT 1
        ) AS LastBodyEditorDisplayName,
        COALESCE(UPPER(SUBSTRING(P.Title, 1, 1)), 'Z') AS FirstCharOfTitle,
        P.CommunityOwnedDate IS NOT NULL AS IsCommunityOwned,
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 5) AS TotalFavoritesCounted_legacy,
        SUM(CASE WHEN PIS.InteractionType = 'Vote' THEN 1 ELSE 0 END) AS TotalVotesOnPost,
        SUM(CASE WHEN PIS.InteractionType = 'Comment' THEN 1 ELSE 0 END) AS TotalCommentsOnPost,
        MAX(PIS.CreationDate) AS LastInteractionDate
    FROM
        Posts P
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN
        PostInteractionSummary PIS ON P.Id = PIS.PostId
    WHERE
        P.PostTypeId = 1 AND P.CreationDate >= '2020-01-01'
    GROUP BY
        P.Id, P.Title, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId, P.LastEditDate, P.ClosedDate, P.FavoriteCount, P.Tags, P.AnswerCount, P.CommunityOwnedDate
    HAVING
        COUNT(DISTINCT PH.RevisionGUID) > 1 OR P.FavoriteCount > 5 OR SUM(CASE WHEN PIS.InteractionType = 'Vote' THEN 1 ELSE 0 END) > 5
),
AnswerDetails AS (
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId AS AnswerOwnerId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate,
        EXISTS (
            SELECT 1
            FROM Posts Q_sub
            WHERE Q_sub.Id = A.ParentId AND Q_sub.AcceptedAnswerId = A.Id
        ) AS WasAccepted,
        RANK() OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC) AS AnswerScoreRankForQuestion,
        EXTRACT(EPOCH FROM (A.CreationDate - Q_parent.CreationDate)) / 3600 AS HoursAfterQuestionCreation,
        COALESCE(NULLIF(LENGTH(TRIM(A.Body)), 0), 1) AS AnswerBodyLength,
        (SELECT COUNT(C_sub.Id) FROM Comments C_sub WHERE C_sub.PostId = A.Id) AS CommentCountForAnswer,
        SUM(CASE WHEN PIS.InteractionType = 'Vote' THEN 1 ELSE 0 END) AS TotalVotesOnAnswer,
        SUM(CASE WHEN PIS.InteractionType = 'Comment' THEN 1 ELSE 0 END) AS TotalCommentsOnAnswer
    FROM
        Posts A
    INNER JOIN
        Posts Q_parent ON A.ParentId = Q_parent.Id
    LEFT JOIN
        PostInteractionSummary PIS ON A.Id = PIS.PostId
    WHERE
        A.PostTypeId = 2 AND A.CreationDate >= '2020-01-01'
    AND (Q_parent.AcceptedAnswerId = A.Id OR A.Score >= 5)
    GROUP BY
        A.Id, A.ParentId, A.OwnerUserId, A.Score, A.CreationDate, Q_parent.CreationDate
),
BadgeEarnersWithReputation AS (
    SELECT
        B.UserId,
        U.DisplayName AS BadgeUserDisplayName,
        U.Reputation AS BadgeUserReputation,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate
    FROM
        Badges B
    INNER JOIN
        Users U ON B.UserId = U.Id
    GROUP BY
        B.UserId, U.DisplayName, U.Reputation
    HAVING
        COUNT(B.Id) > 3 AND SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) >= 1
)
SELECT
    UAS.UserId,
    UAS.UserDisplayName,
    UAS.Reputation,
    UAS.QuestionsAsked,
    UAS.AnswersGiven,
    UAS.TotalPostScore,
    PEM.PostId AS QuestionId,
    PEM.PostTitle,
    PEM.PostScore AS QuestionScore,
    PEM.ViewCount AS QuestionViewCount,
    PEM.NumberOfTags,
    PEM.DistinctHistoryRevisions,
    PEM.CloseVoteCount,
    PEM.DaysUntilLastEdit,
    PEM.HasRollbackBody,
    PEM.LastBodyEditorDisplayName,
    PEM.FirstCharOfTitle,
    PEM.IsCommunityOwned,
    PEM.TotalFavoritesCounted_legacy,
    PEM.TotalVotesOnPost AS QuestionTotalVotes,
    PEM.TotalCommentsOnPost AS QuestionTotalComments,
    PEM.LastInteractionDate AS QuestionLastInteractionDate,
    AD.AnswerId AS TopAnswerId,
    AD.AnswerOwnerId AS TopAnswerOwnerId,
    AD.AnswerScore AS TopAnswerScore,
    AD.HoursAfterQuestionCreation AS TopAnswerHoursAfterQuestion,
    AD.WasAccepted AS TopAnswerWasAccepted,
    AD.AnswerScoreRankForQuestion AS TopAnswerRank,
    AD.CommentCountForAnswer,
    AD.TotalVotesOnAnswer,
    AD.TotalCommentsOnAnswer,
    BWER.TotalBadges,
    BWER.GoldBadges,
    BWER.LastBadgeDate,
    CASE
        WHEN UAS.QuestionsAsked > 0 AND UAS.AnswersGiven > 0 AND PEM.PostScoreRankByOwner = 1 THEN 'Prodigious Contributor & Top Question'
        WHEN PEM.CloseVoteCount > 0 AND PEM.DistinctHistoryRevisions > 5 THEN 'Highly Debated & Evolving Question'
        WHEN AD.WasAccepted AND AD.AnswerScore > PEM.PostScore THEN 'Superlative Accepted Answer'
        WHEN BWER.GoldBadges >= 1 AND BWER.TotalBadges > 10 THEN 'Elite Badge Earner'
        ELSE 'General Activity'
    END AS UserEngagementSegment,
    CAST(COALESCE(AD.AnswerScore, 0) AS NUMERIC) / NULLIF(UAS.AvgQuestionViewCount, 0) AS TopAnswerScorePerAvgQuestionViewRatio,
    LOWER(COALESCE(UAS.Location, 'Unknown Location')) AS UserLocationNormalized,
    (
        SELECT COUNT(DISTINCT PL_dup.RelatedPostId)
        FROM PostLinks PL_dup
        WHERE PL_dup.PostId = PEM.PostId AND PL_dup.LinkTypeId = 3
    ) AS DuplicateLinkCount,
    (
        SELECT MAX(V.CreationDate)
        FROM Votes V
        WHERE V.PostId = PEM.PostId AND V.VoteTypeId = 2 -- Latest Upvote
    ) AS LatestUpvoteDate,
    AVG(PEM.PostScore) OVER (PARTITION BY (UAS.Reputation / 10000), PEM.FirstCharOfTitle) AS AvgPostScoreForReputationAndTitleBand,
    (COALESCE(PEM.ClosedDate, PEM.LastEditDate) IS NOT NULL AND PEM.CloseVoteCount > 0)
    AND (AD.AnswerScore IS NULL OR AD.AnswerScore < 100)
    AND (UAS.Reputation > 50000 OR BWER.GoldBadges >= 2)
    AND (
        PEM.FirstCharOfTitle NOT IN ('A', 'E', 'I', 'O', 'U') OR
        SUBSTRING(PEM.PostTitle, LENGTH(PEM.PostTitle) - 2, 3) LIKE '%?'
    ) AS IsComplexFilteredPost
FROM
    UserActivitySummary UAS
LEFT JOIN
    PostEvolutionMetrics PEM ON UAS.UserId = PEM.OwnerUserId
LEFT JOIN
    AnswerDetails AD ON PEM.PostId = AD.QuestionId AND AD.AnswerScoreRankForQuestion = 1
LEFT JOIN
    BadgeEarnersWithReputation BWER ON UAS.UserId = BWER.UserId
WHERE
    UAS.Reputation >= 10000
    AND UAS.QuestionsAsked >= 2
    AND UAS.AnswersGiven >= 5
    AND PEM.PostId IS NOT NULL
    AND PEM.PostScore >= 10
    AND (
        (PEM.LastEditDate IS NOT NULL AND PEM.LastEditDate > UAS.LastAccessDate) OR
        (PEM.FavoriteCount > 10 AND PEM.IsCommunityOwned) OR
        (PEM.HasRollbackBody AND PEM.DistinctHistoryRevisions > 2)
    )
ORDER BY
    UAS.Reputation DESC, PEM.PostScore DESC, AD.AnswerScore DESC, BWER.GoldBadges DESC
LIMIT 1000;
