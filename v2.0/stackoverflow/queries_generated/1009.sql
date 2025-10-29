-- {"query": "1009.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2737} 

WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate AS UserLastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostViews,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        -- Correlated subquery: find the highest score on any post created by this user
        (
            SELECT MAX(p_inner.Score)
            FROM Posts p_inner
            WHERE p_inner.OwnerUserId = u.Id
        ) AS MaxPostScoreByUser,
        -- Non-correlated subquery: average score of all posts on the platform
        (
            SELECT AVG(p_all.Score)
            FROM Posts p_all
            WHERE p_all.Score IS NOT NULL
        ) AS GlobalAveragePostScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        COUNT(v.Id) FILTER (WHERE vt.Name = 'UpMod') AS TotalUpVotesGiven, -- Using FILTER for specific aggregation
        COUNT(v.Id) FILTER (WHERE vt.Name = 'DownMod') AS TotalDownVotesGiven,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 5) AS TotalFavoritesMade
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostContentAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.OwnerUserId,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(p.Title) AS TitleLength,
        -- String expression: count 'code' occurrences in Body (case-insensitive)
        (LENGTH(LOWER(p.Body)) - LENGTH(REPLACE(LOWER(p.Body), 'code', ''))) / LENGTH('code') AS CodeKeywordCount,
        -- Complicated calculation: engagement ratio (avoid division by zero)
        CAST(COALESCE(p.FavoriteCount, 0) + COALESCE(p.AnswerCount, 0) AS NUMERIC) / NULLIF(p.ViewCount, 0) AS EngagementRatio,
        -- Window function: Rank posts by score within each PostType and Owner (partition by PostTypeId, OwnerUserId)
        RANK() OVER (PARTITION BY p.PostTypeId, p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate ASC) AS RankInUserPostType,
        -- Window function: Average score of posts by the same owner in the last 30 days
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ASC RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW) AS AvgOwnerScoreLast30Days,
        -- LAG function to get the score of the previous post by the same owner
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        -- Complicated predicate in CASE
        CASE
            WHEN p.Score > 100 AND p.ViewCount > 10000 AND p.AnswerCount > 5 THEN 'Highly Engaged & Voted'
            WHEN p.Score BETWEEN 50 AND 100 OR p.ViewCount BETWEEN 5000 AND 10000 THEN 'Moderately Popular'
            WHEN p.ClosedDate IS NOT NULL AND p.Score < 0 THEN 'Closed & Unpopular'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Driven'
            ELSE 'Standard'
        END AS PostStatusCategory,
        -- NULL logic: COALESCE OwnerDisplayName with 'Anonymous'
        COALESCE(p.OwnerDisplayName, 'Anonymous') AS ResolvedOwnerDisplayName,
        -- Extract tags as an array for further processing
        CASE
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 THEN string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')
            ELSE '{}'::varchar[]
        END AS TagArray
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    AND p.CreationDate >= '2020-01-01' -- Filter for recent activity
),
TagPerformanceMetrics AS (
    SELECT
        UPPER(unnest_tag.tag) AS TagName, -- String expression: convert to uppercase
        COUNT(DISTINCT pca.PostId) AS QuestionsWithTag,
        AVG(pca.PostScore) AS AverageTagQuestionScore,
        SUM(pca.ViewCount) AS TotalTagViews,
        MIN(t.Count) AS MinTagUseCount, -- Join to Tags table to get global tag stats
        MAX(t.Count) AS MaxTagUseCount,
        SUM(CASE WHEN t.IsModeratorOnly THEN 1 ELSE 0 END) AS ModeratorOnlyTagCount,
        -- NULL logic for excerpt posts
        SUM(CASE WHEN t.ExcerptPostId IS NULL THEN 1 ELSE 0 END) AS TagsWithoutExcerpt
    FROM PostContentAnalysis pca
    LEFT JOIN LATERAL unnest(pca.TagArray) AS unnest_tag(tag) ON TRUE
    LEFT JOIN Tags t ON UPPER(unnest_tag.tag) = UPPER(t.TagName) -- Case-insensitive tag matching
    WHERE unnest_tag.tag IS NOT NULL
    GROUP BY UPPER(unnest_tag.tag)
    HAVING COUNT(DISTINCT pca.PostId) > 10 -- Only consider tags used in more than 10 posts
)
-- Main query combining all CTEs and additional tables
SELECT
    ues.UserId,
    ues.Reputation,
    ues.UserCreationDate,
    ues.UserLastAccessDate,
    ues.TotalPosts,
    ues.QuestionCount,
    ues.AnswerCount,
    ues.TotalPostScore,
    ues.MaxPostScoreByUser,
    ues.GlobalAveragePostScore,
    tpm.TagName,
    tpm.QuestionsWithTag,
    tpm.AverageTagQuestionScore,
    tpm.TotalTagViews,
    pca.PostId,
    pca.PostTypeId,
    pca.PostCreationDate,
    pca.PostScore,
    pca.ViewCount,
    pca.EngagementRatio,
    pca.RankInUserPostType,
    pca.AvgOwnerScoreLast30Days,
    pca.PostStatusCategory,
    ph.CreationDate AS HistoryDate,
    ph.PostHistoryTypeId,
    pht.Name AS HistoryTypeName,
    ph.Comment AS HistoryComment,
    closereason.Name AS CloseReason, -- Outer join for CloseReasonType, conditional on PostHistoryTypeId
    COALESCE(users_editor.DisplayName, 'Unknown Editor') AS LastEditorDisplayName, -- NULL logic for editor
    pl.LinkTypeId,
    lt.Name AS LinkTypeName,
    related_post.Title AS RelatedPostTitle, -- Nested join for related post title
    -- Complex expression involving multiple fields and type casting
    (ues.TotalPostScore * 0.5 + ues.TotalComments * 0.3 + ues.TotalBadges * 0.2) AS WeightedUserActivityScore,
    -- String operations on user's AboutMe to extract first paragraph if present
    TRIM(SUBSTRING(u.AboutMe, POSITION('<p>' IN u.AboutMe) + 3,
                   CASE WHEN POSITION('</p>' IN u.AboutMe) > POSITION('<p>' IN u.AboutMe)
                        THEN POSITION('</p>' IN u.AboutMe) - (POSITION('<p>' IN u.AboutMe) + 3)
                        ELSE LENGTH(u.AboutMe)
                   END)) AS AboutMeFirstParagraph,
    -- Date difference calculation
    EXTRACT(DAY FROM AGE(u.LastAccessDate, u.CreationDate)) AS DaysSinceCreationToLastAccess,
    -- A simple EXISTS correlated subquery
    EXISTS (
        SELECT 1
        FROM Badges b_sub
        WHERE b_sub.UserId = ues.UserId
          AND b_sub.Class = 1 -- Gold badges
          AND b_sub.TagBased = TRUE
    ) AS HasGoldTagBadge
