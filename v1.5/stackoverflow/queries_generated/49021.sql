-- {"query": "49021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1958} 
WITH UserPostStats AS (
    -- Aggregate statistics for users regarding their posts, filtering for active contributors
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsPosted,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersPosted,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT P.Id) AS TotalPostsAuthored,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 AND P.Id = AcceptedAnswers.AcceptedAnswerId THEN P.Id END) AS AcceptedAnswersCount
    FROM Users AS U
    JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts AS AcceptedAnswers ON P.ParentId = AcceptedAnswers.Id AND AcceptedAnswers.PostTypeId = 1 -- Link answers to their parent questions to check for acceptance
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
    HAVING
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) >= 5 -- At least 5 questions
        AND COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) >= 10 -- At least 10 answers
),
UserBadgesSummary AS (
    -- Count gold, silver, and bronze badges for each user
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges
    FROM Badges AS B
    GROUP BY B.UserId
),
UserTopTags AS (
    -- Determine the top 3 most used tags by post count for each user's questions
    -- and calculate the average score of posts associated with these top tags.
    SELECT
        UserId,
        STRING_AGG(TagName, ', ') WITHIN GROUP (ORDER BY PostCount DESC) AS TopTags,
        AVG(TagPostScore) AS AverageTagPostScore
    FROM (
        SELECT
            P.OwnerUserId AS UserId,
            TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><'))) AS TagName,
            COUNT(P.Id) AS PostCount,
            AVG(P.Score) AS TagPostScore,
            ROW_NUMBER() OVER(PARTITION BY P.OwnerUserId ORDER BY COUNT(P.Id) DESC, AVG(P.Score) DESC) AS rn
        FROM Posts AS P
        WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 -- Ensure tags exist and are properly formatted
        GROUP BY P.OwnerUserId, TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><')))
    ) AS TaggedPostsSubquery
    WHERE rn <= 3
    GROUP BY UserId
),
PostHistoryMetrics AS (
    -- Calculate metrics related to post history, such as edit counts
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edit
        MAX(PH.CreationDate) AS LastHistoryActivityDate
    FROM PostHistory AS PH
    GROUP BY PH.PostId
),
RelatedPostScores AS (
    -- Aggregate scores from linked and duplicate posts for each post
    SELECT
        PL.PostId,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN RP.Score ELSE 0 END) AS LinkedPostScoreSum,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN RP.Score ELSE 0 END) AS DuplicatePostScoreSum,
        COUNT(DISTINCT PL.RelatedPostId) AS TotalRelatedPosts
    FROM PostLinks AS PL
    JOIN Posts AS RP ON PL.RelatedPostId = RP.Id
    GROUP BY PL.PostId
),
UserPostAggregates AS (
    -- Aggregate post-level metrics (history, related posts, comments) up to the user level
    SELECT
        P.OwnerUserId AS UserId,
        SUM(PHM.TotalHistoryEntries) AS TotalHistoryEntriesAcrossPosts,
        SUM(PHM.EditCount) AS TotalEditsAcrossPosts,
        MAX(PHM.LastHistoryActivityDate) AS LastPostHistoryActivityDate,
        SUM(RPS.LinkedPostScoreSum) AS OverallLinkedPostScore,
        SUM(RPS.DuplicatePostScoreSum) AS OverallDuplicatePostSum,
        SUM(RPS.TotalRelatedPosts) AS OverallRelatedPostsCount,
        SUM(P.CommentCount) AS TotalCommentsOnOwnPosts,
        MAX(P.LastActivityDate) AS LastUserPostActivity
    FROM Posts AS P
    LEFT JOIN PostHistoryMetrics AS PHM ON P.Id = PHM.PostId
    LEFT JOIN RelatedPostScores AS RPS ON P.Id = RPS.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
)
-- Main query: Combine all CTEs to generate a comprehensive user performance report
SELECT
    UPS.UserId,
    UPS.DisplayName,
    UPS.Reputation,
    UPS.UserCreationDate,
    UPS.LastAccessDate,
    UPS.QuestionsPosted,
    UPS.AnswersPosted,
    UPS.TotalPostsAuthored,
    UPS.AcceptedAnswersCount,
    CAST(UPS.TotalQuestionScore AS DECIMAL) / NULLIF(UPS.QuestionsPosted, 0) AS AvgQuestionScore,
    CAST(UPS.TotalAnswerScore AS DECIMAL) / NULLIF(UPS.AnswersPosted, 0) AS AvgAnswerScore,
    CAST(UPS.AcceptedAnswersCount AS DECIMAL) / NULLIF(UPS.AnswersPosted, 0) AS AcceptedAnswerRatio,
    BS.GoldBadges,
    BS.SilverBadges,
    BS.BronzeBadges,
    BS.TotalBadges,
    TT.TopTags,
    TT.AverageTagPostScore,
    UPA.LastUserPostActivity,
    UPA.TotalEditsAcrossPosts,
    UPA.TotalCommentsOnOwnPosts,
    UPA.OverallLinkedPostScore,
    UPA.OverallDuplicatePostSum,
    UPA.OverallRelatedPostsCount,
    COUNT(DISTINCT V_Given.Id) FILTER (WHERE V_Given.VoteTypeId = 2) AS TotalUpvotesGivenByUsers,
    COUNT(DISTINCT V_Given.Id) FILTER (WHERE V_Given.VoteTypeId = 3) AS TotalDownvotesGivenByUsers
FROM UserPostStats AS UPS
LEFT JOIN UserBadgesSummary AS BS ON UPS.UserId = BS.UserId
LEFT JOIN UserTopTags AS TT ON UPS.UserId = TT.UserId
LEFT JOIN UserPostAggregates AS UPA ON UPS.UserId = UPA.UserId
LEFT JOIN Votes AS V_Given ON UPS.UserId = V_Given.UserId AND V_Given.VoteTypeId IN (2, 3)
GROUP BY
    UPS.UserId, UPS.DisplayName, UPS.Reputation, UPS.UserCreationDate, UPS.LastAccessDate,
    UPS.QuestionsPosted, UPS.AnswersPosted, UPS.TotalPostsAuthored, UPS.AcceptedAnswersCount,
    UPS.TotalQuestionScore, UPS.TotalAnswerScore,
    BS.GoldBadges, BS.SilverBadges, BS.BronzeBadges, BS.TotalBadges,
    TT.TopTags, TT.AverageTagPostScore,
    UPA.LastUserPostActivity, UPA.TotalEditsAcrossPosts, UPA.TotalCommentsOnOwnPosts,
    UPA.OverallLinkedPostScore, UPA.OverallDuplicatePostSum, UPA.OverallRelatedPostsCount
ORDER BY
    UPS.Reputation DESC,
    UPS.LastAccessDate DESC
LIMIT 100;