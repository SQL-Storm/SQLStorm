-- {"query": "1415.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2542} 
WITH UserEngagementSummary AS (
    -- Aggregates core engagement metrics for each user, including post and comment activity,
    -- along with badge counts and weighted average scores.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        -- Calculate the reputation density per year since creation
        u.Reputation / (EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - u.CreationDate)) / (365.25 * 24 * 60 * 60) + 1.0) AS ReputationPerYear
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostHistoricalMetrics AS (
    -- Computes various historical and linked metrics for posts, including edit counts,
    -- close votes, bounty information, and duplicate links using correlated subqueries.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.ClosedDate,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        MAX(ph.CreationDate) AS LastHistoryDate,
        -- Correlated subquery to count duplicate links pointing from this post
        (
            SELECT COUNT(DISTINCT pl_dup.RelatedPostId)
            FROM PostLinks AS pl_dup
            WHERE pl_dup.PostId = p.Id AND pl_dup.LinkTypeId = 3
        ) AS DuplicateLinkCount,
        -- Correlated subquery to sum bounty amounts offered for this post
        (
            SELECT COALESCE(SUM(v_bounty.BountyAmount), 0)
            FROM Votes AS v_bounty
            WHERE v_bounty.PostId = p.Id AND v_bounty.VoteTypeId = 8 -- BountyStart
        ) AS TotalBountyAmountOffered,
        -- Check if post has ever been migrated away
        MAX(CASE WHEN ph.PostHistoryTypeId = 35 THEN 1 ELSE 0 END) AS HasMigratedAway
    FROM Posts AS p
    LEFT JOIN PostHistory AS ph ON p.Id = ph.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Title, p.Tags, p.ClosedDate
),
UserTagPerformance AS (
    -- Ranks users' posts within a specific tag context ('<sql>') using various window functions,
    -- and identifies their top-performing post for that tag.
    SELECT
        phm.PostId,
        phm.OwnerUserId,
        phm.PostScore,
        phm.ViewCount,
        phm.AnswerCount,
        phm.Tags,
        phm.EditCount,
        phm.TotalHistoryEvents,
        -- Rank posts by score and view count for each user within the tag
        ROW_NUMBER() OVER (PARTITION BY phm.OwnerUserId ORDER BY phm.PostScore DESC, phm.ViewCount DESC, phm.PostCreationDate DESC) AS UserTagPostRank,
        -- Rank posts globally within the tag
        RANK() OVER (ORDER BY phm.PostScore DESC, phm.ViewCount DESC, phm.PostCreationDate ASC) AS GlobalTagRank,
        -- Calculate average score for user's posts in this tag
        AVG(phm.PostScore) OVER (PARTITION BY phm.OwnerUserId) AS AvgScorePerUserInTag,
        -- Compare current post's score to the previous one by the same user in chronological order
        LAG(phm.PostScore, 1, 0) OVER (PARTITION BY phm.OwnerUserId ORDER BY phm.PostCreationDate) AS PreviousPostScore,
        -- Cumulative sum of view counts for a user's posts in this tag
        SUM(phm.ViewCount) OVER (PARTITION BY phm.OwnerUserId ORDER BY phm.PostCreationDate) AS CumulativeViewCount
    FROM PostHistoricalMetrics AS phm
    WHERE
        phm.PostTypeId = 1 -- Only questions
        AND phm.Tags LIKE '%<sql>%' -- Filter for posts tagged with 'sql'
        AND phm.PostScore > 0 -- Only consider posts with positive score
        AND phm.ViewCount > 100 -- Only consider posts with significant views
)
-- Main query to find influential users based on their engagement, historical post metrics,
-- and top performance within a specific technology tag ('sql').
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.TotalPosts,
    ues.TotalComments,
    ues.TotalBadges,
    utp.PostId AS TopSqlQuestionId,
    phm_main.Title AS TopSqlQuestionTitle,
    utp.GlobalTagRank,
    utp.UserTagPostRank,
    utp.PostScore AS TopSqlQuestionScore,
    utp.ViewCount AS TopSqlQuestionViewCount,
    phm_main.AnswerCount AS TopSqlQuestionAnswerCount,
    phm_main.FavoriteCount AS TopSqlQuestionFavoriteCount,
    phm_main.EditCount AS TopSqlQuestionEditCount,
    phm_main.CloseVoteCount AS TopSqlQuestionCloseVotes,
    phm_main.DuplicateLinkCount AS TopSqlQuestionDuplicateLinks,
    phm_main.TotalBountyAmountOffered AS TopSqlQuestionBountyOffered,
    phm_main.HasMigratedAway AS TopSqlQuestionMigratedAway,
    COALESCE(utp.AvgScorePerUserInTag, 0) AS AvgUserSqlTagScore,
    -- Categorize users based on combined metrics and historical patterns
    CASE
        WHEN ues.Reputation > 10000 AND utp.GlobalTagRank <= 50 AND phm_main.AnswerCount >= 5 THEN 'SQL Guru & Top Contributor'
        WHEN ues.Reputation > 5000 AND utp.UserTagPostRank = 1 AND utp.PostScore > 100 THEN 'High-Impact SQL Specialist'
        WHEN ues.TotalQuestions >= 10 AND ues.AvgQuestionScore > 25 AND ues.ReputationPerYear > 500 THEN 'Prolific & Growing SQL Engager'
        WHEN ues.TotalBadges >= 5 AND ues.TotalComments >= 50 THEN 'Active Community Member'
        ELSE 'General Contributor'
    END AS UserInfluenceCategory,
    -- Extract and clean a snippet from the user's AboutMe section
    TRIM(COALESCE(SUBSTRING(u_users.AboutMe, 1, 75), '[No "About Me" provided]')) AS AboutMeSnippet,
    LENGTH(u_users.AboutMe) AS AboutMeLength,
    -- Calculate days since last access with NULL handling
    COALESCE(EXTRACT(DAY FROM (cast('2024-10-01 12:34:56' as timestamp) - ues.LastAccessDate)), -1) AS DaysSinceLastAccess,
    -- Complex weighted score combining post activity, comment activity, and reputation
    (ues.TotalPostScore * 0.4 + ues.TotalCommentScore * 0.2 + ues.Reputation * 0.001) /
    (UES.TotalPosts + UES.TotalComments + 1.0 + (EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - UES.UserCreationDate)) / 864000.0)) AS AdvancedEngagementIndex,
    -- Check if the top SQL question was closed and its title contains a common SQL keyword,
    -- using string manipulation and NULL checks
    (phm_main.ClosedDate IS NOT NULL AND LOWER(phm_main.Title) LIKE '%query%performance%') AS IsClosedPerformanceQuery,
    -- Determine if the user has a "legendary" badge for a specific class
    EXISTS (
        SELECT 1
        FROM Badges AS b_check
        WHERE b_check.UserId = ues.UserId
        AND b_check.Name LIKE '%Legendary%'
        AND b_check.Class = 1 -- Gold badge
    ) AS HasLegendaryGoldBadge,
    -- Calculate the ratio of previous post score to current post score (if applicable)
    COALESCE(utp.PreviousPostScore * 1.0 / utp.PostScore, 0.0) AS PrevPostScoreRatio
FROM UserEngagementSummary AS ues
INNER JOIN UserTagPerformance AS utp ON ues.UserId = utp.OwnerUserId
INNER JOIN PostHistoricalMetrics AS phm_main ON utp.PostId = phm_main.PostId
LEFT JOIN Users AS u_users ON ues.UserId = u_users.Id -- To access AboutMe from original Users table
WHERE
    utp.UserTagPostRank = 1 -- Only consider the user's top-ranked post for the 'sql' tag
    AND ues.Reputation > 1000 -- Filter for users with significant reputation
    AND ues.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months' -- Active within the last 6 months
    AND ues.TotalQuestions >= 5 -- Users who have asked at least 5 questions
    AND phm_main.ClosedDate IS NULL -- Exclude posts that are currently closed
    AND phm_main.Tags LIKE '%<sql>%'
ORDER BY
    AdvancedEngagementIndex DESC,
    utp.GlobalTagRank ASC,
    ues.Reputation DESC
LIMIT 200;