-- {"query": "1208.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3979} 

WITH UserPostSummary AS (
    -- Aggregates various post-related metrics for each user
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostsScore,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(COALESCE(P.FavoriteCount, 0)) AS TotalFavoriteCountOnPosts,
        SUM(COALESCE(P.CommentCount, 0)) AS TotalCommentCountOnPosts,
        MAX(P.LastActivityDate) AS LatestPostActivity,
        MIN(P.CreationDate) AS EarliestPostCreation
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserCommentSummary AS (
    -- Aggregates comment-related metrics for each user
    SELECT
        C.UserId,
        COUNT(C.Id) AS TotalCommentsMade,
        SUM(C.Score) AS TotalCommentScore,
        MAX(C.CreationDate) AS LatestCommentActivity
    FROM Comments C
    WHERE C.UserId IS NOT NULL
    GROUP BY C.UserId
),
UserBadgeSummary AS (
    -- Counts badges by class for each user
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        COUNT(CASE WHEN B.TagBased = TRUE THEN B.Id END) AS TagBasedBadges
    FROM Badges B
    GROUP BY B.UserId
),
UserVoteSummary AS (
    -- Summarizes votes cast by users, including moderation-related votes
    SELECT
        V.UserId,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN V.Id END) AS UpVotesCast,
        COUNT(CASE WHEN V.VoteTypeId = 3 THEN V.Id END) AS DownVotesCast,
        COUNT(CASE WHEN V.VoteTypeId = 8 THEN V.Id END) AS BountyStarts,
        SUM(CASE WHEN V.VoteTypeId = 8 THEN COALESCE(V.BountyAmount, 0) ELSE 0 END) AS TotalBountyAmountStarted,
        COUNT(CASE WHEN V.VoteTypeId IN (6, 7, 10, 11, 12, 15) THEN V.Id END) AS ModerationActionVotes -- Close, Reopen, Delete, Undelete, Spam, ModeratorReview
    FROM Votes V
    WHERE V.UserId IS NOT NULL
    GROUP BY V.UserId
),
UserPostHistoryModeration AS (
    -- Tracks moderation-related actions from PostHistory
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalPostHistoryActions,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (10, 12, 14) THEN PH.Id END) AS NegativeModerationActions, -- Post Closed, Post Deleted, Post Locked
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (11, 13, 15) THEN PH.Id END) AS PositiveModerationActions -- Post Reopened, Post Undeleted, Post Unlocked
    FROM PostHistory PH
    WHERE PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
