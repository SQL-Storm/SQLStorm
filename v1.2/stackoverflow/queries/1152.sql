WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        p.Id AS ExcerptPostId,
        p.OwnerUserId,
        1 AS Level
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    WHERE t.IsModeratorOnly = FALSE AND t.IsRequired = FALSE

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        p2.Id AS ExcerptPostId,
        p2.OwnerUserId,
        r.Level + 1
    FROM Tags t2
    INNER JOIN Posts p2 ON p2.Id = t2.ExcerptPostId
    INNER JOIN RecursiveTagHierarchy r ON r.OwnerUserId = p2.OwnerUserId
    WHERE t2.IsModeratorOnly = FALSE AND t2.IsRequired = FALSE AND r.Level < 3
),
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(b.Id) OVER (PARTITION BY u.Id) AS BadgeCount,
        MAX(b.Date) OVER (PARTITION BY u.Id) AS LastBadgeDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST, u.Id) AS UserRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
),
RecentPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        COALESCE(usr.DisplayName, p.OwnerDisplayName, 'Anonymous') AS PostOwnerName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS LatestPostRank
    FROM Posts p
    LEFT JOIN Users usr ON usr.Id = p.OwnerUserId
    WHERE p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '180 days')
),
TopQuestionsWithAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionDate,
        q.Score AS QuestionScore,
        q.ViewCount AS Views,
        COALESCE(usr.DisplayName, q.OwnerDisplayName, 'Anonymous') AS QuestionOwner,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        a.OwnerUserId AS AnswerOwnerId,
        a.OwnerDisplayName AS AnswerOwnerName,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users usr ON usr.Id = q.OwnerUserId
    WHERE q.PostTypeId = 1
),
AggregatedVotes AS (
    SELECT
        p.Id AS PostId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN v.Id END) AS UpVotes,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN v.Id END) AS DownVotes,
        COUNT(CASE WHEN vt.Name IN ('Close', 'Reopen') THEN v.Id END) AS CloseReopenVotes,
        MAX(CASE WHEN vt.Name = 'BountyStart' THEN v.BountyAmount ELSE NULL END) AS MaxBountyAmount
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY p.Id
),
MostCommentedQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CommentCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '30 days')) AS RecentCommentCount
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT
    tu.UserRank,
    tu.DisplayName AS UserName,
    tu.Reputation,
    tu.BadgeCount,
    tu.LastBadgeDate,
    rp.Id AS RecentPostId,
    rp.PostTypeId,
    rp.CreationDate AS RecentPostDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.PostOwnerName,
    ag.UpVotes,
    ag.DownVotes,
    ag.CloseReopenVotes,
    ag.MaxBountyAmount,
    tq.QuestionId,
    tq.Title AS QuestionTitle,
    tq.QuestionDate,
    tq.QuestionScore,
    tq.Views AS QuestionViews,
    tq.QuestionOwner,
    tq.AnswerId,
    tq.AnswerScore,
    tq.AnswerDate,
    tq.AnswerOwnerId,
    tq.AnswerOwnerName,
    mcq.CommentCount,
    mcq.RecentCommentCount,
    STRING_AGG(DISTINCT rth.TagName, ', ') FILTER (WHERE rth.Level = 1) AS Level1Tags,
    STRING_AGG(DISTINCT rth.TagName, ', ') FILTER (WHERE rth.Level = 2) AS Level2Tags,
    STRING_AGG(DISTINCT rth.TagName, ', ') FILTER (WHERE rth.Level = 3) AS Level3Tags
FROM TopUsers tu
LEFT JOIN RecentPosts rp ON rp.OwnerUserId = tu.Id AND rp.LatestPostRank = 1
LEFT JOIN AggregatedVotes ag ON ag.PostId = rp.Id
LEFT JOIN TopQuestionsWithAnswers tq ON tq.QuestionOwner = tu.DisplayName AND tq.AnswerRank = 1
LEFT JOIN Posts aq ON aq.Id = tq.AnswerId
LEFT JOIN MostCommentedQuestions mcq ON mcq.Id = tq.QuestionId
LEFT JOIN RecursiveTagHierarchy rth ON POSITION('<' || rth.TagName || '>' IN COALESCE(rp.Tags, '')) > 0
WHERE tu.UserRank <= 50
GROUP BY
    tu.UserRank, tu.DisplayName, tu.Reputation, tu.BadgeCount, tu.LastBadgeDate,
    rp.Id, rp.PostTypeId, rp.CreationDate, rp.Score, rp.ViewCount, rp.Tags, rp.PostOwnerName,
    ag.UpVotes, ag.DownVotes, ag.CloseReopenVotes, ag.MaxBountyAmount,
    tq.QuestionId, tq.Title, tq.QuestionDate, tq.QuestionScore, tq.Views, tq.QuestionOwner,
    tq.AnswerId, tq.AnswerScore, tq.AnswerDate, tq.AnswerOwnerId, tq.AnswerOwnerName,
    mcq.CommentCount, mcq.RecentCommentCount,
    tu.Id
ORDER BY tu.UserRank;