-- {"query": "1950.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3124} 

WITH HighValueEntities AS (
    -- Combines high-scoring posts and comments to identify impactful contributions across different entity types
    SELECT
        P.Id AS EntityId,
        'Post' AS EntityType,
        P.OwnerUserId AS EntityOwnerId,
        P.CreationDate AS EntityCreationDate,
        P.Score AS EntityScore,
        P.Body AS EntityContent,
        NULL::int AS ParentEntityId, -- Posts don't have a direct parent_entity_id in this context
        P.ContentLicense
    FROM Posts P
    WHERE P.Score >= 50 AND P.PostTypeId IN (1, 2) -- High-scoring Questions or Answers
    UNION ALL
    SELECT
        C.Id AS EntityId,
        'Comment' AS EntityType,
        C.UserId AS EntityOwnerId,
        C.CreationDate AS EntityCreationDate,
        C.Score AS EntityScore,
        C.Text AS EntityContent,
        C.PostId AS ParentEntityId,
        C.ContentLicense
    FROM Comments C
    WHERE C.Score >= 20 -- High-scoring Comments
),
UserActivityMetrics AS (
    -- Aggregates basic activity metrics for each user
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS TotalGivenUpVotes,
        U.DownVotes AS TotalGivenDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScoreReceived,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScoreReceived,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentActivity
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
        U.UpVotes, U.DownVotes
),
PostTaggingAnalysis AS (
    -- Extracts tag information and other post-specific details, primarily for questions
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.ClosedDate,
        STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><') AS TagArray,
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 5) AS BookmarkCount, -- Correlated subquery for favorite count (VoteType 5)
        (SELECT MAX(CH.CreationDate) FROM Comments CH WHERE CH.PostId = P.Id) AS LatestCommentDate, -- Correlated subquery for latest comment
        (SELECT COALESCE(MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN CRT.Name END), 'N/A')
         FROM PostHistory PH
         LEFT JOIN CloseReasonTypes CRT ON PH.Comment = CRT.Id::varchar -- Assuming Comment stores CloseReasonId as string
         WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 10
        ) AS CloseReasonName, -- Correlated subquery for close reason name
        P.ContentLicense
    FROM Posts P
    WHERE P.PostTypeId = 1 -- Focus on questions for tag analysis
      AND P.Tags IS NOT NULL
      AND P.Tags != ''
),
PostEditHistory AS (
    -- Tracks post editing history, identifying edit types and timing
    SELECT
        PH.PostId,
        PH.UserId AS EditorUserId,
        PH.CreationDate AS EditDate,
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousEditDate, -- Window function: time of previous edit
        CASE
            WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 'Edit' -- Title, Body, Tags edits
            WHEN PH.PostHistoryTypeId IN (1, 2, 3) THEN 'Initial' -- Initial Title, Body, Tags contributions
            ELSE 'Other'
        END AS HistoryType,
        RANK() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS LatestEditRank -- Window function: ranks edits for a post
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (1,2,3,4,5,6) -- Filter for initial contributions and edits
),
AggregatedPostEdits AS (
    -- Summarizes edit activities per post
    SELECT
        PostId,
        COUNT(DISTINCT EditorUserId) AS UniqueEditors,
        COUNT(*) FILTER (WHERE HistoryType = 'Edit') AS TotalEditEvents, -- Conditional aggregation
        SUM(EXTRACT(EPOCH FROM (EditDate - PreviousEditDate))) AS TotalEditTimeSpanSeconds -- Calculates total time spent editing
    FROM PostEditHistory
    GROUP BY PostId
),
UserBadgeAwards AS (
    -- Aggregates badge information for each user
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(B.Date) AS LatestBadgeAwardDate
    FROM Badges B
    GROUP BY B.UserId
)
SELECT
    UAM.UserId,
    UAM.DisplayName,
    UAM.Reputation,
    UAM.TotalPosts,
    UAM.TotalQuestions,
    UAM.TotalAnswers,
    UAM.TotalPostScoreReceived,
    UAM.TotalCommentsMade,
    UAM.TotalGivenUpVotes,
    UAM.TotalGivenDownVotes,
    UBA.TotalBadges,
    UBA.GoldBadges,
    UBA.SilverBadges,
    UBA.BronzeBadges,
    (SELECT COUNT(DISTINCT P.Id) FROM Posts P WHERE P.OwnerUserId = UAM.UserId AND P.AcceptedAnswerId IS NOT NULL) AS QuestionsWithAcceptedAnswers, -- Correlated subquery
    CAST(UAM.TotalAnswers AS DECIMAL) / COALESCE(NULLIF(UAM.TotalQuestions, 0), 1) AS AnswerToQuestionRatio, -- Calculation with NULL logic
    CAST(UAM.TotalPostScoreReceived AS DECIMAL) / (COALESCE(NULLIF(UAM.TotalPosts, 0), 1)) AS AvgScorePerPost, -- Calculation with NULL logic
    CASE
        WHEN UAM.Reputation >= 10000 AND UBA.GoldBadges >= 1 THEN 'Veteran_Elite'
        WHEN UAM.Reputation >= 5000 AND UAM.TotalAnswers >= 100 AND UAM.TotalCommentsMade < 50 THEN 'Pro_Answerer_Focused'
        WHEN UAM.TotalCommentsMade > UAM.TotalPosts * 2 THEN 'Chatty_User_Verbose'
        WHEN EXISTS ( -- Correlated subquery with NULL logic for content license
            SELECT 1
            FROM PostTaggingAnalysis PTA_sub
            WHERE PTA_sub.OwnerUserId = UAM.UserId AND LOWER(COALESCE(PTA_sub.ContentLicense, 'N/A')) LIKE '%cc by-sa 4.0%'
        ) THEN 'CC_BY_SA_4_User'
        ELSE 'Active_Participant_General'
    END AS UserCategory, -- Complex conditional logic
    MIN(PATA.PostCreationDate) OVER (PARTITION BY UAM.UserId) AS FirstQuestionDate, -- Window function
    MAX(PATA.PostCreationDate) OVER (PARTITION BY UAM.UserId) AS LastQuestionDate, -- Window function
    AVG(PATA.PostScore) OVER (PARTITION BY UAM.UserId) AS AvgQuestionScore, -- Window function
    SUM(PATA.BookmarkCount) OVER (PARTITION BY UAM.UserId) AS TotalBookmarkedQuestions, -- Window function
    MAX(CASE WHEN PATA.CloseReasonName != 'N/A' THEN PATA.CloseReasonName ELSE NULL END) OVER (PARTITION BY UAM.UserId) AS LatestCloseReasonForUserQuestion, -- Window function with NULL logic
    COUNT(DISTINCT CASE WHEN PATA.ViewCount > 1000 AND PATA.AnswerCount > 5 AND PATA.ClosedDate IS NULL THEN PATA.PostId END) OVER (PARTITION BY UAM.UserId) AS HighTrafficOpenQuestions, -- Window function with complex predicate
    ROW_NUMBER() OVER (ORDER BY UAM.Reputation DESC, UAM.TotalPosts DESC, UAM.TotalPostScoreReceived DESC) AS GlobalReputationRank, -- Window function for ranking
    DENSE_RANK() OVER (ORDER BY UBA.GoldBadges DESC, UBA.SilverBadges DESC) AS BadgeEliteRank, -- Window function for ranking
    SUM(COALESCE(APE.TotalEditEvents, 0)) AS TotalUserEditEvents,
    AVG(COALESCE(APE.TotalEditTimeSpanSeconds, 0)) AS AvgPostEditTimeSpan,
    (
        -- Correlated subquery with nested aggregation to find average number of links for user's posts
        SELECT AVG(link_counts.NumLinks)
        FROM (
            SELECT COUNT(PL.Id) AS NumLinks
            FROM Posts P_sub
            LEFT JOIN PostLinks PL ON P_sub.Id = PL.PostId OR P_sub.Id = PL.RelatedPostId
            WHERE P_sub.OwnerUserId = UAM.UserId
            GROUP BY P_sub.Id
        ) AS link_counts
    ) AS AvgPostLinkCount,
    COUNT(DISTINCT HVE.EntityId) FILTER (WHERE HVE.EntityOwnerId = UAM.UserId) AS TotalHighValueEntitiesContributed, -- Conditional aggregation using CTE with UNION ALL
    COUNT(DISTINCT PATA.PostId) FILTER (
        WHERE PATA.PostScore > (UAM.TotalPostScoreReceived / COALESCE(NULLIF(UAM.TotalPosts, 0), 1)) * 1.5 -- Complex calculation
          AND PATA.FavoriteCount > 0
          AND PATA.ViewCount > 5000
          AND (PATA.ClosedDate IS NOT NULL OR PATA.LatestCommentDate > UAM.LastAccessDate) -- Complex predicate with date logic and NULL check
          AND EXISTS (SELECT 1 FROM UNNEST(PATA.TagArray) AS tag WHERE LOWER(tag) LIKE '%javascript%' OR LOWER(tag) LIKE '%python%') -- String expression and correlated subquery with UNNEST
          AND PATA.ContentLicense IS NOT NULL AND PATA.ContentLicense != 'CC BY-SA 2.5' -- NULL logic and string comparison
    ) AS HighValueTargetedQuestions,
    (
        -- Correlated subquery for top 5 most frequent tags for user's questions
        SELECT
            ARRAY_AGG(DISTINCT T.TagName ORDER BY T.TagName LIMIT 5)
        FROM UNNEST(PATA.TagArray) AS tag_name
        JOIN Tags T ON LOWER(T.TagName) = LOWER(tag_name)
        WHERE UAM.UserId = PATA.OwnerUserId
        AND PATA.PostTypeId = 1
        GROUP BY UAM.UserId -- Group by UserID to aggregate tags per user within the subquery
    ) AS Top5FrequentTagsByUser

