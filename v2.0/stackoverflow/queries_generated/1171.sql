-- {"query": "1171.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3030} 

WITH UserActivitySummary AS (
    -- Summarize user activity, including reputation, post counts, and activity metrics
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        DATE_PART('day', u.LastAccessDate - u.CreationDate) AS DaysActive,
        u.UpVotes,
        u.DownVotes,
        (CAST(u.UpVotes AS NUMERIC) - u.DownVotes) AS VoteDifference,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS TotalQuestionScore,
        COALESCE(AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END), 0.0) AS AvgQuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS TotalAnswerScore,
        COALESCE(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 0.0) AS AvgAnswerScore,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        MAX(b.Date) AS LastBadgeDate,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT ph_edit.Id) AS TotalEditsMade
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph_edit ON u.Id = ph_edit.UserId AND ph_edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostDetailsExtended AS (
    -- Elaborate post details, including linked posts, comments, and history
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastEditDate,
        p.LastActivityDate,
        p.ClosedDate,
        p.Tags,
        LENGTH(p.Body) AS BodyLength,
        COALESCE(p.OwnerDisplayName, u_owner.DisplayName, 'Community') AS ActualOwnerDisplayName,
        COALESCE(p.LastEditorDisplayName, u_editor.DisplayName, 'N/A') AS ActualLastEditorDisplayName,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedFromCount, -- Other posts link to this one
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateOfCount, -- Other posts are duplicates of this one
        MAX(ph_close.CreationDate) AS LastClosedDateFromHistory,
        -- Get the most recent comment text on this post by its owner, if any
        (
            SELECT c.Text
            FROM Comments c
            WHERE c.PostId = p.Id AND c.UserId = p.OwnerUserId
            ORDER BY c.CreationDate DESC
            LIMIT 1
        ) AS LatestOwnerComment,
        -- Calculate the average score of all answers to this question
        (
            SELECT AVG(ans.Score)
            FROM Posts ans
            WHERE ans.ParentId = p.Id AND ans.PostTypeId = 2
        ) AS AvgAnswerScoreForQuestion,
        -- Use window function to rank posts by score within a user's questions
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostScoreRankByUser,
        -- Detect posts that have been edited by someone other than the owner
        CASE
            WHEN p.OwnerUserId IS NOT NULL AND p.LastEditorUserId IS NOT NULL AND p.OwnerUserId <> p.LastEditorUserId THEN TRUE
            ELSE FALSE
        END AS EditedByOtherUser,
        -- Determine if the post body is "short" or "long"
        CASE
            WHEN LENGTH(p.Body) < 200 THEN 'Short'
            WHEN LENGTH(p.Body) BETWEEN 200 AND 1000 THEN 'Medium'
            ELSE 'Long'
        END AS BodySizeCategory,
        -- Check for presence of 'sql' or 'database' tag (case-insensitive)
        LOWER(p.Tags) LIKE '%<sql>%' OR LOWER(p.Tags) LIKE '%<database>%' AS HasSqlDatabaseTag,
        -- Calculate the reputation of the last editor at the time of the edit
        (
            SELECT u_edit_hist.Reputation
            FROM Users u_edit_hist
            WHERE u_edit_hist.Id = p.LastEditorUserId
        ) AS LastEditorReputation
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u_owner ON p.OwnerUserId = u_owner.Id
    LEFT JOIN Users u_editor ON p.LastEditorUserId = u_editor.Id
    LEFT JOIN PostLinks pl ON p.Id = pl.RelatedPostId -- links pointing TO this post
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10 -- Post Closed
    GROUP BY
        p.Id, p.PostTypeId, pt.Name, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.LastEditDate, p.LastActivityDate, p.ClosedDate,
        p.Tags, p.Body, p.OwnerDisplayName, u_owner.DisplayName, p.LastEditorDisplayName, u_editor.DisplayName,
        p.LastEditorUserId
),
UserPostTiming AS (
    -- Calculate time differences between consecutive posts for a user
    SELECT
        p_all.OwnerUserId AS UserId,
        p_all.Id AS PostId,
        p_all.CreationDate AS CurrentPostDate,
        LAG(p_all.CreationDate, 1, p_all.CreationDate) OVER (PARTITION BY p_all.OwnerUserId ORDER BY p_all.CreationDate) AS PreviousPostDate
    FROM Posts p_all
    WHERE p_all.OwnerUserId IS NOT NULL
)
-- Main Query: Combine information to find highly engaged users with popular posts
SELECT
    uas.UserId,
    uas.UserDisplayName,
    uas.Reputation,
    uas.DaysActive,
    uas.VoteDifference,
    uas.QuestionsAsked,
    uas.AnswersProvided,
    uas.AvgQuestionScore,
    uas.AvgAnswerScore,
    uas.TotalCommentsMade,
    uas.LastCommentDate,
    uas.TotalEditsMade,
    pde.PostId,
    pde.PostTypeName,
    pde.Title,
    pde.PostCreationDate,
    pde.PostScore,
    pde.ViewCount,
    pde.AnswerCount,
    pde.CommentCount,
    pde.FavoriteCount,
    pde.BodySizeCategory,
    pde.LinkedFromCount,
    pde.DuplicateOfCount,
    pde.LatestOwnerComment,
    pde.AvgAnswerScoreForQuestion,
    pde.EditedByOtherUser,
    pde.LastEditorReputation,
    pde.HasSqlDatabaseTag,
    DATE_PART('hour', upt.CurrentPostDate - upt.PreviousPostDate) AS HoursSincePreviousPost,
    -- Check if the user has any gold badges and a very high reputation
    CASE
        WHEN uas.GoldBadges > 0 AND uas.Reputation > 50000 THEN 'Elite Contributor'
        WHEN uas.QuestionsAsked > 100 AND uas.AnswersProvided > 100 THEN 'Prolific All-Rounder'
        WHEN uas.AvgQuestionScore >= 20 AND uas.QuestionsAsked >= 50 THEN 'Impactful Questioner'
        ELSE 'Active User'
    END AS UserCategory,
    -- Determine if the post is a highly viewed question that also has an accepted answer
    COALESCE(pde.PostScore * pde.ViewCount / NULLIF(pde.AnswerCount, 0), 0) AS EngagementMetric, -- complicated calculation with NULL handling
    -- Conditional check for posts closed recently by a specific reason (using PostHistory join implicitly in CTE)
    CASE
        WHEN pde.ClosedDate IS NOT NULL AND pde.LastClosedDateFromHistory >= (NOW() - INTERVAL '6 months') THEN 'Recently Closed Post'
        ELSE 'Not Recently Closed'
    END AS ClosureStatus,
    -- Correlated subquery: check if this user has ever had a post with > 50 favorite counts AND > 10 answers
    EXISTS (
        SELECT 1
        FROM Posts p_fav
        WHERE p_fav.OwnerUserId = uas.UserId
          AND p_fav.FavoriteCount > 50
          AND p_fav.AnswerCount > 10
          AND p_fav.PostTypeId = 1
    ) AS HasHighlyPopularQuestion
