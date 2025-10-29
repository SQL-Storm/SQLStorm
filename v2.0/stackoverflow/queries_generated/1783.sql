-- {"query": "1783.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2960} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        MAX(p.CreationDate) AS LatestPostDate,
        MAX(c.CreationDate) AS LatestCommentDate,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(b.Date) AS LatestBadgeDate,
        -- PostgreSQL specific: Aggregate distinct badge names into an array
        ARRAY_AGG(DISTINCT b.Name ORDER BY b.Name) FILTER (WHERE b.Name IS NOT NULL) AS UserBadgeNames
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostDetailsWithEngagement AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount AS PostTableCommentCount, -- From Posts table directly
        p.FavoriteCount,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.ClosedDate,
        COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId, -- Use -1 for consistency when NULL
        -- Window function: Rank posts by score within each post type, considering creation date as tie-breaker
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostRankByScoreType,
        -- Correlated subquery: Get the text of the most recent body edit/initial content
        (
            SELECT ph_inner.Text
            FROM PostHistory AS ph_inner
            WHERE ph_inner.PostId = p.Id
              AND ph_inner.PostHistoryTypeId IN (2, 5, 8) -- Initial Body, Edit Body, Rollback Body
            ORDER BY ph_inner.CreationDate DESC
            LIMIT 1
        ) AS LatestBodyContent,
        -- Aggregate comment scores for the post from Comments table
        COALESCE(SUM(co.Score), 0) AS TotalRelatedCommentScore,
        COUNT(DISTINCT co.Id) AS AggregatedCommentCount,
        -- Calculate post "freshness" in days
        EXTRACT(DAY FROM (CURRENT_TIMESTAMP - p.CreationDate)) AS DaysSinceCreation,
        -- Determine if post is an old or new type of closed reason based on PostHistory comment
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN
                (SELECT
                    CASE
                        WHEN CAST(phc.Comment AS INTEGER) >= 100 THEN 'NewReason'
                        WHEN CAST(phc.Comment AS INTEGER) < 100 THEN 'OldReason'
                        ELSE 'UnknownReason' -- Should not happen if CloseReasonId is always integer
                    END
                FROM PostHistory phc
                WHERE phc.PostId = p.Id
                  AND phc.PostHistoryTypeId = 10 -- Post Closed
                  AND phc.Comment IS NOT NULL AND phc.Comment ~ '^[0-9]+$' -- Ensure comment is a number
                ORDER BY phc.CreationDate DESC
                LIMIT 1)
            ELSE 'NotClosed'
        END AS CloseReasonCategory,
        -- Window function: Calculate the time difference (in seconds) between current and previous edit date for a post
        EXTRACT(EPOCH FROM (p.LastEditDate - LAG(p.LastEditDate, 1, p.CreationDate) OVER (PARTITION BY p.Id ORDER BY p.LastEditDate NULLS FIRST))) AS TimeSincePreviousEditSeconds
    FROM Posts AS p
    INNER JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments AS co ON p.Id = co.PostId
    GROUP BY p.Id, p.PostTypeId, pt.Name, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.LastActivityDate, p.Title, p.Tags, p.ClosedDate, p.AcceptedAnswerId, p.LastEditDate
),
RelatedPostImpact AS (
    -- Set operator: UNION ALL to combine linked and duplicate posts for comprehensive impact analysis
    SELECT
        pl.PostId AS SourcePostId,
        pl.RelatedPostId AS TargetPostId,
        lt.Name AS LinkTypeName,
        1 AS ImpactFactor -- Linked posts
    FROM PostLinks AS pl
    INNER JOIN LinkTypes AS lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Id = 1 -- Linked
    UNION ALL
    SELECT
        pl.PostId AS SourcePostId,
        pl.RelatedPostId AS TargetPostId,
        lt.Name AS LinkTypeName,
        2 AS ImpactFactor -- Duplicate posts potentially signal higher relatedness or problematic content
    FROM PostLinks AS pl
    INNER JOIN LinkTypes AS lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Id = 3 -- Duplicate
),
TagAnalysis AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS QuestionsWithTag,
        COALESCE(SUM(p.Score), 0) AS TotalTagScore,
        AVG(p.Score) AS AvgTagScore,
        MAX(p.CreationDate) AS LatestTagQuestionDate,
        -- Correlated subquery: Get the body of the associated wiki post for the tag
        (
            SELECT wp.Body
            FROM Posts AS wp
            WHERE wp.Id = t.WikiPostId
            LIMIT 1
        ) AS TagWikiBodyExcerpt
    FROM Tags AS t
    INNER JOIN Posts AS p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%') AND p.PostTypeId = 1 -- Only questions for tag analysis
    GROUP BY t.TagName, t.WikiPostId
)
-- Main query combining all CTEs and further complex logic for a performance benchmark
SELECT
    uas.UserId,
    COALESCE(uas.DisplayName, 'Unknown User') AS DisplayName,
    uas.Reputation,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalPostScore,
    uas.TotalComments,
    uas.TotalCommentScore,
    uas.TotalBadges,
    uas.UserBadgeNames,
    MAX(pd.PostScore) AS MaxPostScore,
    AVG(pd.PostScore) AS AvgPostScore,
    SUM(pd.ViewCount) AS TotalViewsForUserPosts,
    -- Window function: NTILE to categorize users by reputation into 5 distinct groups
    NTILE(5) OVER (ORDER BY uas.Reputation DESC) AS ReputationTier,
    -- Complicated calculation: User's influence score, incorporating various weighted metrics
    (uas.Reputation * 0.15
     + uas.TotalPostScore * 0.40
     + uas.TotalCommentScore * 0.10
     + uas.TotalBadges * 1.2
     + COALESCE(SUM(rpi.ImpactFactor * (pd.PostScore + pd.ViewCount / 100)), 0) * 0.05 -- Impact from related posts, weighted by target post's score/views
     + COALESCE(AVG(pd.TimeSincePreviousEditSeconds), 0) * -0.00001 -- Penalize frequently edited posts (negative weight)
    ) AS UserInfluenceScore,
    -- String expression: Extract clean domain from WebsiteUrl, handle NULL and multiple path parts
    NULLIF(SPLIT_PART(REPLACE(REPLACE(u.WebsiteUrl, 'http://', ''), 'https://', ''), '/', 1), '') AS WebsiteDomain,
    -- Conditional expression based on user's recent activity pattern
    CASE
        WHEN uas.LatestPostDate IS NOT NULL AND (uas.LatestCommentDate IS NULL OR uas.LatestPostDate > uas.LatestCommentDate)
             AND uas.LatestPostDate > CURRENT_TIMESTAMP - INTERVAL '30 days' THEN 'Active Poster'
        WHEN uas.LatestCommentDate IS NOT NULL AND (uas.LatestPostDate IS NULL OR uas.LatestCommentDate > uas.LatestPostDate)
             AND uas.LatestCommentDate > CURRENT_TIMESTAMP - INTERVAL '30 days' THEN 'Active Commenter'
        WHEN uas.LatestPostDate IS NULL AND uas.LatestCommentDate IS NULL THEN 'Inactive'
        ELSE 'Balanced Contributor'
    END AS UserActivityStatus,
    -- Correlated Subquery: Find the user's top-used tag based on number of questions and total score
    (
        SELECT ta.TagName
        FROM Posts p_tag
        JOIN Tags t_tag ON p_tag.Tags LIKE CONCAT('%<', t_tag.TagName, '>%')
        WHERE p_tag.OwnerUserId = uas.UserId
        GROUP BY t_tag.TagName
        ORDER BY COUNT(p_tag.Id) DESC, SUM(p_tag.Score) DESC
        LIMIT 1
    ) AS TopUsedTagByPosts,
    -- Aggregated information about closed reasons for user's posts
    STRING_AGG(DISTINCT pd.CloseReasonCategory, ', ') AS UserRelatedCloseReasons,
    -- Complex predicate combining multiple conditions and subqueries for filtering
    COUNT(CASE WHEN pd.PostTypeName = 'Question' AND pd.AnswerCount >= 1 AND pd.ClosedDate IS NULL AND pd.PostScore > 0 THEN pd.PostId ELSE NULL END) AS SolvedOpenPositiveQuestions,
    AVG(CASE WHEN pd.PostTypeId = 1 AND pd.ViewCount > 1000 THEN pd.DaysSinceCreation ELSE NULL END) AS AvgHighViewQuestionAgeDays,
    MAX(pd.LatestBodyContent) AS ExamplePostContentStart -- MAX is arbitrary, just to get one example of a complex text column
