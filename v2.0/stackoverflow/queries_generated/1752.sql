-- {"query": "1752.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3191} 
WITH UserMetrics AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        U.Views AS UserProfileViews,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(CASE WHEN B.Name = 'Fanatic' THEN 1 ELSE 0 END) AS HasFanaticBadge, -- Specific badge check
        -- NTILE window function to categorize users by reputation
        NTILE(4) OVER (ORDER BY U.Reputation DESC) AS ReputationQuartile,
        -- Scalar correlated subquery: average score of posts by users from the same location
        (
            SELECT AVG(Sp.Score)
            FROM Posts Sp
            JOIN Users Su ON Sp.OwnerUserId = Su.Id
            WHERE Su.Location = U.Location
              AND Sp.PostTypeId IN (1, 2)
              AND Sp.CreationDate BETWEEN U.CreationDate AND U.LastAccessDate
        ) AS AvgLocationPostScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location, U.Views, U.UpVotes, U.DownVotes
),
PostDetailedMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        COALESCE(P.ViewCount, 0) AS PostViewCount,
        COALESCE(P.AnswerCount, 0) AS PostAnswerCount,
        COALESCE(P.CommentCount, 0) AS PostCommentCount,
        COALESCE(P.FavoriteCount, 0) AS PostFavoriteCount,
        COALESCE(P.Title, SUBSTRING(P.Body, 1, 50) || '...') AS PostTitleExcerpt, -- String concatenation and substring
        P.Tags,
        P.LastActivityDate,
        P.ClosedDate,
        PT.Name AS PostTypeName,
        -- Calculate an "engagement score" with NULL logic and arithmetic
        (COALESCE(P.ViewCount, 0) * 0.1
         + COALESCE(P.Score, 0) * 1.5
         + COALESCE(P.AnswerCount, 0) * 5
         + COALESCE(P.CommentCount, 0) * 2
         + COALESCE(P.FavoriteCount, 0) * 10
         + CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 20 ELSE 0 END -- Bonus for accepted answer
        ) AS EngagementScore,
        -- Window function: Rank posts by engagement within each post type
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY (COALESCE(P.ViewCount, 0) + COALESCE(P.Score, 0) * 10) DESC) AS PostTypeEngagementRank,
        -- Window function: Running average score for a user's posts, ordered by creation date
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS RunningAvgUserPostScore,
        -- Window function: Score of the previous post by the same user
        LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PrevPostScore,
        -- Correlated subquery in SELECT: count of comments for this post that are positive
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = P.Id AND C.Score > 0) AS PositiveCommentsCount,
        -- Identify posts that have been closed and reopened based on history
        MAX(CASE WHEN PH_Close.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PH_Reopen.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        -- Complicated calculation: time from creation to last edit/activity in days, NULL if no activity
        NULLIF(
            EXTRACT(EPOCH FROM (COALESCE(P.LastEditDate, P.LastActivityDate) - P.CreationDate)) / (60 * 60 * 24),
            0
        ) AS DaysUntilLastActivityOrEdit,
        -- String expression: check if title contains "index" or "optimize"
        (CASE WHEN P.Title ILIKE '%index%' OR P.Title ILIKE '%optimize%' THEN 1 ELSE 0 END) AS IsPerformanceRelated,
        -- String expression: Count specific tags
        ARRAY_LENGTH(
            ARRAY(SELECT t FROM UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS t WHERE LOWER(t) IN ('sql', 'database', 'performance')),
            1
        ) AS SpecificTagCount,
        -- String expression: get the first tag as primary tag (if tags exist)
        NULLIF(
            (string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))[1],
            ''
        ) AS PrimaryTag
    FROM Posts P
    LEFT JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN PostHistory PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    LEFT JOIN PostHistory PH_Reopen ON P.Id = PH_Reopen.PostId AND PH_Reopen.PostHistoryTypeId = 11
    WHERE P.OwnerUserId IS NOT NULL -- Exclude community-owned posts if OwnerUserId is null
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Title, P.Body, P.Tags, P.LastActivityDate, P.ClosedDate, PT.Name, P.AcceptedAnswerId, P.LastEditDate
),
TagUsageStats AS (
    SELECT
        TagName,
        COUNT(DISTINCT P.Id) AS TaggedPostCount,
        AVG(P.Score) AS AvgScoreForTag,
        SUM(PD.EngagementScore) AS TotalEngagementForTag,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(P.Id) AS QuestionPercentageForTag
    FROM Posts P
    JOIN PostDetailedMetrics PD ON P.Id = PD.PostId
    LEFT JOIN LATERAL (SELECT UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS TagName) AS T ON TRUE
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 AND T.TagName IS NOT NULL
    GROUP BY T.TagName
    HAVING COUNT(DISTINCT P.Id) > 500
),
CommentActivitySummary AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalCommentsOnPost,
        SUM(C.Score) AS TotalCommentScoreOnPost,
        AVG(LENGTH(C.Text)) AS AvgCommentLength,
        SUM(CASE WHEN C.UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousCommentCount,
        MAX(C.CreationDate) AS LastCommentDate,
        -- Correlated subquery: check if any comment on this post mentions "thanks"
        (SELECT 1 FROM Comments SC WHERE SC.PostId = C.PostId AND SC.Text ILIKE '%thanks%' LIMIT 1) AS HasThanksComment
    FROM Comments C
    GROUP BY C.PostId
),
UsersWhoVoteAndPostButNeverComment AS (
    -- Set operator: Users who have posted AND voted, but never commented
    SELECT UserId FROM UserMetrics WHERE TotalPosts > 0
    INTERSECT
    SELECT UserId FROM (SELECT DISTINCT UserId FROM Votes WHERE UserId IS NOT NULL) AS VotedUsers
    EXCEPT
    SELECT UserId FROM UserMetrics WHERE TotalComments > 0
),
HotPostsToday AS (
    -- Using a window function with a time-based partition for "hotness" (simplified)
    SELECT
        PostId,
        PostTitleExcerpt,
        EngagementScore,
        ROW_NUMBER() OVER (ORDER BY EngagementScore DESC, PostCreationDate DESC) AS HotRank
    FROM PostDetailedMetrics
    WHERE PostCreationDate >= CURRENT_DATE - INTERVAL '7 day' -- Only recent posts
      AND PostTypeId = 1
)
-- Main query combining all CTEs with various joins and filters
SELECT
    UM.UserId,
    UM.DisplayName,
    UM.Reputation,
    UM.ReputationQuartile,
    UM.TotalPosts,
    UM.QuestionCount,
    UM.AnswerCount,
    UM.AvgLocationPostScore,
    UM.HasFanaticBadge,
    PDM.PostId,
    PDM.PostTypeName,
    PDM.PostTitleExcerpt,
    PDM.PostScore,
    PDM.EngagementScore,
    PDM.PostTypeEngagementRank,
    PDM.RunningAvgUserPostScore,
    PDM.PrevPostScore,
    PDM.PositiveCommentsCount,
    PDM.DaysUntilLastActivityOrEdit,
    PDM.WasClosed,
    PDM.WasReopened,
    PDM.IsPerformanceRelated,
    PDM.SpecificTagCount,
    CAS.TotalCommentsOnPost,
    CAS.TotalCommentScoreOnPost,
    CAS.AvgCommentLength,
    CAS.AnonymousCommentCount,
    CAS.HasThanksComment IS NOT NULL AS ContainsThanksComment, -- Boolean result from subquery
    TS.TagName AS TopDiscussedTag,
    TS.TaggedPostCount AS TopDiscussedTagPosts,
    TS.QuestionPercentageForTag,
    CASE
        WHEN UVAPNC.UserId IS NOT NULL THEN 'VotePostNoCommentUser'
        WHEN UM.QuestionCount > 0 AND UM.AnswerCount = 0 THEN 'QuestionOnlyUser'
        WHEN UM.TotalPosts = 0 AND UM.TotalComments > 0 THEN 'CommentOnlyUser'
        ELSE 'BalancedUser'
    END AS UserBehaviorCategory,
    -- Complex calculation: User-Post Influence Score
    (UM.Reputation * 0.01 + PDM.EngagementScore * 0.5 + COALESCE(TS.AvgScoreForTag, 0) * 0.1
     + (CASE WHEN PDM.WasClosed = 1 THEN -10 ELSE 0 END)
     + (CASE WHEN PDM.IsPerformanceRelated = 1 THEN 5 ELSE 0 END)
     + (PDM.SpecificTagCount * 2)
     + COALESCE(CAS.TotalCommentsOnPost, 0) * 0.5
     - (PDM.PostScore * 0.1 * PDM.PrevPostScore) -- Example of a volatile calculation
    ) AS UserPostInfluenceScore,
    -- NULL logic for DisplayName based on location
    NULLIF(UM.DisplayName, 'Community') AS ActualDisplayName,
    -- String expression: Uppercase first 5 chars of Post Title, or default
    UPPER(LEFT(COALESCE(PDM.PostTitleExcerpt, 'NO TITLE'), 5)) AS TitleFragment,
    -- Correlated EXISTS subquery in SELECT: check if post has any linked duplicates
    EXISTS (SELECT 1 FROM PostLinks PL WHERE PL.PostId = PDM.PostId AND PL.LinkTypeId = 3) AS HasDuplicateLinks,
    (SELECT TOP_HOT.HotRank FROM HotPostsToday TOP_HOT WHERE TOP_HOT.PostId = PDM.PostId LIMIT 1) AS HotPostRank