FROM UserActivitySummary uas
INNER JOIN PostDetailsExtended pde ON uas.UserId = pde.OwnerUserId
LEFT JOIN UserPostTiming upt ON uas.UserId = upt.UserId AND pde.PostId = upt.PostId
WHERE
    pde.PostTypeId = 1 -- Focus on questions
    AND pde.PostScore >= 5 -- Only show questions with a decent score
    AND pde.PostScoreRankByUser <= 5 -- Top 5 questions by score for each user
    AND pde.ViewCount >= 1000 -- High view count
    AND pde.AnswerCount >= 2 -- At least two answers
    AND uas.Reputation >= 1000 -- Filter for users with significant reputation
    AND uas.DaysActive > 30 -- Active for more than a month
    AND pde.HasSqlDatabaseTag IS TRUE -- Specifically interested in SQL/Database related posts
    AND pde.EditedByOtherUser IS TRUE -- Post was edited by someone other than the owner
    AND pde.LastEditorReputation IS NOT NULL AND pde.LastEditorReputation > uas.Reputation * 0.5 -- Editor has at least 50% of owner's reputation, ensure editor exists
    AND (
        pde.AvgAnswerScoreForQuestion IS NULL -- No answers yet
        OR pde.AvgAnswerScoreForQuestion > 0 -- or answers exist and have a positive average score
    )
    -- This IN subquery acts like a set operator check: ensure user has posted something recently (within 1 year) with a score >= 10
    AND uas.UserId IN (
        SELECT DISTINCT p_recent.OwnerUserId
        FROM Posts p_recent
        WHERE p_recent.CreationDate >= (NOW() - INTERVAL '1 year')
          AND p_recent.Score >= 10
          AND p_recent.OwnerUserId IS NOT NULL
    )
GROUP BY
    uas.UserId, uas.UserDisplayName, uas.Reputation, uas.DaysActive, uas.VoteDifference, uas.QuestionsAsked,
    uas.AnswersProvided, uas.AvgQuestionScore, uas.AvgAnswerScore, uas.TotalCommentsMade, uas.LastCommentDate,
    uas.TotalEditsMade, pde.PostId, pde.PostTypeName, pde.Title, pde.PostCreationDate, pde.PostScore,
    pde.ViewCount, pde.AnswerCount, pde.CommentCount, pde.FavoriteCount, pde.BodySizeCategory,
    pde.LinkedFromCount, pde.DuplicateOfCount, pde.LatestOwnerComment, pde.AvgAnswerScoreForQuestion,
    pde.EditedByOtherUser, pde.LastEditorReputation, pde.HasSqlDatabaseTag,
    upt.CurrentPostDate, upt.PreviousPostDate, pde.ClosedDate, pde.LastClosedDateFromHistory, uas.GoldBadges
HAVING
    MAX(pde.EngagementMetric) > 1000 -- Ensure at least one post has a high engagement
ORDER BY
    uas.Reputation DESC, pde.PostScore DESC
LIMIT 100;
