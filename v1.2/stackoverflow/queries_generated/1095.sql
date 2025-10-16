-- {"query": "1095.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1316} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.Id] AS Ancestors
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        t.Count,
        r.Ancestors || t.Id
    FROM Tags t
    INNER JOIN RecursiveTagHierarchy r ON t.Id <> ALL(r.Ancestors) 
    WHERE t.IsModeratorOnly = 0
),
UserActivityRanked AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COALESCE(SUM(vtpt.VotesCount),0) AS TotalPostVotes,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC, COUNT(DISTINCT b.Id) DESC) AS LocationRank
    FROM Users u
    LEFT JOIN (
        SELECT p.OwnerUserId, COUNT(v.Id) AS VotesCount
        FROM Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3) -- UpMod and DownMod
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ) vtpt ON vtpt.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.CreationDate <= CURRENT_TIMESTAMP - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
QuestionAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreation,
        q.OwnerUserId AS QuestionOwner,
        COALESCE(q.Score,0) AS QuestionScore,
        q.AnswerCount,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwner,
        a.CreationDate AS AnswerCreation,
        a.Score AS AnswerScore,
        a.ParentId,
        CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAcceptedAnswer,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
      AND q.ClosedDate IS NULL
),
RecentActivity AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.Comment,
        ph.Text,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.CreationDate > CURRENT_TIMESTAMP - INTERVAL '3 months'
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        SUM(CASE WHEN c.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 week' THEN 1 ELSE 0 END) AS CommentsLastWeek
    FROM Comments c
    GROUP BY c.UserId
),
DuplicateQuestions AS (
    SELECT
        pl.PostId AS DuplicateId,
        pl.RelatedPostId AS OriginalId,
        q1.Title AS DuplicateTitle,
        q2.Title AS OriginalTitle,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotes,
        MAX(ph.CreationDate) AS LastCloseVoteDate
    FROM PostLinks pl
    INNER JOIN Posts q1 ON q1.Id = pl.PostId AND q1.PostTypeId = 1
    INNER JOIN Posts q2 ON q2.Id = pl.RelatedPostId AND q2.PostTypeId = 1
    LEFT JOIN PostHistory ph ON ph.PostId = pl.PostId AND ph.PostHistoryTypeId = 10
    WHERE pl.LinkTypeId = 3 -- Duplicate
    GROUP BY pl.PostId, pl.RelatedPostId, q1.Title, q2.Title
),
UserBadgeStrings AS (
    SELECT
        b.UserId,
        STRING_AGG(b.Name || ' (' || CASE b.Class WHEN 1 THEN 'Gold' WHEN 2 THEN 'Silver' ELSE 'Bronze' END || ')', ', ' ORDER BY b.Date DESC) AS BadgesList
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    uar.DisplayName,
    uar.Location,
    uar.Reputation,
    uar.TotalPostVotes,
    uar.BadgeCount,
    ub.BadgesList,
    COALESCE(uc.TotalComments,0) AS TotalComments,
    COALESCE(uc.AvgCommentLength,0) AS AvgCommentLength,
    COALESCE(uc.CommentsLastWeek,0) AS CommentsLastWeek,
    q.QuestionTitle,
    q.QuestionScore,
    q.AnswerCount,
    q.AnswerId,
    q.AnswerScore,
    q.IsAcceptedAnswer,
    ROW_NUMBER() OVER (PARTITION BY uar.Location ORDER BY uar.Reputation DESC) AS RankInLocation,
    CASE 
        WHEN q.QuestionScore < 0 THEN 'LowScore'
        WHEN q.AnswerScore > 10 THEN 'HighAnswerScore'
        ELSE 'Normal'
    END AS QuestionAnswerStatus,
    dt.DuplicateTitle,
    dt.OriginalTitle,
    dt.CloseVotes,
    dt.LastCloseVoteDate
FROM UserActivityRanked uar
LEFT JOIN UserCommentStats uc ON uc.UserId = uar.UserId
LEFT JOIN UserBadgeStrings ub ON ub.UserId = uar.UserId
LEFT JOIN QuestionAnswers q ON q.QuestionOwner = uar.UserId AND q.AnswerRank = 1
LEFT JOIN DuplicateQuestions dt ON dt.DuplicateId = q.QuestionId
WHERE uar.Location IS NOT NULL
  AND uar.TotalPostVotes > 10
ORDER BY uar.Location, uar.Reputation DESC, q.QuestionScore DESC;