FROM UserActivityMetrics UAM
LEFT JOIN UserBadgeAwards UBA ON UAM.UserId = UBA.UserId
LEFT JOIN PostTaggingAnalysis PATA ON UAM.UserId = PATA.OwnerUserId -- Left join to keep users without questions
LEFT JOIN AggregatedPostEdits APE ON PATA.PostId = APE.PostId -- Left join for posts without edits
LEFT JOIN HighValueEntities HVE ON UAM.UserId = HVE.EntityOwnerId -- Left join for users without high-value entities
WHERE UAM.Reputation >= 1000
  AND UAM.LastAccessDate >= (NOW() - INTERVAL '1 year') -- Date comparison
  AND (UAM.TotalPosts > 10 OR UAM.TotalCommentsMade > 20) -- Complex boolean logic
  AND (UAM.TotalGivenUpVotes > UAM.TotalGivenDownVotes * 1.5 OR UAM.GoldBadges > 0) -- Complex numerical and boolean logic
  AND UAM.DisplayName IS NOT NULL -- NULL logic
GROUP BY
    UAM.UserId, UAM.DisplayName, UAM.Reputation, UAM.TotalPosts, UAM.TotalQuestions,
    UAM.TotalAnswers, UAM.TotalPostScoreReceived, UAM.TotalCommentsMade,
    UAM.TotalGivenUpVotes, UAM.TotalGivenDownVotes,
    UBA.TotalBadges, UBA.GoldBadges, UBA.SilverBadges, UBA.BronzeBadges
ORDER BY
    GlobalReputationRank ASC, HighValueTargetedQuestions DESC
LIMIT 100;
