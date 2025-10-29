-- {"query": "1107.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2991} 
WITH
  UserQuestionCounts AS (
    SELECT OwnerUserId, COUNT(Id) AS NumQuestions, AVG(ViewCount) AS AvgQViewCount, SUM(FavoriteCount) AS TotalQFavorites
    FROM Posts WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL GROUP BY OwnerUserId
  ),
  UserAnswerCounts AS (
    SELECT OwnerUserId, COUNT(Id) AS NumAnswers FROM Posts WHERE PostTypeId = 2 AND OwnerUserId IS NOT NULL GROUP BY OwnerUserId
  ),
  UserCommentCounts AS (
    SELECT UserId, COUNT(Id) AS NumComments FROM Comments WHERE UserId IS NOT NULL GROUP BY UserId
  ),
  UserBadgeCounts AS (
    SELECT UserId,
           SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges GROUP BY UserId
  ),
  UserLastActivity AS (
    SELECT OwnerUserId, MAX(LastActivityDate) AS LastPostActivityDate
    FROM Posts WHERE OwnerUserId IS NOT NULL GROUP BY OwnerUserId
  ),
  UserOverallStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COALESCE(UQC.NumQuestions, 0) AS TotalQuestions,
        COALESCE(UAC.NumAnswers, 0) AS TotalAnswers,
        COALESCE(UCC.NumComments, 0) AS TotalCommentsMade,
        COALESCE(UBC.GoldBadges, 0) AS GoldBadges,
        COALESCE(UBC.SilverBadges, 0) AS SilverBadges,
        COALESCE(UBC.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(UQC.AvgQViewCount, 0.0) AS AvgQuestionViewCount,
        COALESCE(UQC.TotalQFavorites, 0) AS TotalQuestionFavorites,
        ULA.LastPostActivityDate
    FROM Users AS U
    LEFT JOIN UserQuestionCounts AS UQC ON U.Id = UQC.OwnerUserId
    LEFT JOIN UserAnswerCounts AS UAC ON U.Id = UAC.OwnerUserId
    LEFT JOIN UserCommentCounts AS UCC ON U.Id = UCC.UserId
    LEFT JOIN UserBadgeCounts AS UBC ON U.Id = UBC.UserId
    LEFT JOIN UserLastActivity AS ULA ON U.Id = ULA.OwnerUserId
  ),
  PostPerformanceMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        P.LastEditDate,
        P.LastActivityDate,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        COUNT(V_Up.Id) AS TotalUpVotesReceived,
        COUNT(V_Down.Id) AS TotalDownVotesReceived,
        COUNT(PH_Edit.Id) AS TotalEdits,
        COUNT(PH_Close.Id) AS TotalCloseEvents,
        COALESCE(SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN (SELECT AcceptedAns.Score FROM Posts AS AcceptedAns WHERE AcceptedAns.Id = P.AcceptedAnswerId) ELSE 0 END), 0) AS AcceptedAnswerScore,
        ROW_NUMBER() OVER(PARTITION BY P.OwnerUserId, P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC, P.CreationDate DESC) AS PostRankForUser
    FROM Posts AS P
    LEFT JOIN Votes AS V_Up ON P.Id = V_Up.PostId AND V_Up.VoteTypeId = 2 -- UpMod
    LEFT JOIN Votes AS V_Down ON P.Id = V_Down.PostId AND V_Down.VoteTypeId = 3 -- DownMod
    LEFT JOIN PostHistory AS PH_Edit ON P.Id = PH_Edit.PostId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 24) -- Edits, Rollbacks, Suggested Edits Applied
    LEFT JOIN PostHistory AS PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId IN (10, 11) -- Close, Reopen
    GROUP BY
        P.Id, P.PostTypeId, P.Title, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId, P.LastEditDate, P.LastActivityDate, P.AnswerCount, P.CommentCount, P.FavoriteCount
  ),
  QuestionAnswerAggregates AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        COALESCE(SUM(A.Score), 0) AS SumOfAnswerScores,
        COALESCE(AVG(A.Score), 0.0) AS AvgAnswerScore,
        COUNT(DISTINCT A.Id) AS CountOfAnswers,
        MAX(A.ViewCount) AS MaxAnswerViewCount
    FROM Posts AS Q
    JOIN Posts AS A ON Q.Id = A.ParentId
    WHERE Q.PostTypeId = 1 AND A.PostTypeId = 2
    GROUP BY Q.Id, Q.OwnerUserId
  ),
  UserTopTags AS (
    SELECT
        P.OwnerUserId AS UserId,
        Tag.TagName,
        COUNT(P.Id) AS UserTagPostCount,
        AVG(P.Score) AS UserTagAvgPostScore,
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY COUNT(P.Id) DESC, AVG(P.Score) DESC) AS TagRankForUser
    FROM Posts AS P
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS Tag(TagName)
    WHERE P.PostTypeId = 1 AND P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId, Tag.TagName
  ),
  ControversialPosts AS (
    SELECT
        PPM.PostId,
        PPM.Title,
        PPM.OwnerUserId,
        PPM.PostCreationDate,
        PPM.TotalUpVotesReceived,
        PPM.TotalDownVotesReceived,
        PPM.TotalEdits,
        PPM.Score,
        PPM.ViewCount,
        COALESCE(
            CAST(PPM.TotalDownVotesReceived AS NUMERIC) / NULLIF(PPM.TotalUpVotesReceived + PPM.TotalDownVotesReceived, 0),
            0.0
        ) AS DownvoteRatio,
        RANK() OVER (PARTITION BY PPM.PostTypeId ORDER BY PPM.TotalEdits DESC, PPM.ViewCount DESC) AS EditRank,
        ROW_NUMBER() OVER (ORDER BY (PPM.TotalDownVotesReceived * 2 - PPM.TotalUpVotesReceived) DESC, PPM.Score ASC) AS ControversyScoreRank
    FROM PostPerformanceMetrics AS PPM
    WHERE PPM.PostTypeId IN (1, 2) -- Questions or Answers
      AND (PPM.TotalUpVotesReceived + PPM.TotalDownVotesReceived) > 10 -- Only posts with significant voting
      AND PPM.TotalEdits > 2 -- Only posts with some edit history
  ),
  OldUnansweredQuestions AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.OwnerUserId
    FROM Posts AS P
    WHERE P.PostTypeId = 1
      AND P.AnswerCount = 0
      AND P.ClosedDate IS NULL
      AND P.CreationDate < (CURRENT_TIMESTAMP - INTERVAL '2 year')
      AND P.ViewCount > 50 -- At least some views
  ),
  NotablePosts AS (
    SELECT
        PostId, Title, OwnerUserId, 'Controversial' AS Category, ControversyScoreRank AS RankValue
    FROM ControversialPosts
    WHERE ControversyScoreRank <= 50
    UNION ALL
    SELECT
        PostId, Title, OwnerUserId, 'UnansweredOld' AS Category, NULL AS RankValue
    FROM OldUnansweredQuestions
  )
