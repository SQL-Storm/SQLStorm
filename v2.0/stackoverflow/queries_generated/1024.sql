-- {"query": "1024.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4445} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous User') AS DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(COALESCE(P.LastActivityDate, P.CreationDate, C.CreationDate, B.Date, U.LastAccessDate)) AS LastKnownActivity,
        AVG(CASE WHEN P.Score IS NOT NULL THEN P.Score ELSE 0 END) AS AvgPostScore,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END) AS TotalQuestionViews,
        MIN(U.CreationDate) OVER (PARTITION BY U.AccountId) AS FirstAccountCreationDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
        U.Views, U.UpVotes, U.DownVotes, U.AccountId
),
PostDetailsExtended AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        COALESCE(P.Title, 'N/A') AS PostTitle, -- Title is NULL for answers, etc.
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastActivityDate,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Tags,
        STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><') AS TagArray,
        CASE
            WHEN P.ClosedDate IS NOT NULL AND P.PostTypeId = 1 THEN 'Closed Question'
            WHEN P.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Has Accepted Answer'
            WHEN P.PostTypeId = 1 AND P.AnswerCount = 0 THEN 'Unanswered Question'
            ELSE 'Open'
        END AS PostStatus,
        COUNT(DISTINCT PH.Id) AS RevisionCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId, P.TypeId ORDER BY P.CreationDate DESC) AS rn_user_posttype,
        LAG(P.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostDate,
        -- Calculate the time difference between consecutive edits for a post, if any
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate ELSE NULL END) OVER (PARTITION BY P.Id ORDER BY PH.CreationDate DESC) -
        LAG(MAX(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate ELSE NULL END), 1, P.CreationDate) OVER (PARTITION BY P.Id ORDER BY PH.CreationDate DESC) AS TimeBetweenEdits
    FROM Posts AS P
    INNER JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN Votes AS V ON P.Id = V.PostId
    GROUP BY
        P.Id, P.PostTypeId, PT.Name, P.OwnerUserId, P.Title, P.CreationDate, P.Score,
        P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.LastActivityDate,
        P.AcceptedAnswerId, P.ParentId, P.Tags, P.ClosedDate, P.CommunityOwnedDate
),
TagPerformanceMetrics AS (
    SELECT
        T.TagName,
        T.Id AS TagId,
        COUNT(DISTINCT Q.PostId) AS TotalQuestionsWithTag,
        AVG(Q.PostScore) AS AvgQuestionScoreForTag,
        MAX(Q.PostCreationDate) AS LatestQuestionActivity,
        -- Correlated subquery to find the user with the most highly-scored questions for this specific tag
        (SELECT U.DisplayName
         FROM Users AS U
         JOIN (SELECT PDE.OwnerUserId, SUM(PDE.PostScore) AS TotalScore
               FROM PostDetailsExtended AS PDE
               WHERE PDE.PostTypeId = 1
                 AND PDE.Tags LIKE '%<' || T.TagName || '>%' -- Match tags directly for this subquery
               GROUP BY PDE.OwnerUserId
               ORDER BY TotalScore DESC, PDE.OwnerUserId
               LIMIT 1) AS TagTopUser ON U.Id = TagTopUser.OwnerUserId
        ) AS TopContributingUserForTag,
        SUM(CASE WHEN Q.PostStatus = 'Closed Question' THEN 1 ELSE 0 END) AS ClosedQuestionsCount
    FROM Tags AS T
    INNER JOIN PostDetailsExtended AS Q ON Q.PostTypeId = 1 AND Q.Tags LIKE '%<' || T.TagName || '>%'
    GROUP BY T.TagName, T.Id
),
UserBadgeOverview AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(Date) AS LatestBadgeDate,
        -- Correlated subquery: Find the name of the user's most recent badge
        (SELECT Name FROM Badges WHERE UserId = B.UserId ORDER BY Date DESC LIMIT 1) AS MostRecentBadgeName
    FROM Badges AS B
    GROUP BY UserId
)
-- Main query combining user activity, post details, tag performance, and badge info
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserCreationDate,
    UAS.LastKnownActivity,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalComments,
    UAS.TotalBadges,
    UBO.GoldBadges,
    UBO.SilverBadges,
    UBO.BronzeBadges,
    UBO.MostRecentBadgeName,
    PDE.PostId,
    PDE.PostTypeName,
    PDE.PostTitle,
    PDE.PostCreationDate,
    PDE.PostScore,
    PDE.ViewCount,
    PDE.AnswerCount,
    PDE.CommentCount,
    PDE.FavoriteCount,
    PDE.PostStatus,
    PDE.RevisionCount,
    PDE.UpVoteCount,
    PDE.DownVoteCount,
    EXTRACT(EPOCH FROM (PDE.LastActivityDate - PDE.PostCreationDate)) / 3600 AS HoursSincePostCreation,
    EXTRACT(EPOCH FROM (PDE.PostCreationDate - PDE.PreviousPostDate)) / 86400 AS DaysBetweenUserPosts,
    EXTRACT(EPOCH FROM PDE.TimeBetweenEdits) / 60 AS MinutesBetweenEdits,
    T.TagName AS RelatedTagName,
    TPM.TotalQuestionsWithTag,
    TPM.AvgQuestionScoreForTag,
    TPM.TopContributingUserForTag,
    TPM.ClosedQuestionsCount,
    -- Window function: Rank users by reputation within segments of their post counts (low/medium/high posters)
    DENSE_RANK() OVER (
        PARTITION BY CASE WHEN UAS.TotalPosts < 10 THEN 'Low'
                          WHEN UAS.TotalPosts BETWEEN 10 AND 100 THEN 'Medium'
                          ELSE 'High' END
        ORDER BY UAS.Reputation DESC, UAS.UserId
    ) AS RankByReputationSegment,
    -- Calculate a "controversy score" for posts
    (CAST(PDE.DownVoteCount AS NUMERIC) / NULLIF(PDE.UpVoteCount + PDE.DownVoteCount, 0)) * PDE.CommentCount AS ControversyScore,
    -- NULL logic and complex calculations
    NULLIF(UAS.TotalPosts, 0) / NULLIF(EXTRACT(EPOCH FROM (NOW() - UAS.UserCreationDate)) / (3600 * 24 * 365.25), 0) AS PostsPerYearActive,
    -- String expressions and case logic for post analysis
    CASE
        WHEN PDE.PostTypeName = 'Question' AND PDE.PostTitle ILIKE '%performance%' AND PDE.ViewCount > 50000 THEN 'High-Performance Question'
        WHEN PDE.PostTypeName = 'Answer' AND PDE.PostScore > 100 AND PDE.RevisionCount > 3 THEN 'Highly Refined Answer'
        WHEN PDE.Tags IS NOT NULL AND PDE.Tags LIKE '%<java>%' AND PDE.Tags LIKE '%<android>%' THEN 'Java Android Specific'
        WHEN PDE.PostStatus = 'Closed Question' AND TPM.ClosedQuestionsCount > TPM.TotalQuestionsWithTag * 0.5 THEN 'Problematic Tag Question'
        ELSE 'General Interest'
    END AS PostCategory,
    -- Conditional check using correlated subquery for recent "Accepted" post history
    (SELECT EXISTS(
        SELECT 1 FROM PostHistory PH_sub
        WHERE PH_sub.PostId = PDE.PostId
          AND PH_sub.PostHistoryTypeId = 1 AND PH_sub.CreationDate > (NOW() - INTERVAL '1 year')
    )) AS HasRecentInitialHistory,
    -- Check if user is a "veteran" based on creation date and total upvotes
    CASE
        WHEN UAS.UserCreationDate < (NOW() - INTERVAL '10 years') AND UAS.UserTotalUpVotes > 10000 THEN 'Veteran Influencer'
        WHEN UAS.UserCreationDate < (NOW() - INTERVAL '5 years') AND UAS.UserTotalUpVotes > 1000 THEN 'Established Contributor'
        ELSE 'Newer User'
    END AS UserSeniorityLevel
