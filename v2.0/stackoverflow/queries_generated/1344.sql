-- {"query": "1344.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2056} 

WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.OwnerUserId = u.Id THEN 1 ELSE 0 END) AS AnswersAccepted,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(p.LastActivityDate) AS LastPostActivity,
        -- Complex reputation impact calculation
        (u.Reputation * 0.1 + u.UpVotes * 0.5 - u.DownVotes * 0.2 + COUNT(DISTINCT b.Id) * 10) AS UserInfluenceScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation >= 500
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes
),
PostHistoricalMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        p.Title,
        COALESCE(p.Tags, '') AS TagsString,
        (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS LatestEditDate,
        (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS EditCount,
        (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinksCount,
        (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicatesCount,
        -- Correlated subquery for specific history event count
        (
            SELECT SUM(CASE WHEN ph_event.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) -- Post Closed
            FROM PostHistory ph_event
            WHERE ph_event.PostId = p.Id
        ) AS ClosedEventCount,
        -- Conditional categorization
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            WHEN p.Score >= 100 AND p.ViewCount >= 50000 THEN 'Viral'
            WHEN p.AnswerCount >= 10 AND p.FavoriteCount >= 50 THEN 'HighlyAnsweredAndFavorited'
            ELSE 'Standard'
        END AS PostStatusCategory
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
TopTagsByPostCount AS (
    SELECT
        LOWER(TRIM(SUBSTRING(unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')), 1, 50))) AS TagName, -- Extract and clean tags
        COUNT(p.Id) AS TagPostCount
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.Tags != ''
    GROUP BY TagName
    HAVING COUNT(p.Id) > 1000
)
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.UserInfluenceScore,
    ues.QuestionsAsked,
    ues.AnswersGiven,
    ues.TotalPosts,
    ues.TotalComments,
    pm.PostId,
    pm.Title AS PostTitle,
    pm.PostCreationDate,
    pm.Score AS PostScore,
    pm.ViewCount AS PostViewCount,
    pm.AnswerCount,
    pm.CommentCount,
    pm.FavoriteCount,
    pm.PostStatusCategory,
    pm.EditCount,
    pm.LinksCount,
    pm.DuplicatesCount,
    pm.ClosedEventCount,
    pm.TagsString,
    -- Join to get the owner display name for answers if it's an answer post
    COALESCE(answer_owner.DisplayName, 'Deleted User') AS AnswerOwnerDisplayNameIfApplicable,
    -- Complicated expression with NULL logic
    CASE
        WHEN pm.Score >= 50 AND pm.AnswerCount IS NOT NULL AND pm.AnswerCount > 0 THEN
            (CAST(pm.Score AS NUMERIC) / pm.AnswerCount) * COALESCE(pm.FavoriteCount, 0.5)
        WHEN pm.Score >= 10 THEN CAST(pm.Score AS NUMERIC) * 0.75
        ELSE 0.0
    END AS PostEngagementRatio,
    -- String manipulations
    REPLACE(REPLACE(REPLACE(pm.TagsString, '<', ''), '>', ' '), '  ', ' ') AS FormattedTagsList,
    -- Date difference and calculation
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - pm.PostCreationDate)) / (60 * 60 * 24) AS DaysSincePostCreation,
    -- Window functions
    ROW_NUMBER() OVER (PARTITION BY ues.UserId ORDER BY pm.Score DESC, pm.ViewCount DESC) AS RankOfPostByUser,
    SUM(pm.Score) OVER (PARTITION BY ues.UserId ORDER BY pm.PostCreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS RollingAvgUserPostScore,
    NTILE(10) OVER (ORDER BY ues.UserInfluenceScore DESC) AS UserInfluenceTier,
    LAG(pm.PostScore, 1, 0) OVER (PARTITION BY ues.UserId ORDER BY pm.PostCreationDate) AS PreviousPostScore,
    -- Correlated subquery in SELECT for latest comment
    (SELECT c_latest.Text FROM Comments c_latest WHERE c_latest.PostId = pm.PostId ORDER BY c_latest.CreationDate DESC LIMIT 1) AS LatestCommentText,
    -- Conditional check against a set of top tags (from CTE)
    CASE
        WHEN EXISTS (
            SELECT 1 FROM TopTagsByPostCount t
            WHERE pm.TagsString LIKE '%' || t.TagName || '%'
        ) THEN 'ContainsTopTag'
        ELSE 'NoTopTag'
    END AS TagPopularityClassification
FROM UserEngagementSummary ues
LEFT JOIN PostHistoricalMetrics pm ON ues.UserId = pm.OwnerUserId
LEFT JOIN Users answer_owner ON pm.OwnerUserId = answer_owner.Id AND pm.PostTypeId = 2 -- For answers, get the owner's display name
WHERE
    ues.UserInfluenceScore > 1000
    AND pm.PostId IS NOT NULL -- Only include users with at least one matched post
    AND pm.PostCreationDate BETWEEN ues.UserCreationDate AND CURRENT_TIMESTAMP - INTERVAL '1 year' -- Posts after user creation but not extremely recent
    AND (pm.Title LIKE '%performance%' OR pm.Title LIKE '%optimize%') -- Filtering based on title keywords
    AND pm.TagsString LIKE '%<javascript>%' -- Specific tag
    AND pm.PostStatusCategory != 'Closed' -- Exclude closed posts
    AND pm.ClosedEventCount IS NOT NULL AND pm.ClosedEventCount = 0 -- Ensure it was never closed
    -- Complicated boolean logic with NULL checks
    AND (
        (pm.Score > 20 AND pm.AnswerCount > 5 AND pm.ViewCount IS NOT NULL)
        OR
        (pm.FavoriteCount IS NOT NULL AND pm.FavoriteCount > 10 AND pm.EditCount > 2)
        OR
        (pm.LinksCount > 0 AND pm.DuplicatesCount = 0 AND pm.LatestEditDate IS NOT NULL AND pm.PostCreationDate > CURRENT_TIMESTAMP - INTERVAL '3 year')
    )
ORDER BY
    ues.UserInfluenceScore DESC,
    UserInfluenceTier ASC,
    PostEngagementRatio DESC,
    DaysSincePostCreation ASC
LIMIT 5000;
