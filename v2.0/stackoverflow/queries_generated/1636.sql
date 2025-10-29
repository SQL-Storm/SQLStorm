-- {"query": "1636.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3098} 

WITH UserEngagementSummary AS (
    -- CTE 1: Aggregates user activity, reputation, and initial post statistics.
    -- Includes COALESCE for robust NULL handling in sums.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        MAX(COALESCE(p.LastActivityDate, '1900-01-01'::timestamp)) AS LatestPostActivity,
        MAX(COALESCE(c.CreationDate, '1900-01-01'::timestamp)) AS LatestCommentActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostDetailAnalysis AS (
    -- CTE 2: Processes individual question details, including vote counts and basic content analysis.
    -- Uses string manipulation for tags and conditional checks on text content.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        COALESCE(p.Tags, '><') AS RawTags, -- Ensure tags is not NULL for string functions
        LENGTH(p.Body) AS BodyLength,
        (CASE WHEN p.Body ILIKE '%performance%' OR p.Body ILIKE '%optimization%' THEN TRUE ELSE FALSE END) AS ContainsPerformanceKeywords,
        (CASE WHEN p.Title ILIKE '%slow%' OR p.Title ILIKE '%fast%' THEN TRUE ELSE FALSE END) AS ContainsSpeedKeywords,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        -- Correlated subquery: count distinct link types to this post
        (SELECT COUNT(DISTINCT pl_in.LinkTypeId) FROM PostLinks pl_in WHERE pl_in.RelatedPostId = p.Id) AS IncomingLinkTypeCount
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1 -- Focusing on Questions
    GROUP BY
        p.Id, p.OwnerUserId, p.CreationDate, p.Title, p.Body, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.LastActivityDate, p.Tags
),
UserBadgeTimeline AS (
    -- CTE 3: Analyzes user's badge acquisition, using window functions for ranking and totals.
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Date AS BadgeAwardDate,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY b.UserId, b.Class ORDER BY b.Date ASC) AS BadgeRankInClass,
        COUNT(b.Id) OVER (PARTITION BY b.UserId) AS TotalBadgesForUser,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY b.UserId) AS GoldBadgesCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY b.UserId) AS SilverBadgesCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY b.UserId) AS BronzeBadgesCount,
        AVG(EXTRACT(EPOCH FROM (b.Date - ues.UserCreationDate)) / 86400.0) OVER (PARTITION BY b.UserId) AS AvgDaysToBadgeFromCreation
    FROM Badges b
    JOIN UserEngagementSummary ues ON b.UserId = ues.UserId
),
PostHistoryAndCommentActivity AS (
    -- CTE 4: Combines post history events (edits, close/reopen) and significant comments using UNION ALL.
    -- This shows set operator usage and aggregates event types.
    SELECT
        ph.PostId,
        ph.CreationDate AS EventDate,
        ph.UserId AS EventUserId,
        'PostHistory' AS EventSource,
        ph.PostHistoryTypeId AS HistoryTypeId,
        COALESCE(ph.Comment, 'N/A') AS EventDescription
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 10, 11) -- Edit, Close, Reopen events
    UNION ALL
    SELECT
        c.PostId,
        c.CreationDate AS EventDate,
        c.UserId AS EventUserId,
        'Comment' AS EventSource,
        NULL AS HistoryTypeId, -- No PostHistoryTypeId for comments
        c.Text AS EventDescription
    FROM Comments c
    WHERE c.Score >= 3 -- Only significant comments
)
-- Main query: Joins CTEs and other tables, applies complex filters, calculations, and window functions.
SELECT
    pda.PostId,
    pda.Title AS QuestionTitle,
    ues.DisplayName AS OwnerDisplayName,
    ues.Reputation AS OwnerReputation,
    pda.PostCreationDate,
    pda.Score AS QuestionScore,
    pda.ViewCount AS QuestionViews,
    pda.AnswerCount,
    pda.CommentCount AS QuestionCommentsCount,
    pda.FavoriteCount,
    pda.ClosedDate AS QuestionClosedDate,
    pda.BodyLength,
    pda.ContainsPerformanceKeywords,
    pda.ContainsSpeedKeywords,
    pda.UpVotesReceived,
    pda.DownVotesReceived,
    (CAST(pda.UpVotesReceived AS NUMERIC) - pda.DownVotesReceived) AS NetVotes,
    (CAST(pda.UpVotesReceived AS NUMERIC) / NULLIF(pda.DownVotesReceived + pda.UpVotesReceived, 0)) AS UpvoteRatio,
    pda.IncomingLinkTypeCount,
    -- Correlated subquery: calculate average comment length for the post
    (SELECT AVG(LENGTH(c_len.Text))
     FROM Comments c_len
     WHERE c_len.PostId = pda.PostId AND c_len.UserId IS NOT NULL
       AND c_len.Text IS NOT NULL AND LENGTH(TRIM(c_len.Text)) > 0
    ) AS AverageCommentLength,
    STRING_AGG(DISTINCT t.TagName, '; ') FILTER (WHERE t.TagName IS NOT NULL AND t.Count > 100) AS PopularQuestionTags,
    ubt.GoldBadgesCount,
    ubt.SilverBadgesCount,
    ubt.BronzeBadgesCount,
    MAX(CASE WHEN ubt.BadgeRankInClass = 1 AND ubt.Class = 1 THEN ubt.BadgeName END) OVER (PARTITION BY pda.OwnerUserId) AS FirstGoldBadgeAwarded,
    MIN(EXTRACT(EPOCH FROM (pda.PostCreationDate - ues.UserCreationDate)) / 86400.0) OVER (PARTITION BY pda.OwnerUserId) AS DaysToFirstQuestion,
    MAX(phca.EventDate) FILTER (WHERE phca.EventSource = 'PostHistory' AND phca.HistoryTypeId IN (4,5,6)) AS LatestEditEventDate,
    MAX(phca.EventDate) FILTER (WHERE phca.EventSource = 'Comment') AS LatestSignificantCommentDate,
    CASE
        WHEN pda.ClosedDate IS NOT NULL AND pda.Score < 0 THEN 'Closed & Negative'
        WHEN pda.ClosedDate IS NOT NULL AND pda.Score >= 0 THEN 'Closed & Neutral/Positive'
        WHEN pda.Score > 50 AND pda.CommentCount > 20 THEN 'Highly Engaged'
        WHEN pda.ViewCount > 10000 AND pda.AnswerCount = 0 THEN 'Popular Unanswered'
        ELSE 'Other Question Type'
    END AS PostCategorization,
    ROW_NUMBER() OVER (ORDER BY pda.Score DESC, pda.ViewCount DESC, pda.CommentCount DESC) AS GlobalEngagementRank,
    RANK() OVER (PARTITION BY pda.OwnerUserId ORDER BY pda.Score DESC, pda.ViewCount DESC) AS RankWithinOwnerPosts,
    LAG(pda.PostCreationDate, 1, ues.UserCreationDate) OVER (PARTITION BY pda.OwnerUserId ORDER BY pda.PostCreationDate) AS PreviousQuestionDate,
    DATE_PART('day', pda.PostCreationDate - LAG(pda.PostCreationDate, 1, ues.UserCreationDate) OVER (PARTITION BY pda.OwnerUserId ORDER BY pda.PostCreationDate)) AS DaysSincePreviousQuestion,
    -- Correlated subquery: check if the post has a community owned date and has more than 5 edits
    (SELECT CASE WHEN p.CommunityOwnedDate IS NOT NULL AND COUNT(ph_edit.Id) > 5 THEN 'Community Wiki & Heavily Edited' ELSE 'Regular Status' END
     FROM Posts p_inner
     LEFT JOIN PostHistory ph_edit ON p_inner.Id = ph_edit.PostId AND ph_edit.PostHistoryTypeId IN (4,5,6)
     WHERE p_inner.Id = pda.PostId
     GROUP BY p_inner.CommunityOwnedDate
    ) AS CommunityWikiStatus,
    COALESCE(
        (SELECT MAX(ph_mig.CreationDate)
         FROM PostHistory ph_mig
         WHERE ph_mig.PostId = pda.PostId AND ph_mig.PostHistoryTypeId IN (35, 36)
        ), '1900-01-01'::timestamp
    ) AS LastMigrationDate
