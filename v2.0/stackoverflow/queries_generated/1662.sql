-- {"query": "1662.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3115} 

WITH UserActivitySummary AS (
    -- Summarizes user activity, including post counts, comment counts, total scores, badge distributions,
    -- and general activity timestamps. Uses COALESCE for sums to handle users with no activity.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(p.Score), 0) AS TotalPostScoreOwned,
        COALESCE(SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END), 0) AS TotalUpVotesGiven,
        COALESCE(SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END), 0) AS TotalDownVotesGiven,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadgesCount,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadgesCount,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadgesCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        DATE_PART('day', AGE(CURRENT_TIMESTAMP, u.CreationDate)) AS DaysSinceCreation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostRevisionMetrics AS (
    -- Tracks the history of posts, including total revisions, distinct editors, and specific event counts
    -- such as edits, close, reopen, delete, and undelete.
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalRevisions,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS ContentEditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEventCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeleteEventCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 13 THEN 1 ELSE 0 END) AS UndeleteEventCount,
        MAX(ph.CreationDate) AS LastRevisionDate,
        MIN(ph.CreationDate) AS FirstRevisionDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastReopenedDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
PostVoteAggregates AS (
    -- Aggregates various vote types received by each post.
    SELECT
        v.PostId,
        COALESCE(SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END), 0) AS UpvotesReceived,
        COALESCE(SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END), 0) AS DownvotesReceived,
        COALESCE(SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END), 0) AS FavoriteVotesReceived,
        COALESCE(SUM(CASE WHEN vt.Name IN ('Offensive', 'Spam') THEN 1 ELSE 0 END), 0) AS FlaggedVotesReceived
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
),
SelfAnsweredQuestions AS (
    -- Identifies questions where the owner of the question also provided an answer.
    -- Uses a correlated subquery within the CTE definition.
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND EXISTS (
            SELECT 1
            FROM Posts a
            WHERE a.ParentId = q.Id
              AND a.OwnerUserId = q.OwnerUserId
              AND a.PostTypeId = 2
        )
),
TagPerformance AS (
    -- Parses tags from questions into individual rows, useful for tag-level analytics.
    -- This CTE can generate a significant number of rows depending on tag usage.
    SELECT
        p.Id AS PostId,
        TRIM(unnest(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'))) AS TagName,
        p.Score,
        p.ViewCount,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
),
PostsOfInterestCategory AS (
    -- Categorizes posts based on specific engagement and revision criteria using a UNION ALL set operator.
    SELECT
        'HighEngagementQuestion' AS PostInterestCategory,
        pe.Id AS PostId
    FROM Posts pe
    WHERE pe.PostTypeId = 1 AND pe.ViewCount > 50000 AND pe.AnswerCount > 20
    UNION ALL
    SELECT
        'ControversialEditedAnswer' AS PostInterestCategory,
        pe.Id AS PostId
    FROM Posts pe
    JOIN PostRevisionMetrics prm_sub ON pe.Id = prm_sub.PostId
    JOIN PostVoteAggregates pva_sub ON pe.Id = pva_sub.PostId
    WHERE pe.PostTypeId = 2
      AND prm_sub.ContentEditCount >= 10
      AND pva_sub.DownvotesReceived > 5
      AND prm_sub.CloseEventCount > 0 AND prm_sub.ReopenEventCount > 0
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalPostsOwned,
    uas.TotalCommentsMade,
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.AnswerCount AS PostAnswerCount,
    p.CommentCount AS PostCommentCount,
    p.FavoriteCount AS PostFavoriteCountField,
    prm.TotalRevisions,
    prm.ContentEditCount,
    prm.CloseEventCount,
    prm.ReopenEventCount,
    pva.UpvotesReceived,
    pva.DownvotesReceived,
    pva.FavoriteVotesReceived,
    pva.FlaggedVotesReceived,
    saq.QuestionId IS NOT NULL AS IsSelfAnswered,
    (prm.ReopenEventCount > 0 AND prm.CloseEventCount > 0 AND COALESCE(prm.LastReopenedDate, '1900-01-01') > COALESCE(prm.LastClosedDate, '1900-01-01')) AS HasBeenClosedAndReopened,
    poi.PostInterestCategory,
    -- Window functions for ranking, lagging values, and rolling averages
    DENSE_RANK() OVER (PARTITION BY DATE_TRUNC('year', p.CreationDate) ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRankInYear,
    LAG(p.Score, 1, 0) OVER (PARTITION BY uas.UserId ORDER BY p.CreationDate) AS PreviousPostScoreByAuthor,
    AVG(p.Score) OVER (PARTITION BY uas.UserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RollingAvgScoreLast3PostsByAuthor,
    COALESCE(SUM(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 0) AS CumulativeScoreOverall,
    -- Complex expressions and calculations using CASE, COALESCE, NULLIF
    CASE
        WHEN uas.Reputation >= 10000 AND uas.GoldBadgesCount >= 5 AND uas.TotalPostsOwned >= 100 THEN 'Legendary Contributor'
        WHEN uas.Reputation >= 2000 AND uas.SilverBadgesCount >= 3 THEN 'Veteran Contributor'
        WHEN uas.TotalPostsOwned >= 10 OR uas.TotalCommentsMade >= 50 THEN 'Active Contributor'
        ELSE 'New/Passive Contributor'
    END AS UserContributionTier,
    COALESCE(NULLIF(pva.UpvotesReceived, 0) / NULLIF(pva.DownvotesReceived, 0)::numeric, 0) AS UpvoteToDownvoteRatio,
    -- String expressions for data manipulation and display
    LOWER(SUBSTRING(p.Title FROM 1 FOR 1)) AS FirstCharOfTitle,
    TRIM(REPLACE(REPLACE(LOWER(SUBSTRING(COALESCE(p.Body, ''), 1, 100)), '  ', ' '), CHR(10), '')) AS BodyExcerptCleaned,
    -- NULL logic and complicated boolean predicates
    (p.OwnerUserId IS NOT NULL AND uas.TotalPostsOwned > 0) AS IsValidOwnerAndActive,
    COALESCE(p.ClosedDate, '1900-01-01'::timestamp) AS ActualOrMinClosedDate,
    (p.CommunityOwnedDate IS NULL AND p.LastEditorUserId IS NOT NULL) AS IsUserOwnedAndEdited,
    -- Correlated subquery 1: Count of outgoing linked posts within the last year
    (SELECT COUNT(DISTINCT pl.RelatedPostId)
     FROM PostLinks pl
     WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1
     AND pl.CreationDate >= p.CreationDate - INTERVAL '1 year') AS OutgoingLinkedPostsLastYear,
    -- Correlated subquery 2: Average score of related tags in posts from the last 90 days
    (SELECT AVG(tp_sub.Score)
     FROM TagPerformance tp_sub
     WHERE EXISTS (
         SELECT 1 FROM UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS post_tag
         WHERE LOWER(TRIM(post_tag)) = LOWER(TRIM(tp_sub.TagName))
     )
     AND tp_sub.CreationDate BETWEEN p.CreationDate - INTERVAL '90 days' AND p.CreationDate
     AND tp_sub.PostId <> p.Id
    ) AS AvgRelatedTagScore90DaysPrior
FROM Users u
JOIN UserActivitySummary uas ON u.Id = uas.UserId
JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN PostRevisionMetrics prm ON p.Id = prm.PostId
LEFT JOIN PostVoteAggregates pva ON p.Id = pva.PostId
LEFT JOIN SelfAnsweredQuestions saq ON p.Id = saq.QuestionId
LEFT JOIN PostsOfInterestCategory poi ON p.Id = poi.PostId -- Joins the CTE with UNION ALL results
WHERE
    p.PostTypeId = 1 -- Focus on questions
    AND uas.Reputation > 500 -- Filter for users with a minimum reputation
    AND p.CreationDate BETWEEN '2020-01-01' AND '2024-01-01' -- Date range for posts
    AND (p.ViewCount > 1000 OR p.Score > 5) -- Filter for posts with some popularity
    AND (prm.TotalRevisions IS NULL OR prm.TotalRevisions >= 2 OR pva.DownvotesReceived > 0) -- Posts with activity or negative sentiment
    AND u.Location IS NOT NULL AND LENGTH(TRIM(u.Location)) > 5 -- User has a specified, non-trivial location
    AND NOT EXISTS (
        SELECT 1
        FROM Badges b_filtered
        WHERE b_filtered.UserId = u.Id AND b_filtered.Name = 'Disciplined'
    ) -- Exclude users with a specific badge using NOT EXISTS
    AND p.Body LIKE '%<pre><code>%' -- Filter posts containing code blocks
    AND COALESCE(p.ClosedDate, '2024-01-01'::timestamp) > '2023-01-01'::timestamp -- Posts either not closed, or closed recently
    AND (poi.PostInterestCategory IS NOT NULL OR p.FavoriteCount > 10) -- Include posts matching specific categories or having significant favorites
ORDER BY
    uas.Reputation DESC,
    p.Score DESC NULLS LAST,
    RollingAvgScoreLast3PostsByAuthor DESC NULLS FIRST,
    prm.ContentEditCount DESC NULLS LAST,
    OutgoingLinkedPostsLastYear DESC NULLS LAST
LIMIT 1000;
