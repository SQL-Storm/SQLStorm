-- {"query": "1468.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2897} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        MAX(P.CreationDate) AS LastPostDate,
        COUNT(DISTINCT C.Id) AS TotalComments,
        (CAST(U.UpVotes AS NUMERIC) / NULLIF(U.DownVotes + U.UpVotes, 0)) AS UpDownVoteRatio,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) AS ReputationRank
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    WHERE U.Reputation > 1000
      AND U.CreationDate >= '2010-01-01'
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location, U.UpVotes, U.DownVotes
    HAVING COUNT(P.Id) > 5 OR COUNT(C.Id) > 10
),
PostDetailsRaw AS ( -- Using UNION ALL to combine different post types with specific filters/nulls
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><') AS TagArray,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId, P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS RankByUserPostType,
        LAG(P.LastEditDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.LastEditDate) AS PreviousEditDate,
        (SELECT MAX(C.CreationDate) FROM Comments C WHERE C.PostId = P.Id AND C.UserId IS NOT NULL) AS LatestCommentFromUser, -- Correlated subquery
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 5) AS BookmarkCount -- Correlated subquery
    FROM Posts P
    INNER JOIN PostTypes PT ON P.PostTypeId = PT.Id
    WHERE P.CreationDate BETWEEN '2018-01-01' AND '2023-12-31'
      AND P.Score > 0
      AND P.PostTypeId = 1 -- Questions
      AND P.Title IS NOT NULL
    UNION ALL
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score,
        NULL AS ViewCount, -- Answers don't have ViewCount
        NULL AS AnswerCount, -- Answers don't have AnswerCount
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        NULL AS TagArray, -- Answers don't have tags directly
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId, P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS RankByUserPostType,
        LAG(P.LastEditDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.LastEditDate) AS PreviousEditDate,
        (SELECT MAX(C.CreationDate) FROM Comments C WHERE C.PostId = P.Id AND C.UserId IS NOT NULL) AS LatestCommentFromUser,
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 5) AS BookmarkCount
    FROM Posts P
    INNER JOIN PostTypes PT ON P.PostTypeId = PT.Id
    WHERE P.CreationDate BETWEEN '2018-01-01' AND '2023-12-31'
      AND P.Score > 0
      AND P.PostTypeId = 2 -- Answers
      AND P.ParentId IS NOT NULL
),
PostDetails AS ( -- Further processing to handle NULLs from UNION ALL and add specific tag logic
    SELECT
        PostId,
        PostTypeId,
        PostTypeName,
        OwnerUserId,
        PostCreationDate,
        LastActivityDate,
        Score,
        COALESCE(ViewCount, 0) AS ViewCount, -- Handle NULL ViewCount for answers
        COALESCE(AnswerCount, 0) AS AnswerCount, -- Handle NULL AnswerCount for answers
        CommentCount,
        COALESCE(FavoriteCount, 0) AS FavoriteCount, -- Handle NULL FavoriteCount for answers
        ClosedDate,
        TagArray,
        RankByUserPostType,
        PreviousEditDate,
        LatestCommentFromUser,
        BookmarkCount,
        -- Complex string aggregation for tags, only for questions, using Tags table for global counts
        CASE WHEN PostTypeId = 1 AND TagArray IS NOT NULL THEN
            ARRAY_TO_STRING(
                (
                    SELECT ARRAY_AGG(CONCAT(T.tag, '(', COALESCE(TG.Count, 0), ')'))
                    FROM UNNEST(TagArray) AS T(tag)
                    LEFT JOIN Tags TG ON T.tag = TG.TagName
                    ORDER BY COALESCE(TG.Count, 0) DESC
                    LIMIT 3
                ), ', '
            )
        ELSE NULL END AS TopTagsWithCounts
    FROM PostDetailsRaw
),
PostHistoryAggregates AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS HistoryEntryCount,
        MAX(CASE WHEN PHT.Name LIKE '%Body%' THEN PH.CreationDate END) AS LastBodyEditDate,
        MAX(CASE WHEN PHT.Name LIKE '%Tags%' THEN PH.CreationDate END) AS LastTagEditDate,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 101) THEN 1 ELSE 0 END) AS CloseVoteCount, -- Close reasons (10 = Post Closed, 101 = Duplicate)
        SUM(CASE WHEN PH.PostHistoryTypeId IN (11, 20) THEN 1 ELSE 0 END) AS ReopenUnprotectCount,
        MAX(CASE WHEN PH.UserId IS NOT NULL THEN PH.CreationDate ELSE NULL END) AS LastUserHistoryDate,
        ARRAY_AGG(DISTINCT PHT.Name) FILTER (WHERE PHT.Name IS NOT NULL) AS DistinctHistoryTypes
    FROM PostHistory PH
    INNER JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    GROUP BY PH.PostId
),
LinkedPostsInfo AS (
    SELECT
        PL.PostId,
        COUNT(DISTINCT PL.RelatedPostId) AS TotalLinkedPosts,
        SUM(CASE WHEN LT.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinksCount,
        ARRAY_AGG(DISTINCT P2.Id) FILTER (WHERE LT.Name = 'Duplicate') AS DuplicatePostIds
    FROM PostLinks PL
    INNER JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
    LEFT JOIN Posts P2 ON PL.RelatedPostId = P2.Id
    GROUP BY PL.PostId
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.ReputationRank,
    UE.GoldBadges,
    UE.SilverBadges,
    UE.BronzeBadges,
    UE.UpDownVoteRatio,
    PD.PostId,
    PD.PostTypeName,
    PD.PostCreationDate,
    PD.Score AS PostScore,
    PD.ViewCount,
    PD.BookmarkCount,
    COALESCE(PD.LatestCommentFromUser, PD.LastActivityDate) AS EffectiveLastActivity, -- NULL logic, coalesce
    PD.TagArray,
    PD.RankByUserPostType,
    EXTRACT(EPOCH FROM (PD.LastActivityDate - PD.PreviousEditDate)) / 3600 AS TimeSincePrevEditHours, -- Date calculation
    COALESCE(PHA.HistoryEntryCount, 0) AS HistoryEntryCount,
    COALESCE(PHA.CloseVoteCount, 0) AS CloseVoteCount,
    COALESCE(PHA.ReopenUnprotectCount, 0) AS ReopenUnprotectCount,
    PHA.DistinctHistoryTypes,
    COALESCE(LPI.TotalLinkedPosts, 0) AS TotalLinkedPosts,
    COALESCE(LPI.DuplicateLinksCount, 0) AS DuplicateLinksCount,
    PD.TopTagsWithCounts,
    CASE
        WHEN PD.PostTypeId = 1 AND PD.ViewCount > 10000 AND PD.FavoriteCount > 100 AND COALESCE(PHA.CloseVoteCount, 0) = 0 THEN 'High-Impact Open Question'
        WHEN PD.ClosedDate IS NOT NULL AND COALESCE(LPI.DuplicateLinksCount, 0) > 0 THEN 'Closed Duplicate Post'
        WHEN PD.PostTypeId = 1 AND PD.AnswerCount = 0 AND PD.CommentCount > 5 AND PD.CreationDate < NOW() - INTERVAL '3 years' THEN 'Stale Unanswered Question'
        WHEN PD.PostTypeId = 2 AND PD.OwnerUserId IS NOT NULL AND UE.ReputationRank <= 100 AND PD.Score > 50 THEN 'Top User High-Score Answer'
        WHEN PD.PostTypeId = 2 AND PD.OwnerUserId IS NOT NULL AND PD.Score > 0 AND NOT EXISTS (SELECT 1 FROM Posts A WHERE A.ParentId = PD.PostId AND A.AcceptedAnswerId = PD.PostId) THEN 'Answer Not Accepted Yet'
        ELSE 'Other Post Status'
    END AS PostCategory,
    -- Correlated subquery for average score of previous posts by the same user and type
    (
        SELECT AVG(InnerP.Score)
        FROM Posts InnerP
        WHERE InnerP.OwnerUserId = UE.UserId
          AND InnerP.CreationDate < PD.PostCreationDate
          AND InnerP.PostTypeId = PD.PostTypeId
          AND InnerP.PostTypeId = 1 -- Only consider questions for this specific average
    ) AS AvgPrevPostQuestionScore,
    -- Correlated subquery using EXISTS for a specific comment condition
    EXISTS (
        SELECT 1
        FROM Comments C
        WHERE C.PostId = PD.PostId
          AND C.CreationDate > PD.LastActivityDate
          AND C.Text ILIKE '%bug report%'
    ) AS HasRecentBugReportComment
FROM UserEngagement UE
INNER JOIN PostDetails PD ON UE.UserId = PD.OwnerUserId
LEFT JOIN PostHistoryAggregates PHA ON PD.PostId = PHA.PostId
LEFT JOIN LinkedPostsInfo LPI ON PD.PostId = LPI.PostId
WHERE UE.LastAccessDate >= '2022-01-01'
  AND (PD.PostTypeName = 'Question' OR PD.PostTypeName = 'Answer')
  AND PD.Score > 0
  AND (PD.ClosedDate IS NULL OR PD.ClosedDate >= NOW() - INTERVAL '1 year')
  AND UE.GoldBadges > 0
  AND NOT EXISTS ( -- Correlated subquery with NOT EXISTS to filter out questions with highly downvoted recent answers
      SELECT 1
      FROM Posts SubA
      WHERE SubA.ParentId = PD.PostId
        AND SubA.PostTypeId = 2
        AND SubA.Score < -5
        AND SubA.CreationDate > NOW() - INTERVAL '6 months'
  )
ORDER BY UE.Reputation DESC, PD.Score DESC, PD.PostCreationDate DESC
LIMIT 1000;
