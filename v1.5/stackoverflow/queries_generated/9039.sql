-- {"query": "9039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 8096} 

WITH
    UserBadgeStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 END), 0) AS Golds,
            COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 END), 0) AS Silvers,
            COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 END), 0) AS Bronzes,
            COUNT(b.Id) AS TotalBadges
        FROM Users u
        LEFT JOIN Badges b
            ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName
    ),
    AnswerSummary AS (
        SELECT
            a.ParentId       AS QuestionId,
            COUNT(*)         AS AnswerCount,
            AVG(a.Score)     AS AvgAnswerScore,
            MAX(a.Score)     OVER (PARTITION BY a.ParentId) AS TopAnswerScore
        FROM Posts a
        WHERE a.PostTypeId = 2
        GROUP BY a.ParentId
    ),
    TagExplode AS (
        SELECT
            p.Id            AS QuestionId,
            value           AS Tag
        FROM Posts p
        CROSS APPLY STRING_SPLIT(
            SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2),
            '><'
        )
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    ),
    TagUsage AS (
        SELECT
            Tag,
            COUNT(*)            AS UsageCount,
            DENSE_RANK()        OVER (ORDER BY COUNT(*) DESC) AS UsageRank
        FROM TagExplode
        GROUP BY Tag
    ),
    CommentRank AS (
        SELECT
            c.PostId           AS QuestionId,
            c.Id               AS CommentId,
            c.CreationDate,
            ROW_NUMBER()       OVER (
                                   PARTITION BY c.PostId
                                   ORDER BY c.CreationDate DESC
                               ) AS rn
        FROM Comments c
    ),
    PostHistoryLag AS (
        SELECT
            ph.PostId,
            ph.CreationDate,
            LAG(ph.CreationDate)
                OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PrevDate,
            DATEDIFF(
                minute,
                LAG(ph.CreationDate)
                    OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate),
                ph.CreationDate
            ) AS MinutesBetween
        FROM PostHistory ph
    ),
    LinkSummary AS (
        SELECT
            p.Id                    AS QuestionId,
            SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS OutgoingLinks,
            SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinks
        FROM Posts p
        LEFT JOIN PostLinks pl
            ON pl.PostId = p.Id
        WHERE p.PostTypeId = 1
        GROUP BY p.Id
    )

SELECT
    q.Id                                       AS QuestionId,
    q.Title,
    u.DisplayName                              AS Owner,
    u.Reputation,
    bs.TotalBadges,
    bs.Golds,
    bs.Silvers,
    bs.Bronzes,
    COALESCE(asum.AnswerCount, 0)              AS AnswerCount,
    COALESCE(CONVERT(int, asum.AvgAnswerScore), 0) AS AvgAnswerScore,
    ls.OutgoingLinks,
    ls.DuplicateLinks,
    tu.Tag                                     AS TopTag,
    DATEDIFF(day, q.CreationDate, GETUTCDATE()) AS DaysOld,
    CASE WHEN q.ClosedDate IS NULL THEN 'Open' ELSE 'Closed' END AS Status,
    rc.CreationDate                            AS LatestCommentDate,
    phl.MinutesBetween,
    (
        SELECT COUNT(*)
        FROM Votes v2
        WHERE v2.PostId = q.Id
          AND v2.VoteTypeId = 2
    )                                           AS CorrelatedUpVotes,
    REPLACE(q.Title, '?', '!')                 AS TitleExclaim
FROM Posts q
INNER JOIN Users u
    ON u.Id = q.OwnerUserId
LEFT JOIN UserBadgeStats bs
    ON bs.Id = u.Id
LEFT JOIN AnswerSummary asum
    ON asum.QuestionId = q.Id
LEFT JOIN LinkSummary ls
    ON ls.QuestionId = q.Id
LEFT JOIN TagUsage tu
    ON tu.UsageRank = 1
LEFT JOIN CommentRank rc
    ON rc.QuestionId = q.Id
   AND rc.rn = 1
LEFT JOIN (
    SELECT *
    FROM PostHistoryLag
    WHERE MinutesBetween IS NOT NULL
      AND MinutesBetween > 0
) phl
    ON phl.PostId = q.Id
WHERE q.PostTypeId = 1
  AND q.Score > 0
  AND EXISTS (
        SELECT 1
        FROM Comments c2
        WHERE c2.PostId = q.Id
          AND c2.Score >= 2
    )

UNION

SELECT
    q.Id,
    q.Title,
    u.DisplayName,
    u.Reputation,
    bs.TotalBadges,
    bs.Golds,
    bs.Silvers,
    bs.Bronzes,
    0,
    0,
    0,
    0,
    tu.Tag,
    0,
    'New',
    NULL,
    0,
    0,
    REPLACE(q.Title, '?', '!')
FROM Posts q
LEFT JOIN Users u
    ON u.Id = q.OwnerUserId
LEFT JOIN UserBadgeStats bs
    ON bs.Id = u.Id
LEFT JOIN TagUsage tu
    ON tu.UsageRank = 1
WHERE q.PostTypeId = 1
  AND q.CreationDate > DATEADD(day, -7, GETUTCDATE())

INTERSECT

SELECT
    q.Id,
    q.Title,
    u.DisplayName,
    u.Reputation,
    bs.TotalBadges,
    bs.Golds,
    bs.Silvers,
    bs.Bronzes,
    COALESCE(asum.AnswerCount, 0),
    COALESCE(CONVERT(int, asum.AvgAnswerScore), 0),
    ls.OutgoingLinks,
    ls.DuplicateLinks,
    tu.Tag,
    DATEDIFF(day, q.CreationDate, GETUTCDATE()),
    CASE WHEN q.ClosedDate IS NULL THEN 'Open' ELSE 'Closed' END,
    rc.CreationDate,
    phl.MinutesBetween,
    (
        SELECT COUNT(*)
        FROM Votes v2
        WHERE v2.PostId = q.Id
          AND v2.VoteTypeId = 2
    ),
    REPLACE(q.Title, '?', '!')
FROM Posts q
LEFT JOIN Users u
    ON u.Id = q.OwnerUserId
LEFT JOIN UserBadgeStats bs
    ON bs.Id = u.Id
LEFT JOIN AnswerSummary asum
    ON asum.QuestionId = q.Id
LEFT JOIN LinkSummary ls
    ON ls.QuestionId = q.Id
LEFT JOIN TagUsage tu
    ON tu.UsageRank = 1
LEFT JOIN CommentRank rc
    ON rc.QuestionId = q.Id
   AND rc.rn = 1
LEFT JOIN PostHistoryLag phl
    ON phl.PostId = q.Id
WHERE q.PostTypeId = 1

EXCEPT

SELECT
    q.Id,
    q.Title,
    u.DisplayName,
    u.Reputation,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    NULL,
    0,
    'Open',
    NULL,
    0,
    0,
    REPLACE(q.Title, '?', '!')
FROM Posts q
LEFT JOIN Users u
    ON u.Id = q.OwnerUserId
WHERE q.PostTypeId = 1
  AND q.Score < -5

ORDER BY Reputation DESC, DaysOld ASC;
