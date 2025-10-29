-- {"query": "1443.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3366} 

WITH UserCoreMetrics AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Deleted User ' || U.Id) AS DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UpVotesGiven,
        U.DownVotes AS DownVotesGiven,
        COALESCE(U.Location, 'Unknown Location') AS Location,
        U.AboutMe,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.AnswerCount ELSE 0 END) AS TotalAnswersToOwnQuestions,
        AVG(EXTRACT(EPOCH FROM (NOW() - P.CreationDate)) / (3600 * 24 * 365.25)) FILTER (WHERE P.CreationDate IS NOT NULL) AS AvgPostAgeYears -- Average age of posts in years
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
        U.Views, U.UpVotes, U.DownVotes, U.Location, U.AboutMe
),
PostDetails AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount AS DirectCommentCount,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        LENGTH(P.Body) AS BodyLength,
        P.Body AS PostBodyText,
        COALESCE(P.AcceptedAnswerId, -1) AS AcceptedAnswerId_Ref,
        -- Correlated subquery to count distinct editors
        (SELECT COUNT(DISTINCT PH.UserId)
         FROM PostHistory AS PH
         WHERE PH.PostId = P.Id
           AND PH.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
           AND PH.UserId IS NOT NULL
        ) AS DistinctEditors,
        -- Correlated subquery to count total edit events
        (SELECT COUNT(PH.Id)
         FROM PostHistory AS PH
         WHERE PH.PostId = P.Id
           AND PH.PostHistoryTypeId IN (4, 5, 6)
        ) AS TotalEditEvents,
        -- Correlated subquery to get the latest close reason name
        (SELECT CR.Name
         FROM PostHistory AS PH_CLOSE
         LEFT JOIN CloseReasonTypes AS CR ON PH_CLOSE.Comment = CR.Id::varchar
         WHERE PH_CLOSE.PostId = P.Id
           AND PH_CLOSE.PostHistoryTypeId = 10 -- Post Closed
         ORDER BY PH_CLOSE.CreationDate DESC
         LIMIT 1
        ) AS LatestCloseReasonName,
        -- Correlated subquery to count linked posts
        (SELECT COUNT(PL.Id) FROM PostLinks AS PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 1) AS NumberOfLinkedPosts,
        -- Correlated subquery to count duplicate links
        (SELECT COUNT(PL.Id) FROM PostLinks AS PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3) AS NumberOfDuplicateLinks,
        -- Total votes received on this post
        COUNT(DISTINCT V.Id) AS TotalVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
    FROM Posts AS P
    LEFT JOIN Votes AS V ON P.Id = V.PostId
    GROUP BY
        P.Id, P.OwnerUserId, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.Title, P.Tags,
        P.AnswerCount, P.CommentCount, P.LastEditDate, P.LastActivityDate, P.ClosedDate, P.Body
),
PostRankedMetrics AS (
    SELECT
        PD.*,
        -- Window function: Rank posts by score within each user's contributions
        ROW_NUMBER() OVER (PARTITION BY PD.OwnerUserId ORDER BY PD.PostScore DESC, PD.PostViewCount DESC, PD.PostCreationDate DESC) AS UserPostRankByScoreViews,
        -- Window function: Calculate average score for posts of the same type by the user
        AVG(PD.PostScore) OVER (PARTITION BY PD.OwnerUserId, PD.PostTypeId) AS UserAvgPostTypeScore,
        -- Window function: NTILE for dividing posts into quartiles based on UpVotesReceived
        NTILE(4) OVER (ORDER BY PD.UpVotesReceived DESC) AS UpVoteQuartile,
        -- Window function: Running total of UpVotes received for the user's posts
        SUM(PD.UpVotesReceived) OVER (PARTITION BY PD.OwnerUserId ORDER BY PD.PostCreationDate) AS RunningUpVotesPerUser,
        -- Correlated subquery for body length change from initial version
        CASE
            WHEN (SELECT LENGTH(PH.Text) FROM PostHistory AS PH WHERE PH.PostId = PD.PostId AND PH.PostHistoryTypeId = 2 ORDER BY PH.CreationDate LIMIT 1) IS NOT NULL
            THEN PD.BodyLength - (SELECT LENGTH(PH.Text) FROM PostHistory AS PH WHERE PH.PostId = PD.PostId AND PH.PostHistoryTypeId = 2 ORDER BY PH.CreationDate LIMIT 1)
            ELSE NULL
        END AS BodyLengthChange
    FROM PostDetails AS PD
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        -- String aggregation for gold badge names
        STRING_AGG(DISTINCT B.Name, ', ' ORDER BY B.Name) FILTER (WHERE B.Class = 1) AS GoldBadgeNames,
        -- Check for specific "power tags" based on badge names (case-insensitive)
        MAX(CASE WHEN B.TagBased = TRUE AND LOWER(B.Name) IN ('sql', 'database', 'query', 'performance', 'postgresql', 'mysql') THEN 1 ELSE 0 END) AS HasSqlPerformanceBadges,
        MAX(CASE WHEN B.TagBased = TRUE AND LOWER(B.Name) IN ('python', 'javascript', 'java', 'c#', 'php', 'rust', 'go') THEN 1 ELSE 0 END) AS HasPopularLangBadges
    FROM Badges AS B
    GROUP BY B.UserId
),
-- Set operator example: Find users who have either created a highly-viewed question OR have a gold badge related to 'sql'
HighImpactUsers AS (
    SELECT DISTINCT UCM.UserId
    FROM UserCoreMetrics UCM
    JOIN PostRankedMetrics PRM ON UCM.UserId = PRM.OwnerUserId
    WHERE PRM.PostTypeId = 1 AND PRM.PostViewCount > 500000 -- Highly viewed questions threshold
    UNION
    SELECT DISTINCT UBS.UserId
    FROM UserBadgeSummary UBS
    WHERE UBS.GoldBadges > 0 AND UBS.HasSqlPerformanceBadges = 1 -- Gold badges in SQL performance
)
SELECT
    UCM.UserId,
    UCM.DisplayName,
    UCM.Reputation,
    UCM.UserCreationDate,
    UCM.LastAccessDate,
    UCM.Location,
    UCM.UserProfileViews,
    UCM.TotalPostsCreated,
    UCM.TotalQuestions,
    UCM.TotalAnswers,
    UCM.TotalCommentsMade,
    COALESCE(UBS.TotalBadges, 0) AS TotalBadgesAwarded,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadgesCount,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadgesCount,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadgesCount,
    COALESCE(UBS.HasSqlPerformanceBadges, 0) AS IsSQLPowerUser,
    COALESCE(UBS.HasPopularLangBadges, 0) AS IsPopularLangPowerUser,
    -- User's most impactful question (based on score/views)
    MAX(CASE WHEN PRM_Q.UserPostRankByScoreViews = 1 AND PRM_Q.PostTypeId = 1 THEN PRM_Q.PostId END) AS TopQuestionId,
    MAX(CASE WHEN PRM_Q.UserPostRankByScoreViews = 1 AND PRM_Q.PostTypeId = 1 THEN PRM_Q.Title END) AS TopQuestionTitle,
    MAX(CASE WHEN PRM_Q.UserPostRankByScoreViews = 1 AND PRM_Q.PostTypeId = 1 THEN PRM_Q.PostScore END) AS TopQuestionScore,
    MAX(CASE WHEN PRM_Q.UserPostRankByScoreViews = 1 AND PRM_Q.PostTypeId = 1 THEN PRM_Q.PostViewCount END) AS TopQuestionViews,
    -- User's most impactful answer
    MAX(CASE WHEN PRM_A.UserPostRankByScoreViews = 1 AND PRM_A.PostTypeId = 2 THEN PRM_A.PostId END) AS TopAnswerId,
    MAX(CASE WHEN PRM_A.UserPostRankByScoreViews = 1 AND PRM_A.PostTypeId = 2 THEN PRM_A.Title END) AS TopAnswerTitle,
    MAX(CASE WHEN PRM_A.UserPostRankByScoreViews = 1 AND PRM_A.PostTypeId = 2 THEN PRM_A.PostScore END) AS TopAnswerScore,
    -- Overall average upvotes received per post for the user
    AVG(PRM_ALL.UpVotesReceived) AS UserAvgUpVotesReceivedPerPost,
    -- Ratio of upvotes received on all posts vs. upvotes given by the user
    CASE
        WHEN UCM.UpVotesGiven > 0 THEN CAST(SUM(PRM_ALL.UpVotesReceived) AS NUMERIC) / UCM.UpVotesGiven
        ELSE NULL
    END AS UpVotesReceivedToGivenRatio,
    -- Check if user's location contains 'USA' or 'India' (case-insensitive)
    COALESCE(LOWER(UCM.Location) LIKE '%usa%' OR LOWER(UCM.Location) LIKE '%india%', FALSE) AS IsUS_IndiaUser,
    -- Average body length change for their posts, excluding NULL changes
    AVG(PRM_ALL.BodyLengthChange) FILTER (WHERE PRM_ALL.BodyLengthChange IS NOT NULL) AS AvgPostBodyLengthChange,
    -- Count posts that have been edited by more than 1 distinct user (excluding owner)
    SUM(CASE WHEN PRM_ALL.DistinctEditors > 1 THEN 1 ELSE 0 END) AS PostsWithMultipleEditors,
    -- Count of posts closed specifically due to 'Duplicate' reason
    SUM(CASE WHEN PRM_ALL.LatestCloseReasonName = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateClosedPostsCount,
    -- Average time between post creation and last activity (in days) for posts with activity
    AVG(EXTRACT(EPOCH FROM (PRM_ALL.LastActivityDate - PRM_ALL.PostCreationDate)) / (3600 * 24)) FILTER (WHERE PRM_ALL.LastActivityDate IS NOT NULL AND PRM_ALL.PostCreationDate IS NOT NULL) AS AvgPostActivityLagDays,
    -- Concatenated Gold badge names from UserBadgeSummary
    UBS.GoldBadgeNames,
    -- Boolean flag indicating if the user is considered a high-impact user
    (UCM.UserId IN (SELECT HighImpactUsers.UserId FROM HighImpactUsers)) AS IsHighImpactUser
FROM UserCoreMetrics AS UCM
LEFT JOIN UserBadgeSummary AS UBS ON UCM.UserId = UBS.UserId
LEFT JOIN PostRankedMetrics AS PRM_Q ON UCM.UserId = PRM_Q.OwnerUserId AND PRM_Q.PostTypeId = 1
LEFT JOIN PostRankedMetrics AS PRM_A ON UCM.UserId = PRM_A.OwnerUserId AND PRM_A.PostTypeId = 2
LEFT JOIN PostRankedMetrics AS PRM_ALL ON UCM.UserId = PRM_ALL.OwnerUserId
WHERE UCM.Reputation > 5000 -- Focus on more established users
  AND UCM.TotalPostsCreated >= 10 -- Users with substantial contribution
  AND (UCM.Location IS NULL OR (LOWER(UCM.Location) NOT LIKE '%test%' AND LOWER(UCM.Location) NOT LIKE '%bot%')) -- Filter out test/bot accounts
  AND LENGTH(COALESCE(UCM.AboutMe, '')) > 100 -- Users with a more substantial 'AboutMe' section
  AND UCM.UserId IN (
        SELECT DISTINCT OwnerUserId
        FROM PostRankedMetrics
        WHERE UpVoteQuartile = 1 -- At least one post in the top 25% by upvotes
    )
GROUP BY
    UCM.UserId, UCM.DisplayName, UCM.Reputation, UCM.UserCreationDate, UCM.LastAccessDate,
    UCM.Location, UCM.UserProfileViews, UCM.TotalPostsCreated, UCM.TotalQuestions,
    UCM.TotalAnswers, UCM.TotalCommentsMade, UBS.TotalBadges, UBS.GoldBadges,
    UBS.SilverBadges, UBS.BronzeBadges, UBS.HasSqlPerformanceBadges,
    UBS.HasPopularLangBadges, UCM.UpVotesGiven, UBS.GoldBadgeNames
ORDER BY UCM.Reputation DESC, UCM.TotalPostsCreated DESC, UBS.GoldBadges DESC
LIMIT 1000;
