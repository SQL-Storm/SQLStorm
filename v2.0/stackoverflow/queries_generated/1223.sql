-- {"query": "1223.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3316} 

WITH UserEngagement AS (
    -- CTE 1: Summarize user engagement metrics for users who have at least one post,
    -- distinguishing between question askers and answerers.
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
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostViewCount,
        -- Calculate the average length of their 'AboutMe' section, handling NULLs
        AVG(NULLIF(LENGTH(u.AboutMe), 0)) AS AvgAboutMeLength,
        -- Count of distinct badges, partitioned by Class (correlated subqueries)
        (SELECT COUNT(DISTINCT b_inner.Id) FROM Badges b_inner WHERE b_inner.UserId = u.Id AND b_inner.Class = 1) AS GoldBadges,
        (SELECT COUNT(DISTINCT b_inner.Id) FROM Badges b_inner WHERE b_inner.UserId = u.Id AND b_inner.Class = 2) AS SilverBadges,
        (SELECT COUNT(DISTINCT b_inner.Id) FROM Badges b_inner WHERE b_inner.UserId = u.Id AND b_inner.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
QuestionAnalysis AS (
    -- CTE 2: Analyze questions with their accepted answers and related user data.
    -- Includes window functions for ranking and string manipulation for tags.
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionDate,
        q.ViewCount,
        q.Score AS QuestionScore,
        q.AnswerCount,
        q.OwnerUserId AS QuestionOwnerId,
        q.AcceptedAnswerId,
        COALESCE(a.Score, 0) AS AcceptedAnswerScore,
        a.OwnerUserId AS AcceptedAnswerOwnerId,
        ph_close.CreationDate AS LastCloseDate,
        (SELECT COUNT(DISTINCT ph_inner.UserId) FROM PostHistory ph_inner WHERE ph_inner.PostId = q.Id AND ph_inner.PostHistoryTypeId IN (4, 5, 6)) AS DistinctEditorsCount,
        -- Extract tags and count a specific tag if present
        CASE
            WHEN q.Tags IS NOT NULL AND POSITION('<sql>' IN q.Tags) > 0 THEN 1
            ELSE 0
        END AS HasSqlTag,
        -- Rank questions by view count within the same creation year (Window Function)
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM q.CreationDate) ORDER BY q.ViewCount DESC, q.Score DESC) AS RankByViewsInYear,
        -- Calculate the difference in days between question creation and its first edit (if any)
        (
            SELECT MIN(EXTRACT(EPOCH FROM (ph_edit.CreationDate - q.CreationDate)) / 86400)
            FROM PostHistory ph_edit
            WHERE ph_edit.PostId = q.Id AND ph_edit.PostHistoryTypeId IN (4, 5, 6)
        ) AS DaysToFirstEdit,
        -- Check if the question has a 'duplicate' link (EXISTS subquery)
        EXISTS (
            SELECT 1 FROM PostLinks pl WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3
        ) AS IsDuplicate,
        -- Get the most recent edit's comment text, if available and from a specific type
        (
            SELECT ph_comment.Comment
            FROM PostHistory ph_comment
            WHERE ph_comment.PostId = q.Id AND ph_comment.PostHistoryTypeId = 5 -- Edit Body
            ORDER BY ph_comment.CreationDate DESC
            LIMIT 1
        ) AS LastEditCommentSnippet
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id AND a.PostTypeId = 2
    LEFT JOIN PostHistory ph_close ON q.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10 -- Post Closed
    WHERE q.PostTypeId = 1
),
CommentSentiment AS (
    -- CTE 3: Analyze comments, categorizing them by score and linking to posts.
    -- Includes a window function to find the latest comment per post by a specific user.
    SELECT
        c.Id AS CommentId,
        c.PostId,
        c.UserId AS CommenterUserId,
        c.CreationDate AS CommentDate,
        c.Score AS CommentScore,
        c.Text AS CommentText,
        CASE
            WHEN c.Score >= 3 THEN 'High Score'
            WHEN c.Score <= -1 THEN 'Low Score'
            ELSE 'Neutral Score'
        END AS SentimentCategory,
        -- Find the user's previous comment date on the same post (LAG window function)
        LAG(c.CreationDate, 1, c.CreationDate) OVER (PARTITION BY c.PostId, c.UserId ORDER BY c.CreationDate) AS PreviousCommentDateByUserOnPost
    FROM Comments c
    WHERE c.Text IS NOT NULL
),
BadgesSummary AS (
    -- CTE 4: Summarize badge counts for users, focusing on recent activity and specific badge names.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount,
        -- Identify if a user has specific "popular" badges
        MAX(CASE WHEN b.Name IN ('Enthusiast', 'Mortarboard', 'Epic', 'Legendary') THEN 1 ELSE 0 END) AS HasPrestigiousBadge
    FROM Badges b
    WHERE b.Date > (CURRENT_TIMESTAMP - INTERVAL '1 year') -- Only consider recent badges
    GROUP BY b.UserId
),
MainQueryBranch1 AS (
    -- Main Query Branch 1: Focus on influential questions from active, high-reputation users, with specific content focus.
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.TotalPosts,
        qa.QuestionId,
        qa.QuestionTitle,
        qa.QuestionDate,
        qa.ViewCount,
        qa.QuestionScore,
        qa.AcceptedAnswerId,
        qa.AcceptedAnswerScore,
        qa.RankByViewsInYear,
        qa.HasSqlTag,
        COALESCE(qa.DaysToFirstEdit, 0) AS DaysUntilFirstEdit,
        qa.IsDuplicate,
        -- Subquery to get the average comment score for the question
        (
            SELECT AVG(cs_inner.CommentScore)
            FROM CommentSentiment cs_inner
            WHERE cs_inner.PostId = qa.QuestionId
        ) AS AvgQuestionCommentScore,
        -- Correlated subquery: count of comments on the question by the question owner
        (
            SELECT COUNT(cs_owner.CommentId)
            FROM CommentSentiment cs_owner
            WHERE cs_owner.PostId = qa.QuestionId AND cs_owner.CommenterUserId = ue.UserId
        ) AS OwnerCommentsOnQuestion,
        COALESCE(bs.GoldBadgeCount, 0) AS RecentGoldBadges,
        COALESCE(bs.HasPrestigiousBadge, 0) AS HasRecentPrestigiousBadge,
        -- NULL logic with CASE and COALESCE for Answer Status
        CASE
            WHEN qa.AcceptedAnswerOwnerId IS NOT NULL AND qa.AcceptedAnswerOwnerId = ue.UserId THEN 'SelfAnswered'
            WHEN qa.AcceptedAnswerOwnerId IS NOT NULL AND qa.AcceptedAnswerOwnerId != ue.UserId THEN 'CommunityAnswered'
            WHEN qa.QuestionScore < 0 AND qa.AnswerCount = 0 THEN 'PoorUnanswered'
            ELSE COALESCE('NoAcceptedAnswer', 'Pending')
        END AS AnswerStatus,
        -- String expression: Truncate question title and add ellipsis if too long
        SUBSTRING(qa.QuestionTitle, 1, 50) || (CASE WHEN LENGTH(qa.QuestionTitle) > 50 THEN '...' ELSE '' END) AS ShortQuestionTitlePreview,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
        -- Complicated calculation/expression for Influence Score
        (ue.Reputation * 0.1 + qa.QuestionScore * 0.5 + ue.TotalQuestions * 0.2 + qa.ViewCount * 0.01 + COALESCE(LENGTH(qa.LastEditCommentSnippet), 0) * 0.005) AS InfluenceScore,
        'InfluentialQuestion' AS RecordType -- Identifier for UNION ALL
    FROM UserEngagement ue
    INNER JOIN QuestionAnalysis qa ON ue.UserId = qa.QuestionOwnerId
    LEFT JOIN BadgesSummary bs ON ue.UserId = bs.UserId
    LEFT JOIN PostLinks pl ON qa.QuestionId = pl.PostId AND pl.LinkTypeId = 1 -- Linked posts
    WHERE
        ue.Reputation > 1000 -- Filter for more established users
        AND ue.LastAccessDate >= (CURRENT_TIMESTAMP - INTERVAL '6 months') -- Recently active users
        AND qa.QuestionDate >= (CURRENT_TIMESTAMP - INTERVAL '3 years') -- Questions from the last 3 years
        AND qa.QuestionScore > 5 -- Filter for reasonably good questions
        AND qa.AnswerCount > 0 -- Questions that have at least one answer
        AND (
            qa.HasSqlTag = 1 OR qa.QuestionTitle ILIKE '%performance%' OR qa.QuestionTitle ILIKE '%optimize%' OR qa.QuestionTitle ILIKE '%database%'
        ) -- Questions related to SQL or performance/optimization
    GROUP BY
        ue.UserId, ue.DisplayName, ue.Reputation, ue.TotalPosts, qa.QuestionId, qa.QuestionTitle, qa.QuestionDate, qa.ViewCount, qa.QuestionScore, qa.AnswerCount,
        qa.AcceptedAnswerId, qa.AcceptedAnswerScore, qa.AcceptedAnswerOwnerId, qa.RankByViewsInYear, qa.HasSqlTag, qa.DaysToFirstEdit, qa.IsDuplicate,
        bs.GoldBadgeCount, bs.HasPrestigiousBadge, qa.LastEditCommentSnippet
    HAVING
        COUNT(DISTINCT pl.RelatedPostId) >= 1 OR qa.AcceptedAnswerOwnerId IS NOT NULL
),
MainQueryBranch2 AS (
    -- Main Query Branch 2: Focus on highly-voted questions with a significant number of comments,
    -- potentially from users with lower reputation or older activity. This branch demonstrates a set operator.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        (SELECT COUNT(p_inner.Id) FROM Posts p_inner WHERE p_inner.OwnerUserId = u.Id) AS TotalPosts,
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionDate,
        q.ViewCount,
        q.Score AS QuestionScore,
        q.AcceptedAnswerId,
        COALESCE(a.Score, 0) AS AcceptedAnswerScore,
        0 AS RankByViewsInYear, -- Not calculated in this branch, placeholder
        CASE WHEN q.Tags IS NOT NULL AND POSITION('<sql>' IN q.Tags) > 0 THEN 1 ELSE 0 END AS HasSqlTag,
        NULL AS DaysUntilFirstEdit, -- Not calculated, placeholder
        FALSE AS IsDuplicate, -- Not calculated, placeholder
        (SELECT AVG(cs_inner.CommentScore) FROM CommentSentiment cs_inner WHERE cs_inner.PostId = q.Id) AS AvgQuestionCommentScore,
        COUNT(DISTINCT c.Id) AS OwnerCommentsOnQuestion, -- Here, this means total comments on the question
        0 AS RecentGoldBadges, -- Placeholder for compatibility
        0 AS HasRecentPrestigiousBadge, -- Placeholder for compatibility
        CASE
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            ELSE 'Unanswered'
        END AS AnswerStatus,
        SUBSTRING(q.Title, 1, 50) || (CASE WHEN LENGTH(q.Title) > 50 THEN '...' ELSE '' END) AS ShortQuestionTitlePreview,
        (SELECT COUNT(pl_inner.RelatedPostId) FROM PostLinks pl_inner WHERE pl_inner.PostId = q.Id AND pl_inner.LinkTypeId = 1) AS LinkedPostsCount,
        (u.Reputation * 0.05 + q.Score * 0.7 + COUNT(DISTINCT c.Id) * 0.3) AS InfluenceScore,
        'HighlyCommentedQuestion' AS RecordType
    FROM Posts q
    INNER JOIN Users u ON q.OwnerUserId = u.Id
    LEFT JOIN Comments c ON q.Id = c.PostId
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id AND a.PostTypeId = 2
    WHERE
        q.PostTypeId = 1
        AND q.Score > 20
        AND q.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 years')
        AND q.ViewCount > 500
        AND u.Reputation > 500 -- Filter for users with some reputation
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, q.Id, q.Title, q.CreationDate, q.ViewCount, q.Score, q.AcceptedAnswerId, a.Score
    HAVING
        COUNT(DISTINCT c.Id) >= 5 -- Questions with at least 5 comments
)
-- Final result combining two distinct views of questions using UNION ALL
SELECT * FROM MainQueryBranch1
UNION ALL
SELECT * FROM MainQueryBranch2
ORDER BY InfluenceScore DESC, Reputation DESC
LIMIT 2000;