FROM UserMetrics UM
LEFT JOIN PostDetailedMetrics PDM ON UM.UserId = PDM.OwnerUserId
LEFT JOIN CommentActivitySummary CAS ON PDM.PostId = CAS.PostId
LEFT JOIN TagUsageStats TS ON PDM.PrimaryTag = TS.TagName
LEFT JOIN UsersWhoVoteAndPostButNeverComment UVAPNC ON UM.UserId = UVAPNC.UserId
WHERE UM.Reputation > 500 -- Filter for more active/established users
  AND PDM.PostId IS NOT NULL -- Only include rows that have a post associated
  AND PDM.PostCreationDate > UM.UserCreationDate + INTERVAL '30 days' -- Posts created after user has been active for a month
  AND PDM.EngagementScore > (SELECT AVG(EngagementScore) FROM PostDetailedMetrics) -- Only posts with above-average engagement
  AND NOT EXISTS (
      -- Correlated subquery in WHERE: Exclude posts that have been deleted permanently (PostHistoryTypeId = 12, latest entry)
      SELECT 1 FROM PostHistory PH_Del
      WHERE PH_Del.PostId = PDM.PostId
        AND PH_Del.PostHistoryTypeId = 12
        AND PH_Del.CreationDate = (SELECT MAX(PH_Inner.CreationDate) FROM PostHistory PH_Inner WHERE PH_Inner.PostId = PDM.PostId)
  )
ORDER BY UserPostInfluenceScore DESC, UM.Reputation DESC, PDM.EngagementScore DESC, PDM.DaysUntilLastActivityOrEdit ASC
LIMIT 10000;