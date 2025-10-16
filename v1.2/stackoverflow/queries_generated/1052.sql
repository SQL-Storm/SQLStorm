-- {"query": "1052.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1518} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        ARRAY[t.Id] AS Path,
        1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
    UNION ALL
    SELECT
        t2.Id,
        t2.TagName,
        r.Path || t2.Id,
        r.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id != ALL(r.Path)
    WHERE t2.IsRequired = 1
),
FilteredPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.AcceptedAnswerId
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- questions or answers
      AND p.CreationDate > NOW() - INTERVAL '1 year'
      AND (p.Tags IS NOT NULL OR p.PostTypeId = 2)
),
UserAggregates AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId = 10) AS TimesPostClosed,
        COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId = 11) AS TimesPostReopened
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostComments AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'Anonymous'), ', ') AS Commenters
    FROM Comments c
    GROUP BY c.PostId
),
PostVotesSummary AS (
    SELECT
        v.PostId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod') AS UpVotes,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotes,
        COUNT(*) FILTER (WHERE vt.Name = 'Close') AS CloseVotes,
        COUNT(*) FILTER (WHERE vt.Name = 'Reopen') AS ReopenVotes,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
PostLinkStats AS (
    SELECT
        pl.PostId,
        COUNT(*) FILTER (WHERE lt.Name = 'Linked') AS LinkedCount,
        COUNT(*) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY pl.PostId
),
TopAnswers AS (
    SELECT DISTINCT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS RankAmongAnswers
    FROM Posts a
    WHERE a.PostTypeId = 2
),
MergedQuestions AS (
    SELECT ph.PostId,
           JSON_AGG(DISTINCT jsonb_build_object('MergedInto', ph.Comment)) FILTER (WHERE ph.PostHistoryTypeId = 18) AS MergedMeta
    FROM PostHistory ph
    GROUP BY ph.PostId
)
SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate AS QuestionDate,
    u.DisplayName AS QuestionOwner,
    u.Reputation AS OwnerReputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TimesPostClosed,
    ua.TimesPostReopened,
    COALESCE(pvs.UpVotes, 0) AS QuestionUpVotes,
    COALESCE(pvs.DownVotes, 0) AS QuestionDownVotes,
    COALESCE(pvs.CloseVotes, 0) AS QuestionCloseVotes,
    COALESCE(pc.CommentCount, 0) AS QuestionCommentCount,
    COALESCE(pc.AvgCommentScore, 0) AS QuestionAvgCommentScore,
    STRING_AGG(DISTINCT COALESCE(pc.Commenters, ''), ', ') AS QuestionCommenters,
    COALESCE(pls.LinkedCount, 0) AS LinkedPostsCount,
    COALESCE(pls.DuplicateCount, 0) AS DuplicatePostsCount,
    q.AcceptedAnswerId,
    ta.AnswerId AS TopAnswerId,
    ta.Score AS TopAnswerScore,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.Id AND a.Score >= 10) AS HighScoreAnswerCount,
    EXISTS (
        SELECT 1 FROM MergedQuestions mq WHERE mq.PostId = q.Id
    ) AS IsMerged,
    -- Complex string manipulation and NULL logic for tags
    COALESCE(
        NULLIF(
            REGEXP_REPLACE(
                COALESCE(q.Tags, ''), 
                '<([^>]*)>', 
                '\1', 
                'g'
            ), 
            ''
        ), 'no-tags'
    ) AS CleanedTags,
    -- Window function for ranking questions by score monthly
    RANK() OVER (
        PARTITION BY DATE_TRUNC('month', q.CreationDate)
        ORDER BY q.Score DESC NULLS LAST
    ) AS MonthlyScoreRank,
    -- Correlated subquery for last editor display name with null logic
    (
        SELECT u2.DisplayName
        FROM Users u2
        WHERE u2.Id = q.LastEditorUserId
        LIMIT 1
    ) AS LastEditorDisplayName,
    -- Complex CASE expression for question status with NULL checking and EXISTS
    CASE 
        WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Answered'
        WHEN q.CommentCount > 5 THEN 'Discussed'
        WHEN EXISTS (
            SELECT 1 FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 8 -- BountyStart
        ) THEN 'Bounty'
        ELSE 'Open'
    END AS QuestionStatus
FROM FilteredPosts q
LEFT JOIN Users u ON u.Id = q.OwnerUserId
LEFT JOIN UserAggregates ua ON ua.UserId = q.OwnerUserId
LEFT JOIN PostComments pc ON pc.PostId = q.Id
LEFT JOIN PostVotesSummary pvs ON pvs.PostId = q.Id
LEFT JOIN PostLinkStats pls ON pls.PostId = q.Id
LEFT JOIN TopAnswers ta ON ta.QuestionId = q.Id AND ta.RankAmongAnswers = 1
ORDER BY q.Score DESC NULLS LAST, q.CreationDate DESC
LIMIT 100;
