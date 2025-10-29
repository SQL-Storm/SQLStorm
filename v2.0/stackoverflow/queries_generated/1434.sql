-- {"query": "1434.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2996} 

WITH UserProfileSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate,
        -- Calculate total votes given by user across all posts
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesGiven,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesGiven
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    WHERE U.LastAccessDate >= (CURRENT_DATE - INTERVAL '5 year')
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT B.Id) > 0 OR U.Reputation > 1000
),
PostActivitySummary AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        P.Tags,
        -- String expression: check if 'sql' tag is present
        (P.Tags LIKE '%<sql>%') AS HasSQLTag,
        -- Calculate the "freshness" ratio of last activity vs creation date, handling potential division by zero
        NULLIF(EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)), 0) / (3600.0 * 24.0) AS ActivityLifetimeDays,
        -- Correlated subquery: Calculate average score of comments for this post
        COALESCE((SELECT AVG(C.Score) FROM Comments C WHERE C.PostId = P.Id), 0.0) AS AvgCommentScore,
        -- Correlated subquery: Count unique editors excluding the owner
        (SELECT COUNT(DISTINCT PH.UserId)
         FROM PostHistory PH
         WHERE PH.PostId = P.Id
           AND PH.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
           AND PH.UserId IS NOT NULL
           AND PH.UserId <> P.OwnerUserId) AS UniqueEditorCount,
        -- Correlated subquery: Find the first comment creation date
        (SELECT MIN(C.CreationDate) FROM Comments C WHERE C.PostId = P.Id) AS FirstCommentDate,
        -- Conditional logic: Check if it's an accepted answer (for question posts)
        CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
        -- Correlated subquery: Calculate the time difference between post creation and first comment
        EXTRACT(EPOCH FROM ((SELECT MIN(C.CreationDate) FROM Comments C WHERE C.PostId = P.Id) - P.CreationDate)) AS TimeToFirstCommentSeconds
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    WHERE P.CreationDate >= (CURRENT_DATE - INTERVAL '10 year')
      AND P.Score > 0
      AND P.ViewCount > 100
),
ModerationAndLinkedPosts AS (
    SELECT
        PH.PostId,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id END) AS CloseEvents, -- Post Closed
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.Id END) AS ReopenEvents, -- Post Reopened
        COUNT(DISTINCT PL.RelatedPostId) AS DuplicateLinksCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDate
    FROM PostHistory PH
    LEFT JOIN PostLinks PL ON PH.PostId = PL.PostId AND PL.LinkTypeId = 3 -- Duplicate links
    WHERE PH.PostHistoryTypeId IN (10, 11) OR PL.LinkTypeId = 3
    GROUP BY PH.PostId
),
TagAnalysis AS (
    SELECT
        LOWER(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName,
        P.Id AS PostId,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
)
SELECT
    UPS.DisplayName AS UserDisplayName,
    UPS.Reputation AS UserReputation,
    UPS.TotalBadges,
    PAS.PostTypeName,
    PAS.Title AS PostTitle,
    PAS.PostCreationDate,
    PAS.Score AS PostScore,
    PAS.ViewCount AS PostViewCount,
    PAS.CommentCount,
    PAS.FavoriteCount,
    PAS.HasSQLTag,
    PAS.AvgCommentScore,
    PAS.UniqueEditorCount,
    PAS.HasAcceptedAnswer,
    -- NULL logic with COALESCE for time to first comment
    COALESCE(PAS.TimeToFirstCommentSeconds, 0) AS TimeToFirstCommentOrZero,
    -- Complicated expression/calculation: Post Influence Score
    POWER(GREATEST(PAS.Score, 1.0), 0.5) * LOG(GREATEST(PAS.ViewCount, 10.0)) AS PostInfluenceScore,
    -- Window function: Rank posts by score within each user's post type
    RANK() OVER (PARTITION BY UPS.UserId, PAS.PostTypeId ORDER BY PAS.Score DESC, PAS.ViewCount DESC) AS RankWithinUserPostType,
    -- Window function: Average score of previous 5 posts by the same user, ordered by creation date
    AVG(PAS.Score) OVER (PARTITION BY UPS.UserId ORDER BY PAS.PostCreationDate ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING) AS AvgPrev5PostScore,
    -- Window function: Difference in days between current post creation and the user's last post creation
    EXTRACT(DAY FROM (PAS.PostCreationDate - LAG(PAS.PostCreationDate, 1, PAS.PostCreationDate) OVER (PARTITION BY UPS.UserId ORDER BY PAS.PostCreationDate))) AS DaysSinceLastUserPost,
    -- NULL logic for post status and moderation details
    (CASE WHEN PAS.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END) AS PostStatus,
    COALESCE(MNP.CloseEvents, 0) AS CloseEvents,
    COALESCE(MNP.ReopenEvents, 0) AS ReopenEvents,
    COALESCE(MNP.DuplicateLinksCount, 0) AS DuplicateLinksCount,
    COALESCE(MNP.LastClosedDate, '1900-01-01'::timestamp) AS ActualLastClosedDate,
    -- Non-correlated subquery for a global tag aggregate
    (SELECT AVG(T_inner.PostScore)
     FROM TagAnalysis T_inner
     WHERE T_inner.TagName = 'performance' AND T_inner.PostViewCount > 1000) AS AvgPerformanceTagScore,
    -- Correlated subquery counting posts with higher score for a specific tag
    (SELECT COUNT(DISTINCT TA.PostId) FROM TagAnalysis TA WHERE TA.TagName = 'sql' AND TA.PostScore > PAS.Score) AS HigherScoringSQLPostsCount
FROM UserProfileSummary UPS
JOIN PostActivitySummary PAS ON UPS.UserId = PAS.OwnerUserId
LEFT JOIN ModerationAndLinkedPosts MNP ON PAS.PostId = MNP.PostId
WHERE
    -- Complicated predicates
    (UPS.Reputation > 50000 AND PAS.Score > 50 AND PAS.ViewCount > 10000)
    OR
    (UPS.GoldBadges >= 5 AND PAS.FavoriteCount > 20 AND PAS.HasSQLTag = TRUE)
    OR
    (PAS.PostTypeName = 'Answer' AND PAS.HasAcceptedAnswer = TRUE AND PAS.AvgCommentScore > 2 AND PAS.UniqueEditorCount > 0)
    -- Complex date and string predicate
    AND PAS.PostCreationDate BETWEEN (CURRENT_DATE - INTERVAL '5 year') AND (CURRENT_DATE - INTERVAL '6 month')
    AND (PAS.Title ILIKE '%query%' OR PAS.Title ILIKE '%optimization%')
    AND COALESCE(PAS.TimeToFirstCommentSeconds, 9999999) < 86400 -- first comment within a day (86400 seconds)
ORDER BY
    PostInfluenceScore DESC,
    UPS.Reputation DESC,
    PAS.PostCreationDate DESC
LIMIT 500

UNION ALL

SELECT
    UPS.DisplayName AS UserDisplayName,
    UPS.Reputation AS UserReputation,
    UPS.TotalBadges,
    PAS.PostTypeName,
    PAS.Title AS PostTitle,
    PAS.PostCreationDate,
    PAS.Score AS PostScore,
    PAS.ViewCount AS PostViewCount,
    PAS.CommentCount,
    PAS.FavoriteCount,
    PAS.HasSQLTag,
    PAS.AvgCommentScore,
    PAS.UniqueEditorCount,
    PAS.HasAcceptedAnswer,
    COALESCE(PAS.TimeToFirstCommentSeconds, 0) AS TimeToFirstCommentOrZero,
    POWER(GREATEST(PAS.Score, 1.0), 0.5) * LOG(GREATEST(PAS.ViewCount, 10.0)) AS PostInfluenceScore,
    RANK() OVER (PARTITION BY UPS.UserId, PAS.PostTypeId ORDER BY PAS.Score DESC, PAS.ViewCount DESC) AS RankWithinUserPostType,
    AVG(PAS.Score) OVER (PARTITION BY UPS.UserId ORDER BY PAS.PostCreationDate ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING) AS AvgPrev5PostScore,
    EXTRACT(DAY FROM (PAS.PostCreationDate - LAG(PAS.PostCreationDate, 1, PAS.PostCreationDate) OVER (PARTITION BY UPS.UserId ORDER BY PAS.PostCreationDate))) AS DaysSinceLastUserPost,
    (CASE WHEN PAS.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END) AS PostStatus,
    COALESCE(MNP.CloseEvents, 0) AS CloseEvents,
    COALESCE(MNP.ReopenEvents, 0) AS ReopenEvents,
    COALESCE(MNP.DuplicateLinksCount, 0) AS DuplicateLinksCount,
    COALESCE(MNP.LastClosedDate, '1900-01-01'::timestamp) AS ActualLastClosedDate,
    (SELECT AVG(T_inner.PostScore)
     FROM TagAnalysis T_inner
     WHERE T_inner.TagName = 'performance' AND T_inner.PostViewCount > 1000) AS AvgPerformanceTagScore,
    (SELECT COUNT(DISTINCT TA.PostId) FROM TagAnalysis TA WHERE TA.TagName = 'sql' AND TA.PostScore > PAS.Score) AS HigherScoringSQLPostsCount
FROM UserProfileSummary UPS
JOIN PostActivitySummary PAS ON UPS.UserId = PAS.OwnerUserId
LEFT JOIN ModerationAndLinkedPosts MNP ON PAS.PostId = MNP.PostId
WHERE
    PAS.UniqueEditorCount > 2 -- At least 3 distinct editors (owner + 2 others)
    AND PAS.PostTypeName IN ('Question', 'Wiki')
    AND PAS.PostCreationDate >= (CURRENT_DATE - INTERVAL '2 year')
    AND PAS.ViewCount > 5000
    -- Correlated subquery in WHERE clause for comparison with a global aggregate
    AND PAS.Score < (SELECT COALESCE(AVG(P_sub.Score), 0.0) FROM Posts P_sub WHERE P_sub.PostTypeId = PAS.PostTypeId AND P_sub.CreationDate >= (CURRENT_DATE - INTERVAL '2 year')) * 0.5 -- Below average score but heavily edited
    AND COALESCE(MNP.CloseEvents, 0) = 0 -- Not closed
ORDER BY
    PAS.UniqueEditorCount DESC,
    PAS.PostCreationDate ASC
LIMIT 500;
