-- {"query": "1860.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2300} 

WITH UserEngagementSummary AS (
    -- Summarize user activity and influence on their own posts, focusing on Questions and Answers
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(p.Score) AS TotalPostScore,
        AVG(CAST(p.Score AS NUMERIC)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        -- Window function to get rank of user by reputation
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS RepRank,
        -- Aggregate votes on their posts (UpMod, DownMod)
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceived,
        -- Correlated subquery: Does this user have any posts that were closed due to being a duplicate?
        EXISTS (
            SELECT 1
            FROM PostHistory ph
            WHERE ph.PostId IN (SELECT p_inner.Id FROM Posts p_inner WHERE p_inner.OwnerUserId = u.Id AND p_inner.PostTypeId = 1)
              AND ph.PostHistoryTypeId = 10 -- Post Closed
              AND ph.Comment = (SELECT CAST(crt.Id AS VARCHAR) FROM CloseReasonTypes crt WHERE crt.Name LIKE '%Duplicate%')
        ) AS HasDuplicateClosedPost
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3) -- UpMod, DownMod
    WHERE p.PostTypeId IN (1, 2) -- Only consider Questions and Answers
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostContentQuality AS (
    -- Analyze quality metrics for posts, including edit history and associated tags
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.ClosedDate,
        LENGTH(p.Body) AS BodyLength,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount, -- Title, Body, Tags edits
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS LastEditDate,
        MIN(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS FirstEditDate,
        -- Window function to calculate the time difference in hours between the post creation and its first edit
        EXTRACT(EPOCH FROM (MIN(ph.CreationDate) OVER (PARTITION BY p.Id ORDER BY ph.CreationDate ASC) - p.CreationDate)) / 3600.0 AS TimeToFirstEditHours,
        COALESCE(SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END), 0) AS PositiveCommentCount,
        COUNT(c.Id) AS TotalCommentCount,
        -- String expression: Check if post title contains common problematic phrases (case-insensitive)
        LOWER(p.Title) LIKE '%problem%' OR LOWER(p.Title) LIKE '%issue%' OR LOWER(p.Title) LIKE '%help me%' AS IsProblematicTitle,
        -- Correlated subquery: Has this post received at least one "Offensive" vote?
        EXISTS (
            SELECT 1
            FROM Votes v_inner
            WHERE v_inner.PostId = p.Id AND v_inner.VoteTypeId = 4 -- Offensive vote
        ) AS HasOffensiveVote,
        STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><') AS TagArray
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.Title, p.Tags, p.ClosedDate, p.Body
),
TagPerformanceMetrics AS (
    -- Calculate metrics for tags, identifying "high-engagement" tags
    SELECT
        Tag,
        COUNT(pcq.PostId) AS PostCount,
        AVG(CAST(pcq.Score AS NUMERIC)) AS AvgTagScore,
        SUM(pcq.ViewCount) AS TotalTagViews,
        COUNT(DISTINCT pcq.OwnerUserId) AS UniqueContributors,
        -- Window function to rank tags by total score and unique contributors
        RANK() OVER (ORDER BY SUM(pcq.Score) DESC, COUNT(DISTINCT pcq.OwnerUserId) DESC) AS TagRankByInfluence
    FROM PostContentQuality pcq
    CROSS JOIN UNNEST(pcq.TagArray) AS Tag
    GROUP BY Tag
    HAVING COUNT(pcq.PostId) > 10 -- Only consider tags with significant activity
)
-- Final Query: Combine user engagement, post quality, and tag performance to identify influential users
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.RepRank,
    ues.TotalQuestions,
    ues.TotalAnswers,
    ues.TotalPostScore,
    ues.AvgPostScore,
    ues.TotalUpVotesReceived,
    ues.TotalDownVotesReceived,
    ues.HasDuplicateClosedPost,
    COALESCE(SUM(pcq.EditCount), 0) AS TotalEditsAcrossPosts,
    COALESCE(AVG(pcq.BodyLength), 0) AS AvgPostBodyLength,
    COALESCE(AVG(pcq.TimeToFirstEditHours), 0) AS AvgTimeToFirstEditHours,
    COUNT(DISTINCT pcq.PostId) FILTER (WHERE pcq.IsProblematicTitle) AS ProblematicTitlePosts,
    COUNT(DISTINCT pcq.PostId) FILTER (WHERE pcq.HasOffensiveVote) AS PostsWithOffensiveVotes,
    MAX(tp.AvgTagScore) AS MaxAvgTagScoreForUser,
    MAX(tp.TagRankByInfluence) AS BestTagInfluenceRank,
    STRING_AGG(DISTINCT tp.Tag, ', ') AS TopContributingTags,
    -- Complicated calculation: "Influence Score"
    (
        (ues.TotalUpVotesReceived * 0.5) + (ues.AvgPostScore * 10) +
        (UES.TotalQuestions * 2) + (UES.TotalAnswers * 3) +
        (COALESCE(SUM(pcq.FavoriteCount), 0) * 0.7) -
        (ues.TotalDownVotesReceived * 0.2) -
        (COUNT(DISTINCT pcq.PostId) FILTER (WHERE pcq.HasOffensiveVote) * 5)
    ) AS UserInfluenceScore,
    -- NULL logic and conditional expression: User Location and Website Status
    CASE
        WHEN u.WebsiteUrl IS NOT NULL AND LENGTH(TRIM(u.WebsiteUrl)) > 0 THEN 'Has Website'
        WHEN u.WebsiteUrl IS NULL AND u.Location IS NOT NULL THEN 'No Website, Has Location'
        ELSE 'No Website, Unknown Location'
    END AS UserWebPresenceStatus,
    -- Correlated subquery in SELECT: Get latest badge name for the user, if any
    (
        SELECT b.Name
        FROM Badges b
        WHERE b.UserId = ues.UserId
        ORDER BY b.Date DESC
        LIMIT 1
    ) AS LatestBadgeName
FROM UserEngagementSummary ues
LEFT JOIN PostContentQuality pcq ON ues.UserId = pcq.OwnerUserId
LEFT JOIN Users u ON ues.UserId = u.Id -- Join back to Users for WebsiteUrl/Location
LEFT JOIN TagPerformanceMetrics tp ON EXISTS (
    SELECT 1 FROM UNNEST(pcq.TagArray) AS post_tag WHERE post_tag = tp.Tag AND tp.TagRankByInfluence <= 10
) -- Join to highly influential tags that this user has posted in
GROUP BY
    ues.UserId, ues.DisplayName, ues.Reputation, ues.RepRank, ues.TotalQuestions,
    ues.TotalAnswers, ues.TotalPostScore, ues.AvgPostScore, ues.TotalUpVotesReceived,
    ues.TotalDownVotesReceived, ues.HasDuplicateClosedPost, u.WebsiteUrl, u.Location
HAVING
    ues.TotalQuestions > 5 AND ues.TotalAnswers > 10 AND ues.AvgPostScore > 0
    AND ues.Reputation >= 1000 AND COALESCE(SUM(pcq.EditCount), 0) > 2
    AND (
        (COALESCE(SUM(pcq.PositiveCommentCount), 0) / NULLIF(COALESCE(SUM(pcq.TotalCommentCount), 0), 0)) > 0.6
        OR COALESCE(SUM(pcq.PositiveCommentCount), 0) > 5
    )
ORDER BY UserInfluenceScore DESC, ues.RepRank ASC
LIMIT 100;
