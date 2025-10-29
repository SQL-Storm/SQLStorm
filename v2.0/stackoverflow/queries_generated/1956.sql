-- {"query": "1956.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2317} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT PH.Id) AS TotalPostHistoryEntries,
        SUM(P.Score) AS TotalPostScoreGivenByUser,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentActivity,
        MIN(P.CreationDate) AS FirstPostCreation,
        MIN(C.CreationDate) AS FirstCommentCreation,
        COUNT(DISTINCT B_GOLD.Id) AS GoldBadgeCount,
        COUNT(DISTINCT B_SILVER.Id) AS SilverBadgeCount,
        COUNT(DISTINCT B_BRONZE.Id) AS BronzeBadgeCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN PostHistory PH ON U.Id = PH.UserId
    LEFT JOIN Badges B_GOLD ON U.Id = B_GOLD.UserId AND B_GOLD.Class = 1
    LEFT JOIN Badges B_SILVER ON U.Id = B_SILVER.UserId AND B_SILVER.Class = 2
    LEFT JOIN Badges B_BRONZE ON U.Id = B_BRONZE.UserId AND B_BRONZE.Class = 3
    GROUP BY U.Id
),
PostEditActivity AS (
    SELECT
        PH.PostId,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 7) THEN PH.Id END) AS TitleEditCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (5, 8) THEN PH.Id END) AS BodyEditCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (6, 9) THEN PH.Id END) AS TagEditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 11) THEN PH.CreationDate ELSE NULL END) AS LastCloseReopenDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 16 THEN PH.CreationDate ELSE NULL END) AS CommunityOwnedDateHistory,
        MIN(PH.CreationDate) AS FirstHistoryEntryDate,
        MAX(PH.CreationDate) AS LastHistoryEntryDate,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 AND PH.Comment IN ('101', '1') THEN 1 ELSE 0 END) AS DuplicateCloseVotes,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 AND PH.Comment IN ('102', '2') THEN 1 ELSE 0 END) AS OffTopicCloseVotes
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId BETWEEN 1 AND 100
    GROUP BY PH.PostId
),
QuestionAnswerChain AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        A.Id AS AnswerId,
        A.OwnerUserId AS AnswerOwnerId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate,
        Q.AcceptedAnswerId AS AcceptedAnswerId,
        ROW_NUMBER() OVER(PARTITION BY Q.Id ORDER BY A.CreationDate ASC) AS AnswerSequenceNum,
        RANK() OVER(PARTITION BY Q.Id ORDER BY A.Score DESC, A.CreationDate ASC) AS AnswerRankByScore,
        COUNT(C.Id) OVER(PARTITION BY A.Id) AS AnswerCommentCount
    FROM Posts Q
    INNER JOIN Posts A ON Q.Id = A.ParentId
    LEFT JOIN Comments C ON A.Id = C.PostId
    WHERE Q.PostTypeId = 1 AND A.PostTypeId = 2
),
RecentVoteActivity AS (
    SELECT
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVoteCount,
        MAX(V.CreationDate) AS LatestVoteDate
    FROM Votes V
    GROUP BY V.PostId
),
QuestionAnalysis AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        UE.TotalPosts,
        UE.TotalQuestions,
        UE.TotalAnswers,
        UE.TotalComments,
        UE.TotalPostHistoryEntries,
        COALESCE(UE.TotalPostScoreGivenByUser, 0) AS TotalPostScoreGivenByUser,
        COALESCE(UE.LastPostActivity, UE.LastCommentActivity, U.LastAccessDate) AS UserLastActivityDerived,
        (U.UpVotes - U.DownVotes) AS NetUserVotes,
        CAST(U.UpVotes AS NUMERIC) / NULLIF(U.DownVotes, 0) AS UpDownVoteRatio,
        UE.GoldBadgeCount,
        UE.SilverBadgeCount,
        UE.BronzeBadgeCount,

        P.Id AS PostId,
        PT.Name AS PostTypeName,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title AS PostTitle,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        LENGTH(P.Body) AS PostBodyLength,
        SUBSTRING(P.Body, 1, 50) || '...' AS PostBodyExcerpt,
        COALESCE(PEA.TitleEditCount, 0) AS TitleEditCount,
        COALESCE(PEA.BodyEditCount, 0) AS BodyEditCount,
        COALESCE(PEA.TagEditCount, 0) AS TagEditCount,
        COALESCE(PEA.LastCloseReopenDate, P.ClosedDate) AS EffectiveClosedDate,
        COALESCE(PEA.DuplicateCloseVotes, 0) AS DuplicateCloseVotes,
        COALESCE(PEA.OffTopicCloseVotes, 0) AS OffTopicCloseVotes,
        (CAST(COALESCE(PEA.BodyEditCount, 0) AS NUMERIC) + CAST(COALESCE(PEA.TitleEditCount, 0) AS NUMERIC) + CAST(COALESCE(PEA.TagEditCount, 0) AS NUMERIC)) AS TotalPostEdits,
        P.Score * (COALESCE(P.CommentCount, 0) + COALESCE(P.FavoriteCount, 0) * 1.5) AS EngagementScore,
        CAST(P.Score AS NUMERIC) / NULLIF(P.ViewCount, 0) AS ScorePerView,
        CASE
            WHEN P.CommunityOwnedDate IS NOT NULL OR PEA.CommunityOwnedDateHistory IS NOT NULL THEN 'Community'
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            ELSE 'Open'
        END AS PostStatusDerived,

        COALESCE(RVA.UpvoteCount, 0) AS PostUpvoteCount,
        COALESCE(RVA.DownvoteCount, 0) AS PostDownvoteCount,
        COALESCE(RVA.AcceptedVoteCount, 0) AS PostAcceptedVoteCount,
        (COALESCE(RVA.UpvoteCount, 0) - COALESCE(RVA.DownvoteCount, 0)) AS PostNetVotes,
        CAST(COALESCE(RVA.UpvoteCount, 0) AS NUMERIC) / NULLIF(COALESCE(RVA.DownvoteCount, 0), 0) AS PostUpDownVoteRatio,
        RVA.LatestVoteDate,

        (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 1) AS LinkedPostCount,
        (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3) AS DuplicateLinkCount,

        ROW_NUMBER() OVER (PARTITION BY U.Id ORDER BY P.CreationDate DESC) AS UserPostSeqNumDesc,
        RANK() OVER (ORDER BY P.Score DESC, P.ViewCount DESC, P.CreationDate DESC) AS GlobalPostRank,
        NTILE(10) OVER (ORDER BY P.Score DESC) AS ScoreDecile,
        LAG(P.CreationDate, 1, P.CreationDate) OVER (PARTITION BY U.Id ORDER BY P.CreationDate) AS PreviousPostCreationDate,
        LEAD(P.CreationDate, 1, P.CreationDate) OVER (PARTITION BY U.Id ORDER BY P.CreationDate) AS NextPostCreationDate,
        AVG(P.Score) OVER (PARTITION BY P.PostTypeId ORDER BY P.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS RollingAvgScoreForPostType,

        (SELECT AVG(LENGTH(Text)) FROM Comments WHERE PostId = P.Id) AS AverageCommentLength,

        (SELECT MAX(QAC.AnswerScore) FROM QuestionAnswerChain QAC WHERE QAC.QuestionId = P.Id AND QAC.AcceptedAnswerId = QAC.AnswerId) AS AcceptedAnswerScore,
        (SELECT U_ACC.DisplayName FROM QuestionAnswerChain QAC JOIN Users U_ACC ON QAC.AnswerOwnerId = U_ACC.Id WHERE QAC.QuestionId = P.Id AND QAC.AcceptedAnswerId = QAC.AnswerId) AS AcceptedAnswerOwnerDisplayName,

        P.AnswerCount AS QuestionAnswerCount,
        (SELECT COUNT