FROM UserActivitySummary AS UAS
LEFT JOIN UserBadgeOverview AS UBO ON UAS.UserId = UBO.UserId
LEFT JOIN PostDetailsExtended AS PDE ON UAS.UserId = PDE.OwnerUserId
LEFT JOIN LATERAL UNNEST(PDE.TagArray) AS T(TagName) ON PDE.TagArray IS NOT NULL -- Use LATERAL UNNEST for tags
LEFT JOIN TagPerformanceMetrics AS TPM ON T.TagName = TPM.TagName
WHERE
    UAS.Reputation >= 5000
    AND (PDE.PostId IS NULL OR PDE.rn_user_posttype <= 3) -- Only consider top 3 most recent posts per user per type
    AND (
        PDE.PostScore IS NULL OR PDE.PostScore >= 5
        OR
        (PDE.PostTypeName = 'Question' AND PDE.ViewCount > 1000 AND PDE.AnswerCount > 0)
    )
    AND UAS.LastKnownActivity > (NOW() - INTERVAL '2 year')
    AND (UAS.TotalBadges IS NULL OR UAS.TotalBadges > 5)
    AND (TPM.AvgQuestionScoreForTag IS NULL OR TPM.AvgQuestionScoreForTag > 10) -- Tag must be somewhat popular
    AND NOT EXISTS ( -- Anti-correlated subquery: Exclude users who have posted more than 10 times about "C++" in the last year
        SELECT 1 FROM Posts P_sub
        WHERE P_sub.OwnerUserId = UAS.UserId
          AND P_sub.CreationDate > (NOW() - INTERVAL '1 year')
          AND P_sub.Tags LIKE '%<c++>%'
        GROUP BY P_sub.OwnerUserId
        HAVING COUNT(P_sub.Id) > 10
    )

