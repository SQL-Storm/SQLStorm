-- {"query": "1171.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3030}
WITH UserActivitySummary AS (
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
    LEFT JOIN PostHistory ph_edit ON u.Id = ph_edit.UserId AND ph_edit.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostDetailsExtended AS (
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
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedFromCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateOfCount,
        MAX(ph_close.CreationDate) AS LastClosedDateFromHistory,
        (
            SELECT c.Text
            FROM Comments c
            WHERE c.PostId = p.Id AND c.UserId = p.OwnerUserId
            ORDER BY c.CreationDate DESC
            LIMIT 1
        ) AS LatestOwnerComment,
        (
            SELECT AVG(ans.Score)
            FROM Posts ans
            WHERE ans.ParentId = p.Id AND ans.PostTypeId = 2
        ) AS AvgAnswerScoreForQuestion,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostScoreRankByUser,
        CASE
            WHEN p.OwnerUserId IS NOT NULL AND p.LastEditorUserId IS NOT NULL AND p.OwnerUserId <> p.LastEditorUserId THEN TRUE
            ELSE FALSE
        END AS EditedByOtherUser,
        CASE
            WHEN LENGTH(p.Body) < 200 THEN 'Short'
            WHEN LENGTH(p.Body) BETWEEN 200 AND 1000 THEN 'Medium'
            ELSE 'Long'
        END AS BodySizeCategory,
        (LOWER(p.Tags) LIKE '%<sql>%' OR LOWER(p.Tags) LIKE '%<database>%') AS HasSqlDatabaseTag,
        (
            SELECT u_edit_hist.Reputation
            FROM Users u_edit_hist
            WHERE u_edit_hist.Id = p.LastEditorUserId
        ) AS LastEditorReputation
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u_owner ON p.OwnerUserId = u_owner.Id
    LEFT JOIN Users u_editor ON p.LastEditorUserId = u_editor.Id
    LEFT JOIN PostLinks pl ON p.Id = pl.RelatedPostId
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10
    GROUP BY
        p.Id, p.PostTypeId, pt.Name, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.LastEditDate, p.LastActivityDate, p.ClosedDate,
        p.Tags, p.Body, p.OwnerDisplayName, u_owner.DisplayName, p.LastEditorDisplayName, u_editor.DisplayName,
        p.LastEditorUserId
),
UserPostTiming AS (
    SELECT
        p_all.OwnerUserId AS UserId,
        p_all.Id AS PostId,
        p_all.CreationDate AS CurrentPostDate,
        LAG(p_all.CreationDate, 1, p_all.CreationDate) OVER (PARTITION BY p_all.OwnerUserId ORDER BY p_all.CreationDate) AS PreviousPostDate
    FROM Posts p_all
    WHERE p_all.OwnerUserId IS NOT NULL
)
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
    CASE
        WHEN uas.GoldBadges > 0 AND uas.Reputation > 50000 THEN 'Elite Contributor'
        WHEN uas.QuestionsAsked > 100 AND uas.AnswersProvided > 100 THEN 'Prolific All-Rounder'
        WHEN uas.AvgQuestionScore >= 20 AND uas.QuestionsAsked >= 50 THEN 'Impactful Questioner'
        ELSE 'Active User'
    END AS UserCategory,
    COALESCE(pde.PostScore * pde.ViewCount / NULLIF(pde.AnswerCount, 0), 0) AS EngagementMetric,
    CASE
        WHEN pde.ClosedDate IS NOT NULL AND pde.LastClosedDateFromHistory >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months') THEN 'Recently Closed Post'
        ELSE 'Not Recently Closed'
    END AS ClosureStatus,
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
    pde.PostTypeId = 1
    AND pde.PostScore >= 5
    AND pde.PostScoreRankByUser <= 5
    AND pde.ViewCount >= 1000
    AND pde.AnswerCount >= 2
    AND uas.Reputation >= 1000
    AND uas.DaysActive > 30
    AND pde.HasSqlDatabaseTag IS TRUE
    AND pde.EditedByOtherUser IS TRUE
    AND pde.LastEditorReputation IS NOT NULL AND pde.LastEditorReputation > uas.Reputation * 0.5
    AND (
        pde.AvgAnswerScoreForQuestion IS NULL
        OR pde.AvgAnswerScoreForQuestion > 0
    )
    AND uas.UserId IN (
        SELECT DISTINCT p_recent.OwnerUserId
        FROM Posts p_recent
        WHERE p_recent.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
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
    MAX(COALESCE(pde.PostScore * pde.ViewCount / NULLIF(pde.AnswerCount, 0), 0)) > 1000
ORDER BY
    uas.Reputation DESC, pde.PostScore DESC
LIMIT 100;