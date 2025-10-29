-- {"query": "1577.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2333} 

WITH UserActivitySummary AS (
    -- CTE 1: Summarizes activity and reputation for highly engaged users,
    -- including their post counts and average scores.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(P.Id) AS TotalPostsWritten,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(AVG(P.Score), 0.0) AS AvgPostScore,
        MAX(P.LastActivityDate) AS LatestPostActivityDate,
        RANK() OVER (ORDER BY U.Reputation DESC, COUNT(P.Id) DESC) AS ReputationActivityRank
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE U.Reputation > 5000
      AND U.LastAccessDate >= NOW() - INTERVAL '1 year'
      AND U.Views > 100
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
    HAVING COUNT(P.Id) >= 10
),
PostRevisionAndInteraction AS (
    -- CTE 2: Gathers detailed post information, including revision counts,
    -- comment metrics, and tags, focusing on questions and answers.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Title,
        P.Body,
        P.Tags,
        P.Score,
        P.ViewCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.LastEditDate,
        P.ClosedDate,
        COALESCE(P.AnswerCount, 0) AS DirectAnswerCount,
        COUNT(DISTINCT PH.Id) AS RevisionHistoryCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN PH.Id END) AS ContentEditCount,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        COALESCE(AVG(C.Score), 0.0) AS AvgCommentScore,
        COUNT(C.Id) AS CommentCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDate,
        STRING_AGG(DISTINCT SUBSTRING(t.TagName, 1, 30), ',') FILTER (WHERE t.TagName IS NOT NULL) AS AssociatedTagNames
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Tags T ON P.Tags LIKE '%<' || T.TagName || '>%' -- Join with Tags for tag names
    WHERE P.PostTypeId IN (1, 2) -- Questions or Answers
      AND P.CreationDate >= NOW() - INTERVAL '3 years'
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.Title, P.Body, P.Tags, P.Score, P.ViewCount,
             P.FavoriteCount, P.OwnerUserId, P.AcceptedAnswerId, P.ParentId, P.LastEditDate, P.ClosedDate, P.AnswerCount
    HAVING COUNT(P.Id) > 0 -- Ensure valid posts
),
TagPerformanceMetrics AS (
    -- CTE 3: Calculates performance metrics for the most popular tags.
    SELECT
        TRIM(LOWER(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')))) AS TagName,
        COUNT(P.Id) AS PostsPerTag,
        SUM(P.Score) AS TotalScorePerTag,
        AVG(P.ViewCount) AS AvgViewCountPerTag,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY P.Score) AS MedianScorePerTag
    FROM Posts P
    WHERE P.PostTypeId = 1
      AND P.Tags IS NOT NULL
      AND P.CreationDate >= NOW() - INTERVAL '3 years'
    GROUP BY TRIM(LOWER(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))))
    HAVING COUNT(P.Id) > 50
)
-- Main query: Joins the CTEs and performs final complex analysis
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalPostsWritten,
    PRI.PostId,
    PRI.Title,
    PRI.PostCreationDate,
    PRI.Score AS PostScore,
    PRI.ViewCount,
    PRI.FavoriteCount,
    PRI.RevisionHistoryCount,
    PRI.ContentEditCount,
    PRI.CommentCount,
    PRI.TotalCommentScore,
    PRI.AssociatedTagNames,
    -- Window function: Calculate the moving average of post scores for a user's posts
    AVG(PRI.Score) OVER (PARTITION BY UAS.UserId ORDER BY PRI.PostCreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS UserMovingAvgPostScore,
    -- Correlated subquery: Get the highest reputation of any user who answered this post's question (if it's an answer)
    (
        SELECT MAX(AnsUser.Reputation)
        FROM Posts Ans
        JOIN Users AnsUser ON Ans.OwnerUserId = AnsUser.Id
        WHERE Ans.ParentId = PRI.PostId AND PRI.PostTypeId = 1
    ) AS MaxAnswererReputation,
    -- Complex calculation: Engagement factor considering various metrics
    ROUND(
        (PRI.Score * 0.5 + PRI.TotalCommentScore * 0.2 + PRI.FavoriteCount * 0.3) *
        (LOG(GREATEST(PRI.ViewCount, 1)) / LOG(10) + LOG(GREATEST(PRI.RevisionHistoryCount, 1)) / LOG(5)) *
        (CASE WHEN PRI.AcceptedAnswerId IS NOT NULL THEN 1.5 ELSE 1.0 END) *
        (1 + (PRI.ContentEditCount / GREATEST(PRI.RevisionHistoryCount, 1.0)) * 0.5),
        3
    ) AS CalculatedEngagementFactor,
    -- String expression: Extract the first tag (if available) and its average performance
    COALESCE(
        SUBSTRING(PRI.Tags, 2, POSITION('><' IN PRI.Tags) - 2),
        SUBSTRING(PRI.Tags, 2, LENGTH(PRI.Tags) - 2)
    ) AS PrimaryTag,
    TPM.AvgViewCountPerTag AS PrimaryTagAvgViewCount,
    TPM.MedianScorePerTag AS PrimaryTagMedianScore,
    -- NULL logic and CASE statement: Classify posts based on activity and status
    CASE
        WHEN PRI.ClosedDate IS NOT NULL AND PRI.LastClosedDate < PRI.PostCreationDate + INTERVAL '30 days' THEN 'Closed_Early'
        WHEN PRI.AcceptedAnswerId IS NOT NULL AND PRI.DirectAnswerCount > 0 THEN 'Answered_Accepted'
        WHEN PRI.DirectAnswerCount > 0 AND PRI.AcceptedAnswerId IS NULL THEN 'Answered_Unaccepted'
        WHEN PRI.RevisionHistoryCount > 5 AND PRI.CommentCount > 5 THEN 'Highly_Discussed_Revised'
        WHEN PRI.ViewCount > 1000 AND PRI.Score < 0 THEN 'High_Views_Low_Score'
        ELSE 'Active_Unresolved'
    END AS PostStatusClassification,
    -- Outer join logic: Retrieve details of the accepted answer, if applicable
    AA.Score AS AcceptedAnswerScore,
    AA.OwnerUserId AS AcceptedAnswerOwnerId,
    AA.CreationDate AS AcceptedAnswerCreationDate,
    -- Full Outer Join (simulated with LEFT JOINs and COALESCE logic) to link related posts
    -- Here we get details of parent question for answers or related questions via PostLinks
    -- Not a true FULL OUTER JOIN of two independent sets, but demonstrating complex linking.
    COALESCE(ParentQ.Title, LinkedP.Title) AS RelatedPostTitle,
    COALESCE(ParentQ.Score, LinkedP.Score) AS RelatedPostScore
