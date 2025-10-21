-- {"query": "49023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2133} 

WITH UserBaseStats AS (
    -- Initial selection of active users with minimum reputation, last activity, and creation date filters
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate
    FROM Users AS U
    WHERE U.Reputation > 1000
      AND U.LastAccessDate >= (NOW() - INTERVAL '2 year')
      AND U.CreationDate >= (NOW() - INTERVAL '10 year')
),
UserActivitySummary AS (
    -- Summarize overall post and comment activity for active users
    SELECT
        UBS.UserId,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END) AS AvgQuestionViewCount,
        SUM(P.FavoriteCount) AS TotalQuestionFavorites,
        COUNT(DISTINCT C.Id) AS TotalCommentsWritten
    FROM UserBaseStats AS UBS
    LEFT JOIN Posts AS P ON UBS.UserId = P.OwnerUserId
    LEFT JOIN Comments AS C ON UBS.UserId = C.UserId
    GROUP BY UBS.UserId
),
UserTagSpecificQuestionMetrics AS (
    -- Analyze questions by specific users within a predefined set of "hot" tags
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT P.Id) AS QuestionsInHotTags,
        AVG(P.Score) AS AvgScoreHotTagQuestions,
        MAX(P.ViewCount) AS MaxViewCountHotTagQuestions,
        SUM(P.FavoriteCount) AS TotalFavoritesHotTagQuestions
    FROM Posts AS P
    JOIN UserBaseStats AS UBS ON P.OwnerUserId = UBS.UserId
    CROSS JOIN UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')) AS TagName
    WHERE P.PostTypeId = 1 -- Only questions
      AND P.CreationDate >= (NOW() - INTERVAL '5 year')
      AND TagName IN ('javascript', 'python', 'java', 'c#', 'sql', 'html', 'css', 'reactjs', 'node.js', 'typescript', 'php')
    GROUP BY P.OwnerUserId
),
PostHistoryEngagement AS (
    -- Count edits and specific close reasons for questions
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.Id END) AS TotalEditsToOwnQuestions, -- Edit Title, Body, Tags
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 AND CRT.Name IN ('Duplicate', 'Exact Duplicate', 'Needs details or clarity') THEN PH.PostId END) AS QuestionsClosedForClarityOrDuplicate
    FROM Posts AS P
    JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN CloseReasonTypes AS CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment = CRT.Id::text -- Assuming Comment stores CloseReasonId for type 10
    WHERE P.PostTypeId = 1 -- Only questions
      AND P.CreationDate >= (NOW() - INTERVAL '5 year')
      AND P.OwnerUserId IN (SELECT UserId FROM UserBaseStats)
    GROUP BY P.OwnerUserId
),
UserBadgeAchievements AS (
    -- Count total and gold badges for users
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges AS B
    JOIN UserBaseStats AS UBS ON B.UserId = UBS.UserId
    GROUP BY B.UserId
),
UserAcceptedAnswerCount AS (
    -- Count how many of a user's answers were accepted
    SELECT
        A.OwnerUserId AS UserId,
        COUNT(A.Id) AS TotalAcceptedAnswers
    FROM Posts AS A
    JOIN Posts AS Q ON A.Id = Q.AcceptedAnswerId -- A is an answer that was accepted for question Q
    WHERE A.PostTypeId = 2 -- A must be an answer
    GROUP BY A.OwnerUserId
),
UserLinkedPostActivity AS (
    -- Count how many times a user's questions or answers are linked by other posts
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT PL.PostId) AS OtherPostsLinkingToUserContent, -- Posts that link to this user's posts
        COUNT(DISTINCT PL_REL.RelatedPostId) AS UserContentLinkingToOtherPosts -- This user's posts that link to other posts
    FROM Posts AS P
    LEFT JOIN PostLinks AS PL ON P.Id = PL.RelatedPostId AND PL.LinkTypeId = 1 -- Other posts link to this user's post
    LEFT JOIN PostLinks AS PL_REL ON P.Id = PL_REL.PostId AND PL_REL.LinkTypeId = 1 -- This user's post links to another post
    WHERE P.OwnerUserId IN (SELECT UserId FROM UserBaseStats)
    GROUP BY P.OwnerUserId
)
SELECT
    UBS.UserId,
    UBS.DisplayName,
    UBS.Reputation,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    COALESCE(UTSQM.QuestionsInHotTags, 0) AS QuestionsInHotTags,
    COALESCE(UTSQM.AvgScoreHotTagQuestions, 0.0) AS AvgScoreHotTagQuestions,
    COALESCE(UTSQM.MaxViewCountHotTagQuestions, 0) AS MaxViewCountHotTagQuestions,
    COALESCE(UTSQM.TotalFavoritesHotTagQuestions, 0) AS TotalFavoritesHotTagQuestions,
    COALESCE(PHE.TotalEditsToOwnQuestions, 0) AS TotalEditsToOwnQuestions,
    COALESCE(PHE.QuestionsClosedForClarityOrDuplicate, 0) AS QuestionsClosedForClarityOrDuplicate,
    COALESCE(UBA.TotalBadges, 0) AS TotalBadges,
    COALESCE(UBA.GoldBadges, 0) AS GoldBadges,
    COALESCE(UAA.TotalAcceptedAnswers, 0) AS TotalAcceptedAnswers,
    COALESCE(ULPA.OtherPostsLinkingToUserContent, 0) AS OtherPostsLinkingToUserContent,
    COALESCE(ULPA.UserContentLinkingToOtherPosts, 0) AS UserContentLinkingToOtherPosts,
    -- Composite score for overall contribution and influence
    (
        UBS.Reputation * 0.05 +
        UAS.TotalPosts * 0.1 +
        COALESCE(UTSQM.AvgScoreHotTagQuestions, 0) * 0.5 +
        COALESCE(UTSQM.TotalFavoritesHotTagQuestions, 0) * 0.2 +
        COALESCE(PHE.TotalEditsToOwnQuestions, 0) * 0.05 +
        COALESCE(UBA.GoldBadges, 0) * 10 +
        COALESCE(UAA.TotalAcceptedAnswers, 0) * 0.7 +
        COALESCE(ULPA.OtherPostsLinkingToUserContent, 0) * 0.3 -
        COALESCE(PHE.QuestionsClosedForClarityOrDuplicate, 0) * 2 -- Penalty for questions closed as duplicate/unclear
    ) AS OverallContributionScore,
    RANK() OVER (ORDER BY UBS.Reputation DESC, UAS.TotalPosts DESC, COALESCE(UTSQM.AvgScoreHotTagQuestions, 0) DESC) AS ReputationActivityRank,
    NTILE(5) OVER (ORDER BY (UAS.TotalQuestions + UAS.TotalAnswers) DESC) AS TopActivityQuintile,
    AVG(COALESCE(UTSQM.AvgScoreHotTagQuestions, 0)) OVER (PARTITION BY (UBS.Reputation / 5000)) AS AvgHotTagScoreInReputationBand
FROM UserBaseStats AS UBS
LEFT JOIN UserActivitySummary AS UAS ON UBS.UserId = UAS.UserId
LEFT JOIN UserTagSpecificQuestionMetrics AS UTSQM ON UBS.UserId = UTSQM.UserId
LEFT JOIN PostHistoryEngagement AS PHE ON UBS.UserId = PHE.UserId
LEFT JOIN UserBadgeAchievements AS UBA ON UBS.UserId = UBA.UserId
LEFT JOIN UserAcceptedAnswerCount AS UAA ON UBS.UserId = UAA.UserId
LEFT JOIN UserLinkedPostActivity AS ULPA ON UBS.UserId = ULPA.UserId
WHERE
    (UAS.TotalPosts > 10 OR UTSQM.QuestionsInHotTags > 0) -- Filter out users with very little activity post-join
    AND UBS.DisplayName IS NOT NULL
ORDER BY OverallContributionScore DESC, UBS.Reputation DESC
LIMIT 500;