UNION ALL

-- Second branch: Identify highly active users who have also voted on many posts, particularly 'Deletion' or 'Spam' votes,
-- potentially indicating moderation activity. Exclude those with very low reputation.
SELECT
    U.Id AS UserId,
    COALESCE(U.DisplayName, 'Inactive User') AS DisplayName,
    U.Reputation,
    U.CreationDate AS UserCreationDate,
    U.LastAccessDate AS LastKnownActivity, -- Using LastAccessDate directly for this branch
    (SELECT COUNT(P.Id) FROM Posts P WHERE P.OwnerUserId = U.Id) AS TotalPosts,
    (SELECT COUNT(P.Id) FROM Posts P WHERE P.OwnerUserId = U.Id AND P.PostTypeId = 1) AS TotalQuestions,
    (SELECT COUNT(P.Id) FROM Posts P WHERE P.OwnerUserId = U.Id AND P.PostTypeId = 2) AS TotalAnswers,
    (SELECT COUNT(C.Id) FROM Comments C WHERE C.UserId = U.Id) AS TotalComments,
    (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id) AS TotalBadges,
    SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    MAX(B.Date) AS LatestBadgeDate,
    (SELECT Name FROM Badges WHERE UserId = U.Id ORDER BY Date DESC LIMIT 1) AS MostRecentBadgeName,
    P_active.Id AS PostId,
    PT_active.Name AS PostTypeName,
    COALESCE(P_active.Title, 'N/A') AS PostTitle,
    P_active.CreationDate AS PostCreationDate,
    P_active.Score AS PostScore,
    P_active.ViewCount,
    P_active.AnswerCount,
    P_active.CommentCount,
    P_active.FavoriteCount,
    CASE WHEN P_active.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Active' END AS PostStatus,
    COUNT(DISTINCT PH_active.Id) AS RevisionCount,
    SUM(CASE WHEN V_active.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN V_active.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    EXTRACT(EPOCH FROM (P_active.LastActivityDate - P_active.CreationDate)) / 3600 AS HoursSincePostCreation,
    NULL AS DaysBetweenUserPosts, -- Not computed in this branch
    NULL AS MinutesBetweenEdits, -- Not computed in this branch
    T_active.TagName AS RelatedTagName,
    (SELECT COUNT(DISTINCT P2.Id) FROM Posts P2 WHERE P2.Tags ILIKE '%' || T_active.TagName || '%' AND P2.PostTypeId = 1) AS TotalQuestionsWithTag,
    (SELECT AVG(P2.Score) FROM Posts P2 WHERE P2.Tags ILIKE '%' || T_active.TagName || '%' AND P2.PostTypeId = 1) AS AvgQuestionScoreForTag,
    NULL AS TopContributingUserForTag, -- Not computed in this branch
    (SELECT COUNT(DISTINCT P2.Id) FROM Posts P2 WHERE P2.Tags ILIKE '%' || T_active.TagName || '%' AND P2.PostTypeId = 1 AND P2.ClosedDate IS NOT NULL) AS ClosedQuestionsCount,
    0 AS RankByReputationSegment, -- Placeholder
    CAST(SUM(CASE WHEN V_mod.VoteTypeId IN (3,10,12) THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(COUNT(V_mod.Id), 0) AS ControversyScore, -- Ratio of negative/mod votes
    NULLIF((SELECT COUNT(P3.Id) FROM Posts P3 WHERE P3.OwnerUserId = U.Id), 0) / NULLIF(EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / (3600 * 24 * 365.25), 0) AS PostsPerYearActive,
    'Moderation Interest' AS PostCategory,
    FALSE AS HasRecentInitialHistory, -- Assume false for this branch
    'Moderator Candidate' AS UserSeniorityLevel
FROM Users AS U
INNER JOIN Badges AS B ON U.Id = B.UserId -- Users must have at least one badge
INNER JOIN Posts AS P_active ON U.Id = P_active.OwnerUserId
INNER JOIN PostTypes AS PT_active ON P_active.PostTypeId = PT_active.Id
LEFT JOIN PostHistory AS PH_active ON P_active.Id = PH_active.PostId
LEFT JOIN Votes AS V_active ON P_active.Id = V_active.PostId
INNER JOIN Votes AS V_mod ON U.Id = V_mod.UserId AND V_mod.VoteTypeId IN (3, 10, 12) -- Users who cast down, deletion, or spam votes
LEFT JOIN LATERAL UNNEST(STRING_TO_ARRAY(SUBSTRING(P_active.Tags, 2, LENGTH(P_active.Tags) - 2), '><')) AS T_active(TagName) ON P_active.Tags IS NOT NULL AND P_active.Tags != ''
WHERE
    U.Reputation >= 20000 -- Significant reputation
    AND U.LastAccessDate > (NOW() - INTERVAL '1 year')
    AND (SELECT COUNT(V_sub.Id) FROM Votes V_sub WHERE V_sub.UserId = U.Id AND V_sub.VoteTypeId IN (10, 12)) > 50 -- At least 50 deletion/spam votes
    AND P_active.CreationDate > (NOW() - INTERVAL '3 years') -- Recent posts
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
    P_active.Id, PT_active.Name, P_active.Title, P_active.CreationDate, P_active.Score,
    P_active.ViewCount, P_active.AnswerCount, P_active.CommentCount, P_active.FavoriteCount,
    P_active.ClosedDate, P_active.LastActivityDate, T_active.TagName
HAVING COUNT(DISTINCT V_mod.Id) > 100 -- Users who made more than 100 moderation-related votes
ORDER BY Reputation DESC, PostScore DESC
LIMIT 7500;
