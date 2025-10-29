-- {"query": "1580.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3051} 

WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous User') AS DisplayName,
        U.Reputation,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        U.CreationDate,
        DATE_PART('year', AGE(CURRENT_TIMESTAMP, U.CreationDate)) AS YearsActive,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        SUM(COALESCE(P.Score, 0)) AS TotalPostsScore,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentsScore,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END) AS AvgQuestionScore,
        (CAST(U.UpVotes AS NUMERIC) - U.DownVotes) AS NetVotesGiven,
        (CAST(U.Reputation AS NUMERIC) / (NULLIF(DATE_PART('year', AGE(CURRENT_TIMESTAMP, U.CreationDate)), 0) + 1)) AS ReputationPerYear
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate
    HAVING COUNT(DISTINCT P.Id) > 10
    AND SUM(COALESCE(P.Score, 0)) > 200
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.ParentId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.Title,
        P.Tags,
        P.LastEditDate,
        P.ClosedDate,
        P.AcceptedAnswerId,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS EditCount_Content,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 2) AS UpvoteCount,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 3) AS DownvoteCount,
        COUNT(DISTINCT PL.Id) FILTER (WHERE PL.LinkTypeId = 1) AS LinkedPostCount,
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><'), 1) AS TagCount,
        RANK() OVER (PARTITION BY P.PostTypeId, P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC) AS RankByUserPostType,
        DENSE_RANK() OVER (ORDER BY P.Score DESC, P.CreationDate DESC) AS GlobalScoreRank
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN Votes AS V ON P.Id = V.PostId
    LEFT JOIN PostLinks AS PL ON P.Id = PL.PostId
    WHERE P.PostTypeId IN (1, 2)
      AND P.CreationDate BETWEEN '2018-01-01' AND '2023-12-31'
      AND P.Score IS NOT NULL AND P.Score > 0
      AND P.ViewCount IS NOT NULL AND P.ViewCount > 0
    GROUP BY P.Id, P.OwnerUserId, P.PostTypeId, P.ParentId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount,
             P.Title, P.Tags, P.LastEditDate, P.ClosedDate, P.AcceptedAnswerId
),
RecentCollaborativeHistory AS (
    SELECT
        PH.PostId,
        PH.UserId AS EventUserId,
        PH.CreationDate AS EventDate,
        PH.PostHistoryTypeId,
        PH.Comment,
        LEAD(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS NextEventDate,
        LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PrevEventDate,
        LEAD(PH.UserId) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS NextEventUserId,
        LAG(PH.UserId) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PrevEventUserId
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 10, 11)
      AND PH.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '180 days'
),
QualifiedPosts AS (
    SELECT
        PEM.PostId,
        PEM.OwnerUserId,
        PEM.PostTypeId,
        PEM.ParentId,
        PEM.CreationDate,
        PEM.Score,
        PEM.ViewCount,
        PEM.Title,
        PEM.Tags,
        PEM.RankByUserPostType,
        PEM.TagCount,
        PEM.EditCount_Content,
        PEM.UpvoteCount,
        PEM.DownvoteCount,
        PEM.LinkedPostCount,
        PEM.ClosedDate,
        COUNT(RCH.PostId) FILTER (WHERE RCH.PostHistoryTypeId = 10 AND RCH.EventUserId IS NOT NULL AND RCH.EventUserId <> PEM.OwnerUserId) AS ExternalCloseEvents,
        COUNT(RCH.PostId) FILTER (WHERE RCH.PostHistoryTypeId = 11 AND RCH.EventUserId IS NOT NULL AND RCH.EventUserId <> PEM.OwnerUserId) AS ExternalReopenEvents,
        CASE WHEN PEM.PostTypeId = 2 AND PEM.PostId = Q_Parent.AcceptedAnswerId AND PEM.OwnerUserId = Q_Parent.OwnerUserId THEN TRUE ELSE FALSE END AS OwnerAcceptedOwnAnswer,
        EXISTS (
            SELECT 1
            FROM Comments AS C_sub
            WHERE C_sub.PostId = PEM.PostId
              AND C_sub.UserId IS NOT NULL
              AND C_sub.UserId <> PEM.OwnerUserId
              AND C_sub.CreationDate BETWEEN PEM.CreationDate AND PEM.CreationDate + INTERVAL '24 hours'
            LIMIT 1
        ) AS HasEarlyExternalComments
    FROM PostEngagementMetrics AS PEM
    LEFT JOIN RecentCollaborativeHistory AS RCH ON PEM.PostId = RCH.PostId
    LEFT JOIN Posts AS Q_Parent ON PEM.ParentId = Q_Parent.Id AND PEM.PostTypeId = 2
    WHERE PEM.RankByUserPostType <= 5
      AND (PEM.Score >= 100 OR PEM.ViewCount >= 5000)
    GROUP BY PEM.PostId, PEM.OwnerUserId, PEM.PostTypeId, PEM.ParentId, PEM.CreationDate, PEM.Score, PEM.ViewCount,
             PEM.Title, PEM.Tags, PEM.RankByUserPostType, PEM.TagCount, PEM.EditCount_Content, PEM.UpvoteCount,
             PEM.DownvoteCount, PEM.LinkedPostCount, PEM.ClosedDate, Q_Parent.AcceptedAnswerId, Q_Parent.OwnerUserId
),
HighlyInteractingUsers AS (
    SELECT
        UES.UserId,
        UES.DisplayName,
        UES.Reputation,
        UES.YearsActive,
        UES.TotalPostsOwned,
        UES.TotalPostsScore,
        UES.ReputationPerYear,
        MAX(CASE WHEN B.Class = 1 THEN B.Name ELSE NULL END) AS TopGoldBadge,
        MAX(CASE WHEN B.Class = 2 THEN B.Name ELSE NULL END) AS TopSilverBadge,
        COUNT(DISTINCT B.Id) AS UniqueBadgesCount
    FROM UserEngagementSummary AS UES
    LEFT JOIN Badges AS B ON UES.UserId = B.UserId
    WHERE UES.Reputation > 5000
      AND UES.TotalPostsOwned > 20
    GROUP BY UES.UserId, UES.DisplayName, UES.Reputation, UES.YearsActive, UES.TotalPostsOwned, UES.TotalPostsScore, UES.ReputationPerYear
    HAVING COUNT(DISTINCT B.Id) >= 5
),
ComplexQuestionSelection AS (
    SELECT
        HIU.UserId,
        HIU.DisplayName,
        HIU.Reputation,
        HIU.ReputationPerYear,
        HIU.TopGoldBadge,
        'Question' AS PostCategory,
        QP.PostId,
        QP.Title,
        QP.CreationDate,
        QP.Score,
        QP.ViewCount,
        QP.Tags,
        QP.TagCount,
        QP.UpvoteCount,
        QP.DownvoteCount,
        QP.EditCount_Content,
        QP.LinkedPostCount,
        QP.ClosedDate,
        QP.ExternalCloseEvents,
        QP.ExternalReopenEvents,
        QP.HasEarlyExternalComments,
        (CAST(QP.Score AS NUMERIC) / NULLIF(QP.ViewCount, 0)) AS ScoreToViewRatio,
        NULL::INT AS ParentPostId,
        NULL::BOOLEAN AS OwnerAcceptedSelfAnswer,
        EXISTS (
            SELECT 1
            FROM PostEngagementMetrics AS PEM_other_q
            WHERE PEM_other_q.OwnerUserId = QP.OwnerUserId
              AND PEM_other_q.PostId <> QP.PostId
              AND PEM_other_q.PostTypeId = 1
              AND PEM_other_q.Score >= 200
              AND PEM_other_q.Tags IS NOT NULL
              AND QP.Tags IS NOT NULL
              AND EXISTS (
                  SELECT 1
                  FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(QP.Tags FROM 2 FOR LENGTH(QP.Tags)-2), '><')) AS tag1
                  INNER JOIN UNNEST(STRING_TO_ARRAY(SUBSTRING(PEM_other_q.Tags FROM 2 FOR LENGTH(PEM_other_q.Tags)-2), '><')) AS tag2 ON tag1 = tag2
                  LIMIT 1
              )
            LIMIT 1
        ) AS HasHighlyScoredSiblingTagCorrelation,
        AVG(QP_Other.Score) FILTER (WHERE DATE_PART('year', QP_Other.CreationDate) = DATE_PART('year', QP.CreationDate) AND QP_Other.PostId <> QP.PostId AND QP_Other.PostTypeId = 1) OVER (PARTITION BY HIU.UserId) AS AvgPeerQuestionScoreInYear
    FROM HighlyInteractingUsers AS HIU
    INNER JOIN QualifiedPosts AS QP ON HIU.UserId = QP.OwnerUserId
    LEFT JOIN PostEngagementMetrics AS QP_Other ON HIU.UserId = QP_Other.OwnerUserId AND QP_Other.PostTypeId = 1
    WHERE QP.PostTypeId = 1
      AND QP.TagCount >= 3
      AND QP.UpvoteCount >= 50
      AND (QP.ClosedDate IS NULL OR QP.ExternalReopenEvents > 0)
      AND QP.HasEarlyExternalComments IS TRUE
),
InfluentialAnswerSelection AS (
    SELECT
        HIU.UserId,
        HIU.DisplayName,
        HIU.Reputation,
        HIU.ReputationPerYear,
        HIU.TopGoldBadge,
        'Answer' AS PostCategory,
        QP_Ans.PostId,
        QP_Ans.Title,
        QP_Ans.CreationDate,
        QP_Ans.Score,
        QP_Ans.ViewCount,
        Q_Parent.Tags AS Tags,
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(Q_Parent.Tags FROM 2 FOR LENGTH(Q_Parent.Tags)-2), '><'), 1) AS TagCount,
        QP_Ans.UpvoteCount,
        QP_Ans.DownvoteCount,
        QP_Ans.EditCount_Content,
        QP_Ans.LinkedPostCount,
        NULL::TIMESTAMP AS ClosedDate,
        NULL::BIGINT AS ExternalCloseEvents,
        NULL::BIGINT AS ExternalReopenEvents,
        QP_Ans.HasEarlyExternalComments,
        (CAST(QP_Ans.Score AS NUMERIC) / NULLIF(Q_Parent.ViewCount, 0)) AS ScoreToParentViewRatio,
        QP_Ans.ParentId AS ParentPostId,
        QP_Ans.OwnerAcceptedOwnAnswer AS OwnerAcceptedSelfAnswer,
        NULL::BOOLEAN AS HasHighlyScoredSiblingTagCorrelation,
        MAX(QP_Ans_Other.Score) FILTER (WHERE QP_Ans_Other.PostId <> QP_Ans.PostId AND QP_Ans_Other.PostTypeId = 2) OVER (PARTITION BY HIU.UserId) AS MaxOtherAnswerScore
    FROM