-- {"query": "1244.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2718} 
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MIN(B.Date) AS FirstBadgeDate,
        MAX(B.Date) AS LastBadgeDate,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersGiven,
        SUM(P.Score) AS TotalPostScore,
        AVG(CASE WHEN P.PostTypeId IN (1, 2) THEN P.Score END) AS AvgPostScore,
        COUNT(DISTINCT Tag.T) AS UniqueTagsUsedInPosts,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentActivity
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')) AS Tag(T) ON P.Tags IS NOT NULL AND P.PostTypeId = 1
    WHERE U.CreationDate >= '2020-01-01' -- Focus on more recent users
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT B.Id) > 5 -- Only users with a fair number of badges
),
HighImpactQuestions AS (
    SELECT
        P.Id AS PostId,
        P.Title AS QuestionTitle,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><') AS TagArray,
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            ELSE 'Open'
        END AS PostStatus,
        DENSE_RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC) AS RankByUserScore,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 11) THEN 1 ELSE 0 END) OVER (PARTITION BY P.Id) AS CloseReopenEvents,
        COALESCE(SUM(CASE WHEN C.Text ILIKE '%bug%' OR C.Text ILIKE '%error%' THEN 1 ELSE 0 END), 0) AS BugCommentCount
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN Comments AS C ON P.Id = C.PostId
    WHERE P.PostTypeId = 1 -- Only questions
      AND P.CreationDate BETWEEN '2021-01-01' AND '2023-12-31'
      AND (P.ViewCount > 500 OR P.FavoriteCount > 10) -- High engagement threshold
    GROUP BY P.Id, P.Title, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.AcceptedAnswerId, P.Tags, P.ClosedDate, P.CommunityOwnedDate
),
DuplicatePostAnalysis AS (
    SELECT
        PL.PostId AS OriginalPostId,
        PL.RelatedPostId AS DuplicatePostId,
        P_Original.OwnerUserId AS OriginalOwnerUserId,
        P_Duplicate.OwnerUserId AS DuplicateOwnerUserId,
        P_Original.CreationDate AS OriginalCreationDate,
        P_Duplicate.CreationDate AS DuplicateCreationDate,
        PH_Close.CreationDate AS CloseDate,
        COALESCE(CR.Name, 'Unknown') AS CloseReasonName
    FROM PostLinks AS PL
    JOIN Posts AS P_Original ON PL.PostId = P_Original.Id
    JOIN Posts AS P_Duplicate ON PL.RelatedPostId = P_Duplicate.Id
    LEFT JOIN PostHistory AS PH_Close
        ON P_Original.Id = PH_Close.PostId
       AND PH_Close.PostHistoryTypeId = 10 -- Post Closed event
       AND PH_Close.Comment IS NOT NULL
       AND PH_Close.Comment ~ '^[0-9]+$' -- Ensure comment is numeric before casting
    LEFT JOIN CloseReasonTypes AS CR
        ON CAST(PH_Close.Comment AS SMALLINT) = CR.Id
    WHERE PL.LinkTypeId = 3 -- Duplicate link type
      AND P_Original.CreationDate >= '2022-01-01' -- Recent duplicates
),
HighReputationOrHighEngagementUsers AS (
    -- Users with very high reputation
    SELECT U.Id AS UserId
    FROM Users AS U
    WHERE U.Reputation > 50000
    UNION ALL
    -- Users with many gold badges who also posted 'performance' related questions
    SELECT UE.UserId
    FROM UserEngagement AS UE
    JOIN HighImpactQuestions AS HIQ ON UE.UserId = HIQ.OwnerUserId
    CROSS JOIN UNNEST(HIQ.TagArray) AS Tag (T)
    WHERE UE.GoldBadges >= 3 AND T.T IN ('performance', 'optimization')
),
UserTagPerformance AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.GoldBadges,
        UE.SilverBadges,
        UE.BronzeBadges,
        UE.QuestionsAsked,
        UE.AnswersGiven,
        COALESCE(UE.AvgPostScore, 0) AS OverallAvgPostScore,
        COALESCE(HIQ.AverageScoreForTaggedQuestions, 0) AS AvgScoreForPerformanceTags,
        SUM(CASE WHEN DPA.OriginalOwnerUserId = UE.UserId THEN 1 ELSE 0 END) AS QuestionsMarkedAsDuplicate,
        SUM(CASE WHEN DPA.DuplicateOwnerUserId = UE.UserId THEN 1 ELSE 0 END) AS AnswersOnDuplicateQuestions,
        LAG(UE.LastPostActivity) OVER (PARTITION BY UE.UserId ORDER BY UE.LastPostActivity) AS PreviousActivityDate,
        DATE_PART('day', NOW() - UE.LastPostActivity) AS DaysSinceLastActivity,
        -- Correlated subquery: Get average score of user's answers to questions that were later involved in a duplicate link.
        (SELECT AVG(A.Score)
         FROM Posts AS A
         WHERE A.OwnerUserId = UE.UserId
           AND A.PostTypeId = 2 -- Only answers
           AND EXISTS (
               SELECT 1
               FROM PostLinks AS PL_Inner
               WHERE (PL_Inner.PostId = A.ParentId OR PL_Inner.RelatedPostId = A.ParentId)
                 AND PL_Inner.LinkTypeId = 3
           )
           AND A.CreationDate < UE.LastPostActivity -- Only answers before the overall last post activity
        ) AS AvgAnswerScoreOnDuplicateRelatedPosts
    FROM UserEngagement AS UE
    LEFT JOIN LATERAL ( -- Lateral join to get aggregated stats for a user's 'performance' tagged questions
        SELECT
            OwnerUserId,
            AVG(PostScore) AS AverageScoreForTaggedQuestions,
            COUNT(DISTINCT PostId) AS PerformanceTaggedQuestionsCount
        FROM HighImpactQuestions
        CROSS JOIN UNNEST(TagArray) AS Tag (T)
        WHERE OwnerUserId = UE.UserId
          AND T.T IN ('performance', 'optimization', 'benchmark', 'scaling')
        GROUP BY OwnerUserId
    ) AS HIQ ON UE.UserId = HIQ.OwnerUserId
    LEFT JOIN DuplicatePostAnalysis AS DPA ON UE.UserId = DPA.OriginalOwnerUserId OR UE.UserId = DPA.DuplicateOwnerUserId
    GROUP BY UE.UserId, UE.DisplayName, UE.Reputation, UE.GoldBadges, UE.SilverBadges, UE.BronzeBadges, UE.QuestionsAsked, UE.AnswersGiven, UE.AvgPostScore, HIQ.AverageScoreForTaggedQuestions, UE.LastPostActivity
)
SELECT
    UTP.UserId,
    UTP.DisplayName,
    UTP.Reputation,
    UTP.GoldBadges,
    UTP.SilverBadges,
    UTP.BronzeBadges,
    UTP.QuestionsAsked,
    UTP.AnswersGiven,
    UTP.OverallAvgPostScore,
    UTP.AvgScoreForPerformanceTags,
    UTP.QuestionsMarkedAsDuplicate,
    UTP.AnswersOnDuplicateQuestions,
    UTP.AvgAnswerScoreOnDuplicateRelatedPosts,
    UTP.DaysSinceLastActivity,
    -- Calculate a weighted engagement score
    (UTP.Reputation * 0.1)
    + (UTP.GoldBadges * 5)
    + (UTP.SilverBadges * 3)
    + (UTP.BronzeBadges * 1)
    + (COALESCE(UTP.OverallAvgPostScore, 0) * 0.5)
    + (COALESCE(UTP.AvgAnswerScoreOnDuplicateRelatedPosts, 0) * 0.8) AS WeightedEngagementScore,
    -- String manipulation example
    LOWER(SUBSTRING(UTP.DisplayName, 1, 3)) || '_' || UPPER(SUBSTRING(UTP.DisplayName, LENGTH(UTP.DisplayName) - 2, 3)) AS DisplayNameSignature,
    -- Example of NULL logic and conditional aggregation based on post history
    MAX(CASE WHEN HIQ_Main.PostStatus = 'Closed' AND HIQ_Main.CloseReopenEvents > 0 THEN 'True' ELSE 'False' END) AS HasClosedReopenedQuestion,
    MAX(CASE WHEN HIQ_Main.BugCommentCount > 0 THEN 'True' ELSE 'False' END) AS HasBugCommentedQuestion
FROM UserTagPerformance AS UTP
LEFT JOIN HighImpactQuestions AS HIQ_Main ON UTP.UserId = HIQ_Main.OwnerUserId
WHERE UTP.Reputation > 1000 -- Filter for more established users
  AND (UTP.QuestionsMarkedAsDuplicate > 0 OR UTP.AnswersOnDuplicateQuestions > 0) -- Users involved in duplicates
  AND UTP.DaysSinceLastActivity < 90 -- Recently active
  AND UTP.UserId IN (SELECT UserId FROM HighReputationOrHighEngagementUsers) -- Filter by combined high-impact users
GROUP BY
    UTP.UserId, UTP.DisplayName, UTP.Reputation, UTP.GoldBadges, UTP.SilverBadges, UTP.BronzeBadges,
    UTP.QuestionsAsked, UTP.AnswersGiven, UTP.OverallAvgPostScore, UTP.AvgScoreForPerformanceTags,
    UTP.QuestionsMarkedAsDuplicate, UTP.AnswersOnDuplicateQuestions, UTP.AvgAnswerScoreOnDuplicateRelatedPosts,
    UTP.DaysSinceLastActivity
ORDER BY WeightedEngagementScore DESC, UTP.Reputation DESC
LIMIT 100;