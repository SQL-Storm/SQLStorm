-- {"query": "1211.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3027} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT P.Id) AS PostsCreated,
        COUNT(DISTINCT C.Id) AS CommentsMade,
        COUNT(DISTINCT B.Id) AS BadgesEarned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COALESCE(U.Reputation, 0) * 0.5 + COALESCE(U.Views, 0) * 0.05 + COALESCE(U.UpVotes, 0) * 0.3 - COALESCE(U.DownVotes, 0) * 0.1 AS UserImpactScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.ViewCount,
        P.Score AS InitialScore,
        P.AnswerCount,
        P.FavoriteCount,
        P.ClosedDate,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN V.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) AS TotalDirectVotes,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 24) THEN 1 ELSE 0 END) AS EditCount, -- Edit Title, Body, Tags, Suggested Edit Applied
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 11, 19, 20) THEN 1 ELSE 0 END) AS LifecycleEvents, -- Closed, Reopened, Protected, Unprotected
        COUNT(DISTINCT Cmt.Id) AS CommentCountOnPost,
        LENGTH(P.Body) AS BodyLength,
        LENGTH(COALESCE(P.Title, '')) AS TitleLength,
        P.Tags
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Comments Cmt ON P.Id = Cmt.PostId
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.Title, P.CreationDate, P.ViewCount, P.Score, P.AnswerCount, P.FavoriteCount, P.ClosedDate, P.Body, P.Tags
),
RankedPostPerformance AS (
    SELECT
        PEM.PostId,
        PEM.OwnerUserId,
        PEM.PostTypeId,
        PEM.Title,
        PEM.PostCreationDate,
        PEM.UpVoteCount,
        PEM.DownVoteCount,
        PEM.TotalDirectVotes,
        PEM.EditCount,
        PEM.LifecycleEvents,
        PEM.CommentCountOnPost,
        PEM.AnswerCount,
        PEM.ViewCount,
        PEM.FavoriteCount,
        PEM.ClosedDate,
        (PEM.UpVoteCount - PEM.DownVoteCount) AS NetVoteScore,
        CAST(PEM.UpVoteCount AS DECIMAL) / NULLIF(PEM.DownVoteCount, 0) AS UpDownRatio,
        ROW_NUMBER() OVER (PARTITION BY PEM.OwnerUserId, PEM.PostTypeId ORDER BY (PEM.UpVoteCount - PEM.DownVoteCount) DESC, PEM.ViewCount DESC) AS Rn_OwnerPostRank,
        AVG(PEM.UpVoteCount - PEM.DownVoteCount) OVER (PARTITION BY PEM.PostTypeId, EXTRACT(YEAR FROM PEM.PostCreationDate)) AS AvgNetScoreByPostTypeYear,
        NTILE(4) OVER (ORDER BY (PEM.UpVoteCount - PEM.DownVoteCount) DESC) AS NetScoreQuartile,
        LAG(PEM.PostCreationDate, 1, '1970-01-01'::timestamp) OVER (PARTITION BY PEM.OwnerUserId ORDER BY PEM.PostCreationDate) AS PreviousPostDate
    FROM PostEngagementMetrics PEM
    WHERE PEM.OwnerUserId IS NOT NULL
),
ControversialPostCandidates AS (
    SELECT
        RPP.PostId,
        RPP.OwnerUserId,
        RPP.Title,
        RPP.PostCreationDate,
        RPP.UpVoteCount,
        RPP.DownVoteCount,
        RPP.NetVoteScore,
        RPP.UpDownRatio,
        RPP.EditCount,
        RPP.LifecycleEvents,
        RPP.CommentCountOnPost,
        RPP.AnswerCount,
        RPP.ViewCount,
        RPP.FavoriteCount,
        RPP.ClosedDate,
        COALESCE(
            CASE
                WHEN RPP.NetVoteScore < -5 AND RPP.TotalDirectVotes > 10 THEN 'HighlyNegativeScore'
                WHEN RPP.UpDownRatio IS NOT NULL AND RPP.UpDownRatio < 0.25 AND RPP.DownVoteCount > 3 THEN 'LowUpDownRatio'
                WHEN RPP.LifecycleEvents >= 2 THEN 'MultipleLifecycleEvents'
                WHEN RPP.EditCount > 7 AND RPP.ViewCount > 5000 THEN 'HeavilyEditedPopular'
                WHEN RPP.PostTypeId = 1 AND RPP.AnswerCount IS NOT NULL AND RPP.AnswerCount = 0 AND RPP.ViewCount > 100 THEN 'UnansweredPopularQuestion'
                ELSE NULL
            END, 'NotControversial'
        ) AS ControversyType,
        (SELECT COUNT(DISTINCT PL.RelatedPostId) FROM PostLinks PL WHERE PL.PostId = RPP.PostId AND PL.LinkTypeId = 3) AS DuplicateLinkCount,
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = RPP.PostId AND C.Text LIKE '%clarity needed%' OR C.Text LIKE '%too broad%') AS ClarityCommentsCount
    FROM RankedPostPerformance RPP
    WHERE RPP.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
