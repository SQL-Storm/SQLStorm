-- {"query": "112.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2610} 
WITH RecentQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_by_owner
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NULL
      AND p.LastActivityDate IS NOT NULL
      AND p.CreationDate > DATEADD(day, -60, GETDATE())
),
OwnerStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.LastAccessDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
        (SELECT STRING_AGG(bt.Name, ', ') WITHIN GROUP (ORDER BY bt.Name)
         FROM Badges b2
         JOIN Badges b ON b2.UserId = u.Id
         JOIN (VALUES (1,'Gold'),(2,'Silver'),(3,'Bronze')) AS bt(Class,Name) ON b.Class = bt.Class
        ) AS BadgeSummary
    FROM Users u
),
TopLinks AS (
    SELECT
        pl.PostId,
        COUNT(*) AS LinkCount,
        MAX(pl.CreationDate) AS LastLinkDate
    FROM PostLinks pl
    GROUP BY pl.PostId
),
VoteActivity AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    GROUP BY v.PostId
),
Combined AS (
    SELECT
        rq.Id,
        rq.Title,
        rq.OwnerUserId,
        rq.Score,
        rq.ViewCount,
        rq.CreationDate,
        rq.LastActivityDate,
        rq.Tags,
        os.DisplayName AS OwnerDisplayName,
        os.Reputation,
        ba.BadgeCount,
        ba.Appendix AS BadgeSummary,
        tl.LinkCount,
        va.UpVotes,
        va.DownVotes,
        va.LastVoteDate
    FROM RecentQuestions rq
    LEFT JOIN Users os ON rq.OwnerUserId = os.Id
    LEFT JOIN OwnerStats oa ON rq.OwnerUserId = oa.UserId
    LEFT JOIN TopLinks tl ON rq.Id = tl.PostId
    LEFT JOIN VoteActivity va ON rq.Id = va.PostId
    LEFT JOIN (SELECT UserId, BadgeCount, BadgeSummary, DisplayName FROM OwnerStats) ba ON rq.OwnerUserId = ba.UserId
),
RecentModeratorNoms AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        0 AS Placeholder
    FROM Posts p
    WHERE p.PostTypeId = 6 -- ModeratorNomination
      AND p.CreationDate > DATEADD(day, -14, GETDATE())
),
UnionSet AS (
    SELECT
        Id,
        Title,
        OwnerUserId,
        Score,
        ViewCount,
        CreationDate,
        LastActivityDate,
        'Question' AS PostKind,
        NULL AS Extra
    FROM Combined
    UNION ALL
    SELECT
        Id,
        Title,
        OwnerUserId,
        Score,
        ViewCount,
        CreationDate,
        LastActivityDate,
        'Nomination' AS PostKind,
        NULL AS Extra
    FROM RecentModeratorNoms
)
SELECT
    Id,
    Title,
    PostKind,
    OwnerUserId,
    (SELECT DisplayName FROM Users WHERE Id = OwnerUserId) AS OwnerDisplayName,
    Score,
    ViewCount,
    CreationDate,
    LastActivityDate,
    COALESCE((SELECT TOP 1 TagName FROM Tags t WHERE t.ExcerptPostId = Id OR t.WikiPostId = Id), NULL) AS PrimaryTag,
    COALESCE((SELECT SUM(CommentCount) FROM (SELECT Id AS cId FROM Comments WHERE PostId = Id) AS c), 0) AS CommentCount,
    COALESCE(UpVotes, 0) AS UpVotes,
    COALESCE(DownVotes, 0) AS DownVotes,
    COALESCE(LastVoteDate, CreationDate) AS LastVoteOrCreationDate,
    COALESCE(LinkCount, 0) AS LinkCount,
    BadgeCount,
    BadgeSummary
FROM UnionSet u
LEFT JOIN VoteActivity va ON u.Id = va.PostId
LEFT JOIN TopLinks tl ON u.Id = tl.PostId
LEFT JOIN (SELECT UserId, MAX(LastAccessDate) AS LastAccessDate FROM Users GROUP BY UserId) ua ON ua.UserId = u.OwnerUserId
ORDER BY Score DESC, ViewCount DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;