SELECT
    UOS.UserId,
    UOS.DisplayName,
    UOS.Reputation,
    UOS.TotalQuestions,
    UOS.TotalAnswers,
    UOS.TotalCommentsMade,
    UOS.GoldBadges,
    UOS.SilverBadges,
    UOS.BronzeBadges,
    UOS.AvgQuestionViewCount,
    UOS.TotalQuestionFavorites,
    PPM_Q.PostId AS TopQuestionId,
    PPM_Q.Title AS TopQuestionTitle,
    PPM_Q.Score AS TopQuestionScore,
    PPM_Q.ViewCount AS TopQuestionViewCount,
    PPM_Q.TotalEdits AS TopQuestionEdits,
    QAA.CountOfAnswers AS TopQuestionAnswerCount,
    QAA.AvgAnswerScore AS TopQuestionAvgAnswerScore,
    UTT.TagName AS UsersTopTagName,
    UTT.UserTagAvgPostScore AS UsersTopTagAvgScore,
    NP.Title AS NotablePostTitle,
    NP.Category AS NotablePostCategory,
    NP.RankValue AS NotablePostRank,
    CASE
        WHEN UOS.Reputation > 50000 AND UOS.TotalQuestions + UOS.TotalAnswers > 500 THEN 'Legendary Contributor'
        WHEN UOS.TotalQuestions > 100 AND UOS.TotalAnswers > 200 THEN 'Prodigious Contributor'
        WHEN UOS.TotalQuestions > 50 OR UOS.TotalAnswers > 100 THEN 'Active Contributor'
        WHEN UOS.TotalQuestions + UOS.TotalAnswers > 10 THEN 'Occasional Contributor'
        ELSE 'Novice/Lurker'
    END AS UserContributionLevel,
    -- Correlated subquery: Get the most recent comment text on a user's *own* negative-scored post
    (
        SELECT C_Corr.Text
        FROM Comments AS C_Corr
        WHERE C_Corr.PostId = PPM_Q.PostId
          AND C_Corr.UserId = UOS.UserId
          AND PPM_Q.Score < 0
        ORDER BY C_Corr.CreationDate DESC
        LIMIT 1
    ) AS LatestNegativeScoreCommentText,
    -- String expression and NULL logic: Cleaned User Location
    COALESCE(
        REPLACE(
            REPLACE(
                REPLACE(
                    UPPER(U.Location),
                    'USA', 'UNITED STATES'
                ),
                'US', 'UNITED STATES'
            ),
            'UK', 'UNITED KINGDOM'
        ),
        'Unknown Location'
    ) AS CleanedUserLocation,
    -- Complicated calculation: Ratio of days since last post activity to total days since user creation
    CASE
        WHEN UOS.LastPostActivityDate IS NOT NULL AND UOS.UserCreationDate IS NOT NULL
        THEN
            CAST(DATE_PART('day', CURRENT_TIMESTAMP - UOS.LastPostActivityDate) AS NUMERIC)
            / NULLIF(DATE_PART('day', CURRENT_TIMESTAMP - UOS.UserCreationDate), 0)
        ELSE NULL
    END AS ActivityToLifespanRatio,
    -- Window function example for overall user ranking
    RANK() OVER (ORDER BY UOS.Reputation DESC, (UOS.TotalQuestions + UOS.TotalAnswers) DESC, UOS.UserCreationDate ASC) AS OverallUserRank
FROM UserOverallStats AS UOS
JOIN Users AS U ON UOS.UserId = U.Id -- Join back to Users for Location and other details not aggregated
LEFT JOIN PostPerformanceMetrics AS PPM_Q ON UOS.UserId = PPM_Q.OwnerUserId AND PPM_Q.PostTypeId = 1 AND PPM_Q.PostRankForUser = 1
LEFT JOIN QuestionAnswerAggregates AS QAA ON PPM_Q.PostId = QAA.QuestionId
LEFT JOIN UserTopTags AS UTT ON UOS.UserId = UTT.UserId AND UTT.TagRankForUser = 1
LEFT JOIN NotablePosts AS NP ON UOS.UserId = NP.OwnerUserId
WHERE UOS.Reputation > 1000 -- Focus on more established users
  AND (PPM_Q.PostId IS NOT NULL OR UOS.TotalAnswers > 50) -- User has at least a top question or significant answers
  AND (NP.PostId IS NOT NULL OR UOS.TotalQuestions + UOS.TotalAnswers > 20) -- User associated with a notable post or significant overall contribution
ORDER BY
    OverallUserRank ASC, UOS.Reputation DESC
LIMIT 1000;