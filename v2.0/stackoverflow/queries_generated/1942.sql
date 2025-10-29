-- {"query": "1942.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3134} 

WITH UserActivityMetrics AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT C.Id) AS CommentCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived, -- Upvotes on their posts
        SUM(CASE WHEN VP.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven, -- Upvotes given by user
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 2) AS SilverBadges,
        MAX(P.CreationDate) AS LatestPostDate,
        MIN(P.CreationDate) AS EarliestPostDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Votes AS V ON P.Id = V.PostId AND V.VoteTypeId IN (1, 2) -- AcceptedAnswerByOriginator, UpMod
    LEFT JOIN Votes AS VP ON U.Id = VP.UserId AND VP.VoteTypeId IN (2, 3, 5) -- UpMod, DownMod, Favorite given by user
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostHistoryAggregated AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS EditCount, -- Title, Body, Tags edits
        MAX(PH.CreationDate) AS LastHistoryDate,
        -- Correlated subquery to calculate the average time between *any* two consecutive history events for a post
        (
            SELECT AVG(EXTRACT(EPOCH FROM (current_ph.CreationDate - prev_ph.CreationDate)))
            FROM (
                SELECT
                    ph_inner.CreationDate,
                    LAG(ph_inner.CreationDate) OVER (PARTITION BY ph_inner.PostId ORDER BY ph_inner.CreationDate) AS PrevCreationDate
                FROM PostHistory ph_inner
                WHERE ph_inner.PostId = PH.PostId
            ) AS current_ph (CreationDate, PrevCreationDate)
            WHERE PrevCreationDate IS NOT NULL
        ) AS AvgTimeBetweenHistoryEventsSeconds,
        -- Flag if post was closed and then reopened
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        -- Correlated subquery: Does this post have any history entry where the comment mentions 'moderator'?
        EXISTS (
            SELECT 1 FROM PostHistory ph_mod
            WHERE ph_mod.PostId = PH.PostId AND ph_mod.Comment ILIKE '%moderator%'
        ) AS HasModeratorCommentHistory
    FROM PostHistory AS PH
    GROUP BY PH.PostId
),
ComplexPostAttributes AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS DirectCommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.Tags,
        -- Complicated calculation for CompositeEngagementScore
        COALESCE(P.ViewCount, 0) + COALESCE(P.Score * 10, 0) + COALESCE(P.CommentCount * 5, 0) + COALESCE(P.FavoriteCount * 20, 0) AS CompositeEngagementScore,
        LENGTH(P.Body) AS BodyLength,
        COUNT(DISTINCT C.Id) AS TotalCommentsOnPost,
        AVG(C.Score) AS AvgCommentScore,
        COUNT(DISTINCT PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 1) AS LinkedPostsCount,
        COUNT(DISTINCT PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 3) AS DuplicatePostsCount,
        -- String expression and NULL handling for Tags
        NULLIF(TRIM(LOWER(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2))), '') AS ParsedTagsString,
        CASE
            WHEN P.Tags LIKE '%<sql>%' OR P.Tags LIKE '%<database>%' OR P.Tags LIKE '%<performance>%' OR P.Tags LIKE '%<query-optimization>%' THEN TRUE
            ELSE FALSE
        END AS IsDatabaseRelated,
        -- Correlated subquery: check if post has any comment from a user with > 1000 reputation
        EXISTS (
            SELECT 1 FROM Comments sc JOIN Users su ON sc.UserId = su.Id
            WHERE sc.PostId = P.Id AND su.Reputation > 1000
        ) AS HasHighRepCommenter,
        -- String expression: Check if post's title contains specific keywords (case-insensitive)
        (P.Title ILIKE '%performance%' OR P.Title ILIKE '%optimization%' OR P.Title ILIKE '%benchmark%' OR P.Title ILIKE '%speed%') AS TitleIndicatesPerformance,
        -- Correlated subquery: Average score of comments for posts by the same owner in the last year relative to this post's creation
        (
            SELECT COALESCE(AVG(sc_inner.Score), 0)
            FROM Comments sc_inner
            JOIN Posts p_inner ON sc_inner.PostId = p_inner.Id
            WHERE p_inner.OwnerUserId = P.OwnerUserId
              AND p_inner.CreationDate >= P.CreationDate - INTERVAL '1 year'
              AND p_inner.CreationDate <= P.CreationDate
        ) AS AvgOwnerCommentScoreLastYear
    FROM Posts AS P
    LEFT JOIN Comments AS C ON P.Id = C.PostId
    LEFT JOIN PostLinks AS PL ON P.Id = PL.PostId
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.Tags, P.Body, P.Title
),
TopPerformingEntities AS (
    SELECT
        UAM.UserId,
        UAM.DisplayName,
        UAM.Reputation,
        UAM.QuestionCount,
        UAM.AnswerCount,
        UAM.TotalUpvotesReceived,
        CPA.PostId,
        CPA.PostTypeId,
        CPA.Score AS PostScore,
        CPA.ViewCount AS PostViewCount,
        CPA.BodyLength,
        CPA.CompositeEngagementScore,
        PHA.EditCount,
        PHA.AvgTimeBetweenHistoryEventsSeconds,
        CPA.IsDatabaseRelated,
        CPA.TitleIndicatesPerformance,
        PHA.HasModeratorCommentHistory,
        -- Window functions for ranking
        RANK() OVER (PARTITION BY CPA.PostTypeId ORDER BY CPA.CompositeEngagementScore DESC, PHA.EditCount DESC) AS RankByEngagementAndEdits,
        NTILE(10) OVER (ORDER BY UAM.Reputation DESC, UAM.TotalUpvotesReceived DESC) AS ReputationTier,
        SUM(CPA.Score) OVER (PARTITION BY UAM.UserId ORDER BY CPA.PostCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeUserScore,
        -- NULL logic and complex calculations for reputation per day
        (CAST(UAM.Reputation AS numeric) / NULLIF(EXTRACT(DAY FROM AGE(CURRENT_TIMESTAMP, UAM.UserCreationDate)), 0)) AS ReputationPerDay,
        COALESCE(UAM.GoldBadges * 100 + UAM.SilverBadges * 50, 0) AS BadgeValueScore,
        -- String expression and UNNEST for distinct tag count
        (SELECT COUNT(DISTINCT T.TagName) FROM UNNEST(string_to_array(SUBSTRING(CPA.Tags, 2, LENGTH(CPA.Tags) - 2), '><')) AS T(TagName)) AS DistinctTagsCount,
        -- Correlated subquery: Check if a user has any Gold badge created after their earliest post
        EXISTS (
            SELECT 1 FROM Badges b_inner
            WHERE b_inner.UserId = UAM.UserId
              AND b_inner.Class = 1
              AND b_inner.Date > UAM.EarliestPostDate
        ) AS HasLateGoldBadge
    FROM UserActivityMetrics AS UAM
    LEFT JOIN ComplexPostAttributes AS CPA ON UAM.UserId = CPA.OwnerUserId
    LEFT JOIN PostHistoryAggregated AS PHA ON CPA.PostId = PHA.PostId
    WHERE
        UAM.Reputation > (SELECT COALESCE(AVG(Reputation), 0) * 5 FROM Users WHERE Id IS NOT NULL) -- Non-correlated subquery for global threshold
        AND CPA.PostTypeId IN (1, 2) -- Only questions and answers
        AND (CPA.BodyLength > 500 OR CPA.TotalCommentsOnPost > 10 OR CPA.AvgOwnerCommentScoreLastYear > 5) -- Complicated predicate
        AND CPA.PostCreationDate >= '2020-01-01'
        AND CPA.ParsedTagsString IS NOT NULL
        AND PHA.EditCount > 0 -- Only posts with at least one edit
),
HighlyEngagedUsers AS (
    SELECT
        TPE.UserId,
        TPE.DisplayName,
        TPE.Reputation,
        TPE.QuestionCount,
        TPE.AnswerCount,
        TPE.TotalUpvotesReceived,
        TPE.PostId,
        TPE.PostTypeId,
        TPE.PostScore,
        TPE.PostViewCount,
        TPE.EditCount,
        TPE.CompositeEngagementScore,
        TPE.ReputationPerDay,
        TPE.BadgeValueScore
    FROM TopPerformingEntities AS TPE
    WHERE
        TPE.ReputationTier = 1 -- Top 10% reputation
        AND TPE.RankByEngagementAndEdits <= 10 -- Top 10 posts per PostType for engagement/edits
        AND TPE.DistinctTagsCount > 5 -- User posts across diverse tags
        AND TPE.HasLateGoldBadge IS TRUE -- Only users who earned a gold badge after they started posting
),
PerformanceRelatedContent AS (
    SELECT
        TPE.UserId,
        TPE.DisplayName,
        TPE.Reputation,
        TPE.QuestionCount,
        TPE.AnswerCount,
        TPE.TotalUpvotesReceived,
        TPE.PostId,
        TPE.PostTypeId,
        TPE.PostScore,
        TPE.PostViewCount,
        TPE.EditCount,
        TPE.CompositeEngagementScore,
        TPE.ReputationPerDay,
        TPE.BadgeValueScore
    FROM TopPerformingEntities AS TPE
    WHERE
        (TPE.IsDatabaseRelated OR TPE.TitleIndicatesPerformance)
        AND TPE.PostScore > 50
        AND TPE.EditCount > 3
        AND TPE.AvgTimeBetweenHistoryEventsSeconds IS NOT NULL AND TPE.AvgTimeBetweenHistoryEventsSeconds < (3600 * 24 * 7) -- Edits are relatively frequent (less than weekly average)
        AND TPE.HasModeratorCommentHistory IS TRUE -- Content that had moderator intervention
)
-- Set operator to combine results
SELECT
    HEU.UserId,
    HEU.DisplayName,
    'Highly Engaged User' AS Category,
    HEU.Reputation,
    HEU.QuestionCount,
    HEU.AnswerCount,
    HEU.TotalUpvotesReceived,
    HEU.PostId,
    HEU.PostTypeId,
    HEU.PostScore,
    HEU.PostViewCount,
    HEU.EditCount,
    HEU.CompositeEngagementScore,
    HEU.ReputationPerDay,
    HEU.BadgeValueScore
FROM HighlyEngagedUsers AS HEU
WHERE HEU.UserId IS NOT NULL -- Ensure a user exists for this entry
UNION ALL
SELECT
    PRC.UserId,
    PRC.DisplayName,
    'Performance Content Contributor' AS Category,
    PRC.Reputation,
    PRC.QuestionCount,
    PRC.AnswerCount,
    PRC.TotalUpvotesReceived,
    PRC.PostId,
    PRC.PostTypeId,
    PRC.PostScore,
    PRC.PostViewCount,
    PRC.EditCount,
    PRC.CompositeEngagementScore,
    PRC.ReputationPerDay,
    PRC.BadgeValueScore
FROM PerformanceRelatedContent AS PRC
WHERE PRC.UserId IS NOT NULL -- Ensure a user exists for this entry
ORDER BY Reputation DESC, CompositeEngagementScore DESC, PostId
LIMIT 100;