PostTagAnalysis AS (
    SELECT
        CPC.PostId,
        CPC.OwnerUserId,
        CPC.Title,
        CPC.PostCreationDate,
        CPC.ControversyType,
        LOWER(TRIM(unnest_tag.tag_name)) AS TagName, -- Using unnest for tag array parsing
        SUM(CASE WHEN PH.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEditHistories,
        SUM(CASE WHEN PH.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagsEditHistories,
        MAX(PH.CreationDate) AS LastHistoryActivityDate,
        EXISTS (
            SELECT 1
            FROM PostHistory PH_inner
            WHERE PH_inner.PostId = CPC.PostId
              AND PH_inner.Comment IS NOT NULL
              AND PH_inner.Comment ~* '(duplicate|off-topic|subjective|opinion)' -- Regex for various keywords
        ) AS HasFlaggedHistoryComment
    FROM ControversialPostCandidates CPC
    JOIN Posts P ON CPC.PostId = P.Id
    LEFT JOIN PostHistory PH ON CPC.PostId = PH.PostId
    -- Assuming a function like string_to_array to split tags string
    LEFT JOIN LATERAL (SELECT trim(substring(elem, 2, length(elem)-2)) AS tag_name FROM unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) elem) AS unnest_tag ON P.Tags IS NOT NULL
    GROUP BY CPC.PostId, CPC.OwnerUserId, CPC.Title, CPC.PostCreationDate, CPC.ControversyType, unnest_tag.tag_name
),
FinalUserPostInsights AS (
    SELECT
        UAS.DisplayName AS OwnerDisplayName,
        UAS.Reputation AS OwnerReputation,
        UAS.UserImpactScore,
        PTA.PostId,
        PTA.Title AS PostTitle,
        PTA.PostCreationDate,
        PTA.TagName,
        PTA.ControversyType,
        RPP.PostTypeId,
        RPP.NetVoteScore,
        RPP.UpVoteCount,
        RPP.DownVoteCount,
        RPP.ViewCount,
        RPP.AnswerCount,
        RPP.CommentCountOnPost,
        RPP.EditCount AS TotalPostEdits,
        RPP.LifecycleEvents AS TotalPostLifecycleEvents,
        RPP.FavoriteCount,
        RPP.ClosedDate,
        PTA.BodyEditHistories,
        PTA.TagsEditHistories,
        PTA.LastHistoryActivityDate,
        PTA.HasFlaggedHistoryComment,
        CPC.DuplicateLinkCount,
        CPC.ClarityCommentsCount,
        RPP.Rn_OwnerPostRank,
        RPP.AvgNetScoreByPostTypeYear,
        RPP.NetScoreQuartile,
        RPP.PreviousPostDate,
        COALESCE(RPP.UpDownRatio, 0.0) AS ActualUpDownRatio,
        CASE
            WHEN RPP.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN RPP.PostTypeId = 1 AND (RPP.AnswerCount IS NULL OR RPP.AnswerCount = 0) THEN 'Unanswered'
            WHEN RPP.NetVoteScore <= -10 THEN 'VeryPoorlyReceived'
            ELSE 'ModeratelyEngaging'
        END AS PostEngagementCategory,
        (
            SELECT A.Id
            FROM Posts A
            WHERE A.ParentId = PTA.PostId AND A.PostTypeId = 2
            ORDER BY A.Score DESC, A.CreationDate ASC
            LIMIT 1
        ) AS TopAnswerId,
        (
            SELECT U_ans.DisplayName
            FROM Posts A
            JOIN Users U_ans ON A.OwnerUserId = U_ans.Id
            WHERE A.ParentId = PTA.PostId AND A.PostTypeId = 2
            ORDER BY A.Score DESC, A.CreationDate ASC
            LIMIT 1
        ) AS TopAnswerOwnerDisplayName
    FROM PostTagAnalysis PTA
    INNER JOIN UserActivitySummary UAS ON PTA.OwnerUserId = UAS.UserId
    INNER JOIN RankedPostPerformance RPP ON PTA.PostId = RPP.PostId
    INNER JOIN ControversialPostCandidates CPC ON PTA.PostId = CPC.PostId
    WHERE UAS.Reputation > 5000
      AND PTA.ControversyType != 'NotControversial'
      AND PTA.PostCreationDate BETWEEN '2021-01-01' AND '2023-12-31'
      AND RPP.NetScoreQuartile IN (1, 4) -- Top or bottom 25% by net score
)
SELECT
    FPI.OwnerDisplayName,
    FPI.OwnerReputation,
    FPI.UserImpactScore,
    FPI.PostTitle,
    FPI.PostCreationDate,
    FPI.TagName,
    FPI.ControversyType,
    FPI.PostTypeId,
    FPI.NetVoteScore,
    FPI.UpVoteCount,
    FPI.DownVoteCount,
    FPI.ViewCount,
    FPI.AnswerCount,
    FPI.CommentCountOnPost,
    FPI.TotalPostEdits,
    FPI.TotalPostLifecycleEvents,
    FPI.FavoriteCount,
    FPI.ClosedDate,
    FPI.BodyEditHistories,
    FPI.TagsEditHistories,
    FPI.LastHistoryActivityDate,
    FPI.HasFlaggedHistoryComment,
    FPI.DuplicateLinkCount,
    FPI.ClarityCommentsCount,
    FPI.Rn_OwnerPostRank,
    FPI.AvgNetScoreByPostTypeYear,
    FPI.NetScoreQuartile,
    FPI.PreviousPostDate,
    FPI.ActualUpDownRatio,
    FPI.PostEngagementCategory,
    FPI.TopAnswerId,
    FPI.TopAnswerOwnerDisplayName
FROM FinalUserPostInsights FPI
WHERE FPI.CommentCountOnPost > 0
ORDER BY FPI.UserImpactScore DESC, FPI.PostCreationDate DESC, FPI.NetVoteScore ASC
LIMIT 1000;