FROM UserActivitySummary AS uas
LEFT JOIN Users AS u ON uas.UserId = u.Id
LEFT JOIN PostDetailsWithEngagement AS pd ON uas.UserId = pd.OwnerUserId
LEFT JOIN RelatedPostImpact AS rpi ON pd.PostId = rpi.SourcePostId
WHERE uas.Reputation > 1000
  AND uas.TotalPosts > 10
  AND u.Location IS NOT NULL
  AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '180 days' -- Active within last 6 months
  AND (uas.UserBadgeNames IS NOT NULL AND ARRAY_LENGTH(uas.UserBadgeNames, 1) > 0) -- User has at least one badge
  AND NOT EXISTS ( -- Exclude users who have many old unedited questions
      SELECT 1
      FROM Posts p_no_edit
      WHERE p_no_edit.OwnerUserId = uas.UserId
        AND p_no_edit.PostTypeId = 1
        AND p_no_edit.LastEditorUserId IS NULL
        AND p_no_edit.CreationDate < CURRENT_DATE - INTERVAL '2 years' -- Questions older than 2 years
      GROUP BY p_no_edit.OwnerUserId
      HAVING COUNT(p_no_edit.Id) >= 5 -- User has 5 or more old questions that were never edited
  )
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.TotalPosts, uas.TotalQuestions, uas.TotalAnswers,
    uas.TotalPostScore, uas.TotalCommentScore, uas.TotalBadges, uas.UserBadgeNames,
    u.WebsiteUrl, uas.LatestPostDate, uas.LatestCommentDate, u.Location, u.LastAccessDate
HAVING SUM(CASE WHEN pd.PostTypeName = 'Answer' AND pd.PostScore > 5 THEN 1 ELSE 0 END) >= 5 -- At least 5 answers with score > 5
   AND COUNT(DISTINCT pd.PostId) > 0 -- Ensure the user actually has posts included in the PostDetailsWithEngagement CTE join
ORDER BY UserInfluenceScore DESC, uas.Reputation DESC
LIMIT 200;
