-- {"query": "1874.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3415} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(EXTRACT(DAY FROM (U.LastAccessDate - U.CreationDate)), 0) AS UserAgeDays,
        COALESCE(EXTRACT(DAY FROM (CURRENT_TIMESTAMP - U.LastAccessDate)), 0) AS DaysSinceLastAccess,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(AVG(P.Score), 0.0) AS AvgPostScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesGiven,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesGiven,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostDetailsExtended AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.ViewCount,
        P.Score,
        P.AnswerCount,
        P.CommentCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        P.ClosedDate,
        P.Title,
        COALESCE(EXTRACT(DAY FROM (CURRENT_TIMESTAMP - P.CreationDate)), 0) AS PostAgeDays,
        COALESCE(ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><'), 1), 0) AS NumberOfTags,
        COALESCE(SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END), 0) AS EditCount, -- Title, Body, Tags edits
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        MAX(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS WasDeleted,
        COUNT(DISTINCT PL_Linked.RelatedPostId) AS LinkedFromOtherPostsCount,
        COUNT(DISTINCT PL_Duplicate.RelatedPostId) AS DuplicateOfOtherPostsCount
    FROM Posts P
    INNER JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN Users U ON P.OwnerUserId = U.Id
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN PostLinks PL_Linked ON P.Id = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1
    LEFT JOIN PostLinks PL_Duplicate ON P.Id = PL_Duplicate.RelatedPostId AND PL_Duplicate.LinkTypeId = 3
    GROUP BY
        P.Id, P.PostTypeId, PT.Name, P.OwnerUserId, U.DisplayName, P.CreationDate, P.LastActivityDate, P.ViewCount, P.Score,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.Title, P.Tags
),
UserTagContributions AS (
    SELECT
        P.OwnerUserId AS UserId,
        TRIM(unnest(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><'))) AS TagName,
        COUNT(P.Id) AS PostsInTag,
        COALESCE(SUM(P.Score), 0) AS ScoreInTag,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1) AS QuestionsInTag,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 2) AS AnswersInTag
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL AND P.Tags IS NOT NULL AND P.Tags != ''
    GROUP BY P.OwnerUserId, TRIM(unnest(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><')))
),
AggregatedTagRanking AS (
    SELECT
        UTC.UserId,
        UTC.TagName,
        UTC.PostsInTag,
        UTC.ScoreInTag,
        RANK() OVER (PARTITION BY UTC.TagName ORDER BY UTC.ScoreInTag DESC, UTC.PostsInTag DESC) AS TagRankByScore,
        NTILE(5) OVER (PARTITION BY UTC.TagName ORDER BY UTC.PostsInTag DESC) AS TagPostVolumeQuintile
    FROM UserTagContributions UTC
),
TopTagsPerUser AS (
    SELECT
        ATR.UserId,
        STRING_AGG(ATR.TagName || ' (' || ATR.PostsInTag || ')', ', ') FILTER (WHERE ATR.TagRankByScore <= 3) AS Top3TagsContributions
    FROM AggregatedTagRanking ATR
    WHERE ATR.TagRankByScore <= 3 -- Only consider top 3 tags by score for each user
    GROUP BY ATR.UserId
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserCreationDate,
    UAS.LastAccessDate,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalPostScore,
    UAS.AvgPostScore,
    UAS.TotalComments,
    UAS.TotalCommentScore,
    UAS.UpVotesGiven,
    UAS.DownVotesGiven,
    UAS.TotalBadges,
    UAS.GoldBadges,
    UAS.SilverBadges,
    UAS.BronzeBadges,
    TTPU.Top3TagsContributions,
    -- User influence score calculation
    CAST(UAS.Reputation AS NUMERIC) / 100.0 +
    (UAS.TotalPostScore * 0.5) +
    (UAS.GoldBadges * 10) +
    (UAS.SilverBadges * 5) +
    (UAS.BronzeBadges * 1) +
    (UAS.AvgPostScore * 2) +
    (UAS.TotalComments * 0.1) -
    (UAS.DaysSinceLastAccess * 0.01) AS UserInfluenceScore,

    -- Window Function: Rank users by influence
    RANK() OVER (ORDER BY
        CAST(UAS.Reputation AS NUMERIC) / 100.0 +
        (UAS.TotalPostScore * 0.5) +
        (UAS.GoldBadges * 10) +
        (UAS.SilverBadges * 5) +
        (UAS.BronzeBadges * 1) +
        (UAS.AvgPostScore * 2) +
        (UAS.TotalComments * 0.1) -
        (UAS.DaysSinceLastAccess * 0.01) DESC,
        UAS.UserId
    ) AS OverallInfluenceRank,

    -- Window Function: NTILE for reputation decile
    NTILE(10) OVER (ORDER BY UAS.Reputation DESC) AS ReputationDecile,

    -- Correlated Subquery 1: Check if user has an accepted answer to a question by a highly reputable user
    EXISTS (
        SELECT 1
        FROM Posts P_inner
        JOIN Posts Q_inner ON P_inner.ParentId = Q_inner.Id
        JOIN Users U_q_inner ON Q_inner.OwnerUserId = U_q_inner.Id
        WHERE P_inner.OwnerUserId = UAS.UserId
          AND P_inner.Id = Q_inner.AcceptedAnswerId -- This answer was accepted
          AND Q_inner.PostTypeId = 1 -- It's an answer to a question
          AND U_q_inner.Reputation > 10000 -- Question owner is highly reputable
          AND P_inner.CreationDate > (UAS.UserCreationDate + INTERVAL '1 year') -- Accepted answer provided after 1 year of user's existence
    ) AS HasAcceptedAnswerFromHighReputationQ,

    -- Correlated Subquery 2: Count of their questions that are highly viewed AND have at least 5 answers
    (
        SELECT COUNT(P_q_inner.Id)
        FROM Posts P_q_inner
        WHERE P_q_inner.OwnerUserId = UAS.UserId
          AND P_q_inner.PostTypeId = 1 -- Is a question
          AND P_q_inner.ViewCount > 5000 -- Highly viewed
          AND P_q_inner.AnswerCount >= 5 -- Has sufficient answers
          AND NOT EXISTS (
              SELECT 1 FROM PostHistory PH_close WHERE PH_close.PostId = P_q_inner.Id AND PH_close.PostHistoryTypeId = 10 -- Not closed
          )
    ) AS HighEngagementQuestionCount,

    -- Complicated Expression/Predicate using NULL logic and string operations
    COALESCE(UAS.DisplayName, 'Anonymous') ||
    CASE
        WHEN UAS.Reputation > 10000 AND UAS.TotalBadges > 50 THEN ' (Guru)'
        WHEN UAS.Reputation > 5000 AND UAS.GoldBadges > 0 THEN ' (Expert)'
        WHEN UAS.TotalPosts > 100 AND UAS.AvgPostScore > 5 THEN ' (Contributor)'
        ELSE ''
    END AS UserTitleComputed,

    -- Average time between post creation and its last activity (for their own posts)
    (
        SELECT AVG(EXTRACT(HOUR FROM (PDE.LastActivityDate - PDE.PostCreationDate)))
        FROM PostDetailsExtended PDE
        WHERE PDE.OwnerUserId = UAS.UserId AND PDE.PostCreationDate IS NOT NULL AND PDE.LastActivityDate IS NOT NULL
        AND PDE.PostTypeId IN (1,2)
    ) AS AvgPostActivityTimeHours,

    -- Post Metrics for their highest scored question
    (
        SELECT P_max.ViewCount
        FROM PostDetailsExtended P_max
        WHERE P_max.OwnerUserId = UAS.UserId
          AND P_max.PostTypeId = 1
        ORDER BY P_max.Score DESC, P_max.ViewCount DESC
        LIMIT 1
    ) AS HighestScoredQuestionViewCount,
    (
        SELECT P_max.EditCount
        FROM PostDetailsExtended P_max
        WHERE P_max.OwnerUserId = UAS.UserId
          AND P_max.PostTypeId = 1
        ORDER BY P_max.Score DESC, P_max.ViewCount DESC
        LIMIT 1
    ) AS HighestScoredQuestionEditCount

FROM UserActivitySummary UAS
LEFT JOIN TopTagsPerUser TTPU ON UAS.UserId = TTPU.UserId
WHERE
    UAS.Reputation > 100
    AND (UAS.TotalPosts > 5 OR UAS.TotalComments > 10)
    AND UAS.DaysSinceLastAccess < 365 -- Active in the last year
    AND (
        UAS.DisplayName LIKE 'A%' OR UAS.DisplayName LIKE 'J%' OR UAS.DisplayName IS NULL
    )
    -- Set Operator: Union with another set of users for complexity:
UNION ALL
SELECT
    UAS_alt.UserId,
    UAS_alt.DisplayName,
    UAS_alt.Reputation,
    UAS_alt.UserCreationDate,
    UAS_alt.LastAccessDate,
    UAS_alt.TotalPosts,
    UAS_alt.TotalQuestions,
    UAS_alt.TotalAnswers,
    UAS_alt.TotalPostScore,
    UAS_alt.AvgPostScore,
    UAS_alt.TotalComments,
    UAS_alt.TotalCommentScore,
    UAS_alt.UpVotesGiven,
    UAS_alt.DownVotesGiven,
    UAS_alt.TotalBadges,
    UAS_alt.GoldBadges,
    UAS_alt.SilverBadges,
    UAS_alt.BronzeBadges,
    NULL AS Top3TagsContributions, -- No specific tag contributions for this set
    -- Simplified influence score for this set
    CAST(UAS_alt.Reputation AS NUMERIC) / 200.0 +
    (UAS_alt.TotalBadges * 5) AS UserInfluenceScore,
    NULL AS OverallInfluenceRank, -- Not ranked in this specific UNION branch
    NULL AS ReputationDecile,
    FALSE AS HasAcceptedAnswerFromHighReputationQ,
    0 AS HighEngagementQuestionCount,
    'Legacy User' AS UserTitleComputed,
    NULL AS AvgPostActivityTimeHours,
    NULL AS HighestScoredQuestionViewCount,
    NULL AS HighestScoredQuestionEditCount
FROM UserActivitySummary UAS_alt
WHERE
    UAS_alt.Reputation BETWEEN 50 AND 1000
    AND UAS_alt.TotalPosts = 0
    AND UAS_alt.TotalComments > 0
    AND UAS_alt.UserAgeDays > (365 * 5) -- User is at least 5 years old
    AND EXISTS (
        SELECT 1 FROM Comments C_inner WHERE C_inner.UserId = UAS_alt.UserId
        AND C_inner.Text ILIKE '%bug%'
        AND C_inner.Score > 0
    )
ORDER BY UserInfluenceScore DESC, Reputation DESC
LIMIT 500;