FROM Users u
RIGHT JOIN UserEngagementSummary ues ON u.Id = ues.UserId -- RIGHT JOIN for variety
LEFT JOIN PostContentAnalysis pca ON u.Id = pca.OwnerUserId
LEFT JOIN LATERAL unnest(pca.TagArray) AS unnested_tag(tag) ON TRUE -- Simulate row-wise operation for tag processing
LEFT JOIN TagPerformanceMetrics tpm ON UPPER(unnested_tag.tag) = tpm.TagName
LEFT JOIN PostHistory ph ON pca.PostId = ph.PostId
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN CloseReasonTypes closereason ON ph.PostHistoryTypeId = 10 AND ph.Comment = closereason.Id::varchar -- Conditional join based on PostHistoryTypeId
LEFT JOIN Users users_editor ON ph.UserId = users_editor.Id -- Join for editor details in PostHistory
LEFT JOIN PostLinks pl ON pca.PostId = pl.PostId
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN Posts related_post ON pl.RelatedPostId = related_post.Id -- Get title of related post
WHERE
    ues.Reputation > 1000 -- Filter users with significant reputation
    AND pca.PostScore IS NOT NULL AND pca.ViewCount IS NOT NULL -- Exclude posts without scores/views
    AND (pca.PostTypeId = 1 AND pca.AnswerCount >= 1 OR pca.PostTypeId = 2 AND pca.PostScore > 5) -- Complicated OR predicate
    AND (
        ph.PostHistoryTypeId IN (4, 5, 6, 10, 11) -- Edited, Closed, or Reopened posts
        OR (ph.PostHistoryTypeId IS NULL AND u.LastAccessDate > u.CreationDate + INTERVAL '1 year') -- Users active for over a year with no history for these types
    )
    AND u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 50 -- Users with substantial 'About Me' sections
    AND u.Location LIKE '%United States%' -- String search in Location
    AND pca.EngagementRatio IS NOT NULL AND pca.EngagementRatio > (SELECT AVG(EngagementRatio) FROM PostContentAnalysis WHERE EngagementRatio IS NOT NULL) -- Non-correlated subquery in WHERE
ORDER BY
    ues.WeightedUserActivityScore DESC,
    tpm.AverageTagQuestionScore DESC NULLS LAST, -- NULLS LAST for tags that might not have performance metrics
    pca.AvgOwnerScoreLast30Days DESC
LIMIT 500;