FROM PostDetailAnalysis pda
JOIN UserEngagementSummary ues ON pda.OwnerUserId = ues.UserId
LEFT JOIN LATERAL (SELECT UNNEST(string_to_array(substring(pda.RawTags, 2, length(pda.RawTags)-2), '><')) AS TagName) AS unnested_tags ON TRUE
LEFT JOIN Tags t ON unnested_tags.TagName = t.TagName
LEFT JOIN UserBadgeTimeline ubt ON ues.UserId = ubt.UserId
LEFT JOIN PostHistoryAndCommentActivity phca ON pda.PostId = phca.PostId
WHERE
    ues.Reputation > 7500 -- Filter for highly reputed users
    AND pda.ViewCount > 2000 -- Focus on well-viewed questions
    AND pda.CommentCount > 10 -- And those with substantial discussion
    AND pda.BodyLength BETWEEN 300 AND 4000 -- Ensure relevant body length
    AND pda.ClosedDate IS NOT NULL -- Only closed questions
    AND (pda.RawTags ILIKE '%<sql>%' OR pda.RawTags ILIKE '%<database>%' OR pda.RawTags ILIKE '%<performance>%') -- Topic focus
    AND EXISTS ( -- Correlated subquery: user must have at least one gold badge
        SELECT 1
        FROM Badges b_gold
        WHERE b_gold.UserId = ues.UserId AND b_gold.Class = 1
    )
    AND NOT EXISTS ( -- Correlated subquery: post should not have been deleted
        SELECT 1
        FROM PostHistory ph_deleted
        WHERE ph_deleted.PostId = pda.PostId AND ph_deleted.PostHistoryTypeId = 12
    )
    AND pda.UpVotesReceived > pda.DownVotesReceived * 1.5 -- Positive net sentiment
    AND pda.IncomingLinkTypeCount > 0 -- Question is linked from somewhere
GROUP BY
    pda.PostId, pda.Title, ues.DisplayName, ues.Reputation, pda.PostCreationDate, pda.Score,
    pda.ViewCount, pda.AnswerCount, pda.CommentCount, pda.FavoriteCount, pda.ClosedDate,
    pda.BodyLength, pda.ContainsPerformanceKeywords, pda.ContainsSpeedKeywords,
    pda.UpVotesReceived, pda.DownVotesReceived, pda.IncomingLinkTypeCount,
    ues.UserId, ues.UserCreationDate, ubt.GoldBadgesCount, ubt.SilverBadgesCount,
    ubt.BronzeBadgesCount
HAVING
    COUNT(DISTINCT t.TagName) > 2 -- Ensure question has at least 3 distinct tags
    AND SUM(CASE WHEN t.TagName = 'sql' THEN 1 ELSE 0 END) > 0 -- Must explicitly contain 'sql' tag
ORDER BY
    ues.Reputation DESC, pda.Score DESC, pda.ViewCount DESC, pda.PostCreationDate DESC
LIMIT 250;