UserAcceptedAnswers AS (
    -- Counts accepted answers where the user provided the answer
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(P.Id) AS AcceptedAnswersProvided
    FROM Posts P
    WHERE P.PostTypeId = 2 -- Only answers
      AND P.Id = (SELECT Q.AcceptedAnswerId FROM Posts Q WHERE Q.AcceptedAnswerId = P.Id LIMIT 1) -- Is an accepted answer for some question
    GROUP BY P.OwnerUserId
),
UserTopTags AS (
    -- Identifies the most impactful tag for each user based on questions and score
    SELECT
        UserId,
        TagName AS TopInfluentialTag,
        QuestionsWithTag,
        TagScoreSum
    FROM (
        SELECT
            P.OwnerUserId AS UserId,
            T.TagName,
            COUNT(DISTINCT P.Id) AS QuestionsWithTag,
            SUM(P.Score) AS TagScoreSum,
            ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY COUNT(DISTINCT P.Id) DESC, SUM(P.Score) DESC) AS rn
        FROM Posts P
        JOIN Tags T ON P.Tags LIKE '%<' || T.TagName || '>%' -- String expression for tag matching
        WHERE P.PostTypeId = 1 AND P.OwnerUserId IS NOT NULL AND P.Tags IS NOT NULL
        GROUP BY P.OwnerUserId, T.TagName
    ) AS RankedTags
    WHERE rn = 1
),
CombinedUserMetrics AS (
    -- Joins all user-related CTEs and adds base user data and derived metrics
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        EXTRACT(DAY FROM (NOW() - U.CreationDate)) AS AccountAgeDays,
        COALESCE(UPS.TotalPosts, 0) AS TotalPosts,
        COALESCE(UPS.TotalQuestions, 0) AS TotalQuestions,
        COALESCE(UPS.TotalAnswers, 0) AS TotalAnswers,
        COALESCE(UPS.TotalPostsScore, 0) AS TotalPostsScore,
        COALESCE(UPS.TotalQuestionViews, 0) AS TotalQuestionViews,
        COALESCE(UPS.TotalFavoriteCountOnPosts, 0) AS TotalFavoriteCountOnPosts,
        COALESCE(UPS.TotalCommentCountOnPosts, 0) AS TotalCommentCountOnPosts,
        COALESCE(UCS.TotalCommentsMade, 0) AS TotalCommentsMade,
        COALESCE(UCS.TotalCommentScore, 0) AS TotalCommentScore,
        COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
        COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
        COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(UVS.UpVotesCast, 0) AS UpVotesCast,
        COALESCE(UVS.DownVotesCast, 0) AS DownVotesCast,
        COALESCE(UVS.BountyStarts, 0) AS BountyStarts,
        COALESCE(UVS.TotalBountyAmountStarted, 0) AS TotalBountyAmountStarted,
        COALESCE(UPHM.NegativeModerationActions, 0) AS NegativeModerationActions,
        COALESCE(UPHM.PositiveModerationActions, 0) AS PositiveModerationActions,
        COALESCE(UAA.AcceptedAnswersProvided, 0) AS AcceptedAnswersProvided,
        COALESCE(UTT.TopInfluentialTag, 'No Top Tag') AS MostInfluentialTag,
        COALESCE(UTT.QuestionsWithTag, 0) AS QuestionsWithMostInfluentialTag,
        COALESCE(UTT.TagScoreSum, 0) AS MostInfluentialTagScoreSum,
        -- Correlated subquery: Average score of posts created in the first 30 days of the user's account
        (
            SELECT COALESCE(AVG(P_early.Score * 1.0), 0)
            FROM Posts P_early
            WHERE P_early.OwnerUserId = U.Id
              AND P_early.CreationDate BETWEEN U.CreationDate AND (U.CreationDate + INTERVAL '30 days')
        ) AS AvgScoreFirstMonth,
        U.WebsiteUrl,
        U.Location,
        U.AboutMe,
        -- Check if user's display name or about me contains a common spam pattern (example)
        CASE
            WHEN LOWER(U.DisplayName) LIKE '%free%' OR LOWER(U.DisplayName) LIKE '%coupon%' OR
                 (U.AboutMe IS NOT NULL AND LOWER(U.AboutMe) LIKE '%http%' AND LENGTH(U.AboutMe) < 50)
            THEN TRUE ELSE FALSE
        END AS PotentiallySpammyProfile
    FROM Users U
    LEFT JOIN UserPostSummary UPS ON U.Id = UPS.UserId
    LEFT JOIN UserCommentSummary UCS ON U.Id = UCS.UserId
    LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
    LEFT JOIN UserVoteSummary UVS ON U.Id = UVS.UserId
    LEFT JOIN UserPostHistoryModeration UPHM ON U.Id = UPHM.UserId
    LEFT JOIN UserAcceptedAnswers UAA ON U.Id = UAA.UserId
    LEFT JOIN UserTopTags UTT ON U.Id = UTT.UserId
    WHERE U.Reputation >= 100 -- Filter out very inactive users early
      AND U.CreationDate <= NOW() - INTERVAL '30 days' -- Ensure minimum account age for meaningful stats
)
SELECT
    CUM.UserId,
    CUM.DisplayName,
    CUM.Reputation,
    CUM.AccountAgeDays,
    CUM.TotalPosts,
    CUM.TotalQuestions,
    CUM.TotalAnswers,
    CUM.TotalPostsScore,
    CUM.TotalQuestionViews,
    CUM.TotalFavoriteCountOnPosts,
    CUM.TotalCommentsMade,
    CUM.TotalCommentScore,
    CUM.GoldBadges,
    CUM.SilverBadges,
    CUM.BronzeBadges,
    CUM.UpVotesCast,
    CUM.DownVotesCast,
    CUM.BountyStarts,
    CUM.TotalBountyAmountStarted,
    CUM.NegativeModerationActions,
    CUM.PositiveModerationActions,
    CUM.AcceptedAnswersProvided,
    CUM.MostInfluentialTag,
    CUM.QuestionsWithMostInfluentialTag,
    CUM.MostInfluentialTagScoreSum,
    CUM.AvgScoreFirstMonth,
    CUM.PotentiallySpammyProfile,
    -- Complicated calculation for a composite 'UserInfluenceScore' using weighted factors, COALESCE for NULLs, and CASE expressions
    CAST(
        (CUM.Reputation * 0.4) +
        (COALESCE(CUM.TotalPostsScore, 0) * 0.15) +
        (COALESCE(CUM.TotalQuestionViews, 0) * 0.0005) +
        (COALESCE(CUM.AcceptedAnswersProvided, 0) * 12) +
        (COALESCE(CUM.TotalCommentsMade, 0) * 0.4) +
        (COALESCE(CUM.GoldBadges, 0) * 25) +
        (COALESCE(CUM.SilverBadges, 0) * 15) +
        (COALESCE(CUM.BronzeBadges, 0) * 3) +
        (COALESCE(CUM.UpVotesCast, 0) * 0.08) -
        (COALESCE(CUM.DownVotesCast, 0) * 0.15) +
        (COALESCE(CUM.NegativeModerationActions, 0) * -7) + -- Penalize negative moderation actions
        (COALESCE(CUM.PositiveModerationActions, 0) * 8) +  -- Reward positive moderation actions
        (COALESCE(CUM.AvgScoreFirstMonth, 0) * 2.0) +
        (CASE WHEN CUM.WebsiteUrl IS NOT NULL AND LENGTH(TRIM(CUM.WebsiteUrl)) > 5 THEN 40 ELSE 0 END) + -- Bonus for having a valid-looking website
        (CASE WHEN CUM.AboutMe IS NOT NULL AND LENGTH(CUM.AboutMe) > 150 THEN 25 ELSE 0 END) + -- Bonus for descriptive AboutMe
        (COALESCE(CUM.QuestionsWithMostInfluentialTag, 0) * 0.7) +
        (COALESCE(CUM.MostInfluentialTagScoreSum, 0) * 0.12) -
        (CASE WHEN CUM.PotentiallySpammyProfile THEN 100 ELSE 0 END) -- Penalty for potentially spammy profiles
    AS BIGINT) AS UserInfluenceScore,
    -- Window function: Rank users by their calculated influence score
    RANK() OVER (ORDER BY (
        (CUM.Reputation * 0.4) +
        (COALESCE(CUM.TotalPostsScore, 0) * 0.15) +
        (COALESCE(CUM.TotalQuestionViews, 0) * 0.0005) +
        (COALESCE(CUM.AcceptedAnswersProvided, 0) * 12) +
        (COALESCE(CUM.TotalCommentsMade, 0) * 0.4) +
        (COALESCE(CUM.GoldBadges, 0) * 25) +
        (COALESCE(CUM.SilverBadges, 0) * 15) +
        (COALESCE(CUM.BronzeBadges, 0) * 3) +
        (COALESCE(CUM.UpVotesCast, 0) * 0.08) -
        (COALESCE(CUM.DownVotesCast, 0) * 0.15) +
        (COALESCE(CUM.NegativeModerationActions, 0) * -7) +
        (COALESCE(CUM.PositiveModerationActions, 0) * 8) +
        (COALESCE(CUM.AvgScoreFirstMonth, 0) * 2.0) +
        (CASE WHEN CUM.WebsiteUrl IS NOT NULL AND LENGTH(TRIM(CUM.WebsiteUrl)) > 5 THEN 40 ELSE 0 END) +
        (CASE WHEN CUM.AboutMe IS NOT NULL AND LENGTH(CUM.AboutMe) > 150 THEN 25 ELSE 0 END) +
        (COALESCE(CUM.QuestionsWithMostInfluentialTag, 0) * 0.7) +
        (COALESCE(CUM.MostInfluentialTagScoreSum, 0) * 0.12) -
        (CASE WHEN CUM.PotentiallySpammyProfile THEN 100 ELSE 0 END)
    ) DESC) AS OverallInfluenceRank,
    -- Window function: Calculate the average posts score for users based on their account creation year
    AVG(CASE WHEN CUM.TotalPosts > 0 THEN CUM.TotalPostsScore * 1.0 / CUM.TotalPosts ELSE 0 END)
        OVER (PARTITION BY EXTRACT(YEAR FROM CUM.UserCreationDate)) AS AvgUserPostScoreForCreationYear,
    -- String expression and NULL logic for a truncated location preview
    CASE
        WHEN CUM.Location IS NOT NULL AND LENGTH(TRIM(CUM.Location)) > 0
            THEN SUBSTRING(TRIM(CUM.Location), 1, LEAST(LENGTH(TRIM(CUM.Location)), 30)) ||
                 CASE WHEN LENGTH(TRIM(CUM.Location)) > 30 THEN '...' ELSE '' END
        ELSE 'Location Not Provided'
    END AS FormattedLocationPreview,
    -- Nested correlated subquery: Check if the user has ever edited a post containing specific keywords related to documentation
    EXISTS (
        SELECT 1
        FROM PostHistory PH_inner
        JOIN Posts P_inner ON PH_inner.PostId = P_inner.Id
        WHERE PH_inner.UserId = CUM.UserId
          AND PH_inner.PostHistoryTypeId IN (5, 8) -- Edit Body, Rollback Body
          AND (LOWER(P_inner.Body) LIKE '%documentation%' OR LOWER(P_inner.Body) LIKE '%tutorial%')
        LIMIT 1
    ) AS HasEditedForDocumentation,
    -- Correlated subquery: Calculates the average score of all posts linked to by questions owned by this user
    (
        SELECT COALESCE(AVG(LP.Score * 1.0), 0)
        FROM Posts P_owner
        JOIN PostLinks PL ON P_owner.Id = PL.PostId
        JOIN Posts LP ON PL.RelatedPostId = LP.Id
        WHERE P_owner.OwnerUserId = CUM.UserId
          AND P_owner.PostTypeId = 1 -- Only consider links from questions
          AND PL.LinkTypeId = 1 -- Only 'Linked' type
    ) AS AvgScoreOfLinkedPosts
FROM CombinedUserMetrics CUM
WHERE CUM.TotalPosts > 0 OR CUM.TotalCommentsMade > 0 OR CUM.GoldBadges > 0 -- Ensure user has some activity
ORDER BY UserInfluenceScore DESC, CUM.UserId
LIMIT 2000;