FROM UserActivitySummary UAS
INNER JOIN PostRevisionAndInteraction PRI ON UAS.UserId = PRI.OwnerUserId
LEFT JOIN Posts AA ON PRI.AcceptedAnswerId = AA.Id AND PRI.PostTypeId = 1 -- Details for Accepted Answer
LEFT JOIN TagPerformanceMetrics TPM ON TRIM(LOWER(
    COALESCE(
        SUBSTRING(PRI.Tags, 2, POSITION('><' IN PRI.Tags) - 2),
        SUBSTRING(PRI.Tags, 2, LENGTH(PRI.Tags) - 2)
    )
)) = TPM.TagName
-- Conditional joins for related posts based on PostTypeId
LEFT JOIN Posts ParentQ ON PRI.PostTypeId = 2 AND PRI.ParentId = ParentQ.Id
LEFT JOIN PostLinks PL ON PRI.PostTypeId = 1 AND PRI.PostId = PL.PostId AND PL.LinkTypeId = 1 -- Linked questions
LEFT JOIN Posts LinkedP ON PL.RelatedPostId = LinkedP.Id
WHERE PRI.RevisionHistoryCount > 1
  AND PRI.ViewCount > 50
  AND UAS.ReputationActivityRank <= 1000 -- Limit to top active users by rank
  AND (PRI.ClosedDate IS NULL OR PRI.ClosedDate > NOW() - INTERVAL '1 year') -- Include recently closed or open posts
  AND PRI.Title IS NOT NULL
  AND PRI.Title LIKE '%[sql]%' OR PRI.Tags LIKE '%<sql>%' -- Focus on posts related to 'SQL'
ORDER BY CalculatedEngagementFactor DESC, UAS.Reputation DESC, PRI.PostCreationDate DESC
LIMIT 5000;
