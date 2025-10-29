-- {"query": "1677.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2695} 

WITH UserReputationTiers AS (
    -- CTE 1: Classify users into reputation tiers and calculate various user-centric metrics,
    -- including their activity summary and badge acquisition patterns.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        COALESCE(U.Location, 'Unspecified Location') AS UserLocation,
        CASE
            WHEN U.Reputation >= 100000 THEN 'Legendary Contributor'
            WHEN U.Reputation >= 20000 THEN 'Distinguished Expert'
            WHEN U.Reputation >= 5000 THEN 'Seasoned Pro'
            WHEN U.Reputation >= 1000 THEN 'Active Participant'
            WHEN U.Reputation >= 100 THEN 'Emerging Talent'
            ELSE 'Newcomer'
        END AS ReputationTier,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 2) AS AnswersPosted,
        COUNT(B.Id) AS TotalBadgesAwarded,
        MAX(B.Date) AS LastBadgeDate,
        MIN(B.Date) AS FirstBadgeDate,
        EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60 * 60 * 24 * 30) AS MonthsSinceCreation, -- Convert days to months
        LAG(U.Reputation, 1, 0) OVER (ORDER BY U.Reputation ASC, U.CreationDate ASC) AS PrevUserReputation, -- Window function: previous user's reputation
        DENSE_RANK() OVER (PARTITION BY COALESCE(U.Location, 'Unspecified Location') ORDER BY U.Reputation DESC, U.CreationDate ASC) AS RankInLocationByRep
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes, U.Location
),
PostEngagementSummary AS (
    -- CTE 2: Aggregate various engagement metrics for posts, including vote counts, comment analysis,
    -- and history details, ensuring robust NULL handling and complex aggregations.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.LastEditDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        COALESCE(P.AnswerCount, 0) AS AnswerCount, -- Handle NULL AnswerCount for non-questions
        COALESCE(P.CommentCount, 0) AS CommentCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        P.ClosedDate,
        COALESCE(P.Title, SUBSTRING(P.Body, 1, 75) || '...') AS DisplayTitle, -- String expression with NULL fallback
        REPLACE(REPLACE(REPLACE(P.Tags, '>', ''), '<', ','), ',,', ',') AS CleanedTags, -- String manipulation
        -- Correlated subquery to count distinct editors from post history
        (SELECT COUNT(DISTINCT PH.UserId)
         FROM PostHistory AS PH
         WHERE PH.PostId = P.Id
         AND PH.PostHistoryTypeId IN (4, 5, 6, 9)) AS DistinctEditorsOrRollbackers, -- Edit Title, Body, Tags, Rollback Tags
        -- Correlated subquery to determine if there's any accepted answer for the question
        EXISTS (SELECT 1 FROM Posts AS A WHERE A.Id = P.AcceptedAnswerId AND P.PostTypeId = 1) AS HasAcceptedAnswer,
        -- Aggregate vote counts using FILTER (similar to CASE WHEN for SUM)
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 2) AS UpVoteCount, -- UpMod
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 3) AS DownVoteCount, -- DownMod
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 1) AS AcceptedByOriginatorVoteCount,
        SUM(CASE WHEN V.VoteTypeId IN (2, 5) THEN 1 ELSE 0 END) AS TotalPositiveVotes,
        SUM(CASE WHEN V.VoteTypeId IN (3, 4, 10, 12) THEN 1 ELSE 0 END) AS TotalNegativeVotes,
        AVG(V.BountyAmount) FILTER (WHERE V.VoteTypeId = 9) AS AvgBountyAwarded, -- Average bounty only for BountyClose votes
        MAX(C.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT C.UserId) AS DistinctCommenters,
        AVG(C.Score) AS AverageCommentScore,
        MIN(C.Score) AS MinCommentScore,
        MAX(C.Score) AS MaxCommentScore
    FROM Posts AS P
    LEFT JOIN Votes AS V ON P.Id = V.PostId
    LEFT JOIN Comments AS C ON P.Id = C.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.LastActivityDate, P.LastEditDate,
        P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate,
        P.Title, P.Body, P.Tags, P.AcceptedAnswerId
),
PostLifecycleHistory AS (
    -- CTE 3: Analyze post history, focusing on closure reasons and migration details.
    -- Uses window functions to identify the most recent history event of certain types.
    SELECT
        PH.PostId,
        PH.CreationDate AS HistoryDate,
        PH.PostHistoryTypeId,
        PHT.Name AS HistoryTypeName,
        COALESCE(PH.Comment, 'No Comment') AS HistoryComment,
        FIRST_VALUE(PH.Text) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS LatestHistoryText,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS rn
    FROM PostHistory AS PH
    JOIN PostHistoryTypes AS PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.PostHistoryTypeId IN (10, 11, 17, 35, 36) -- Post Closed, Reopened, Migrated (old), Migrated Away, Migrated Here
)
SELECT
    URT.UserId,
    URT.DisplayName,
    URT.ReputationTier,
    URT.UserLocation,
    URT.QuestionsPosted,
    URT.AnswersPosted,
    PES.PostId,
    PES.DisplayTitle,
    PES.PostScore,
    PES.PostViewCount,
    PES.UpVoteCount,
    PES.DownVoteCount,
    PES.FavoriteCount,
    PES.CleanedTags,
    PLH.HistoryTypeName AS LastRelevantPostHistory,
    PLH.HistoryDate AS LastHistoryEventDate,
    PL.RelatedPostId AS LinkedDuplicatePostId,
    LT.Name AS LinkTypeDescription,
    -- Complex calculated fields with NULL logic and arithmetic operations
    (PES.UpVoteCount * 1.0 / NULLIF(PES.UpVoteCount + PES.DownVoteCount, 0)) AS UpvoteDownvoteRatio,
    (PES.PostScore * 1.0 / NULLIF(PES.PostViewCount, 0)) AS ScorePerView,
    (URT.AnswersPosted * 1.0 / NULLIF(URT.QuestionsPosted + URT.AnswersPosted, 0)) AS AnswererContributionRatio,
    CASE
        WHEN PES.ClosedDate IS NOT NULL THEN 'CLOSED'
        WHEN PES.HasAcceptedAnswer THEN 'ANSWERED_ACCEPTED'
        WHEN PES.AnswerCount > 0 THEN 'ANSWERED_PENDING_ACCEPTANCE'
        WHEN PES.CommentCount > 5 AND PES.PostViewCount > 500 THEN 'HIGH_INTERACTION_UNANSWERED'
        ELSE 'OPEN_AND_PENDING'
    END AS PostStatusDetail,
    -- Correlated subquery to check for specific badges associated with the user
    EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = URT.UserId AND B.Name = 'Disciplined' AND B.Class = 2) AS HasDisciplinedSilverBadge,
    -- Another correlated subquery to fetch the content of the highest scored comment on the post
    (SELECT C.Text FROM Comments C WHERE C.PostId = PES.PostId ORDER BY C.Score DESC, C.CreationDate DESC LIMIT 1) AS TopScoredCommentText,
    -- Window function: average score of posts by users in the same reputation tier
    AVG(PES.PostScore) OVER (PARTITION BY URT.ReputationTier) AS AvgPostScoreInTier,
    -- Window function: rolling sum of favorite counts for posts by the same user, ordered by creation date
    SUM(PES.FavoriteCount) OVER (PARTITION BY URT.UserId ORDER BY PES.PostCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeFavoritesByUser,
    -- String check for specific terms in post body (via Title excerpt)
    (PES.DisplayTitle ILIKE '%performance%' OR PES.DisplayTitle ILIKE '%optimization%') AS IsPerformanceRelated,
    URT.CreationDate AS UserCreationDate,
    PES.PostCreationDate AS PostCreatedDate,
    PES.LastActivityDate AS PostLastActivityDate
FROM UserReputationTiers AS URT
INNER JOIN PostEngagementSummary AS PES ON URT.UserId = PES.OwnerUserId
LEFT JOIN PostLifecycleHistory AS PLH ON PES.PostId = PLH.PostId AND PLH.rn = 1 -- Get only the latest history event for relevant types
LEFT JOIN PostLinks AS PL ON PES.PostId = PL.PostId AND PL.LinkTypeId = 3 -- Only duplicate links
LEFT JOIN LinkTypes AS LT ON PL.LinkTypeId = LT.Id
WHERE
    URT.Reputation >= 1000 -- Filter for established users
    AND PES.PostTypeId = 1 -- Focus primarily on Questions
    AND PES.PostViewCount > 5000 -- Popular questions
    AND PES.PostScore > 100 -- Highly upvoted questions
    AND PES.ClosedDate IS NULL -- Exclude closed questions
    AND PES.CreationDate > NOW() - INTERVAL '5 year' -- Recently active questions (within last 5 years)
    AND (
        (PES.CleanedTags LIKE '%<sql>%' OR PES.CleanedTags LIKE '%<database>%') -- Specific tags for focus
        OR
        (PES.DistinctEditorsOrRollbackers > 2 AND PES.AverageCommentScore > 2) -- Complex interaction pattern
    )
    AND NOT EXISTS (
        -- Correlated subquery: exclude posts that have been migrated away or deleted recently
        SELECT 1
        FROM PostHistory PH_EX
        WHERE PH_EX.PostId = PES.PostId
        AND PH_EX.PostHistoryTypeId IN (12, 35) -- Post Deleted, Post Migrated Away
        AND PH_EX.CreationDate > NOW() - INTERVAL '1 year'
    )
ORDER BY
    URT.Reputation DESC,
    PES.PostScore DESC,
    PES.LastActivityDate DESC
LIMIT 1000;
