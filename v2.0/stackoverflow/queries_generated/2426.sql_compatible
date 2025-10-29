WITH RECURSIVE RecursiveUserHierarchy AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate, 1 AS Level
    FROM Users u
    WHERE u.Reputation > 20000
    UNION ALL
    SELECT u2.Id, u2.DisplayName, u2.Reputation, u2.CreationDate, ruh.Level + 1
    FROM Users u2
    JOIN RecursiveUserHierarchy ruh ON ruh.Id = u2.Id - 1
    WHERE u2.Reputation > 20000 AND ruh.Level < 5
),
TopQuestions AS (
    SELECT p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.Tags,
        row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn,
        p.AcceptedAnswerId
    FROM Posts p 
    WHERE p.PostTypeId = 1
      AND p.Score > 10
      AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '2' YEAR)
),
QuestionBadges AS (
    SELECT b.UserId, COUNT(*) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    JOIN TopQuestions tq ON b.UserId = tq.OwnerUserId
    WHERE b.Date >= (CAST('2024-10-01' AS DATE) - INTERVAL '2' YEAR)
    GROUP BY b.UserId
),
CommentsStats AS (
    SELECT c.PostId, COUNT(*) AS CommentCount,
           SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousComments,
           AVG(LENGTH(c.Text)) AS AvgCommentLength
    FROM Comments c
    GROUP BY c.PostId
),
AcceptedAnswersWithVotes AS (
    SELECT a.Id, a.ParentId AS QuestionId, a.Score AS AnswerScore,
        COALESCE(v.UpVotesCount, 0) AS UpVotes, COALESCE(v.DownVotesCount, 0) AS DownVotes,
        u.DisplayName AS AnswerOwnerName
    FROM Posts a
    LEFT JOIN (
        SELECT v.PostId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotesCount,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesCount
        FROM Votes v
        JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
        GROUP BY v.PostId
    ) v ON a.Id = v.PostId
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
),
DuplicateQuestions AS (
    SELECT pl.PostId AS DuplicateId, pl.RelatedPostId AS OriginalQuestionId
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name = 'Duplicate'
),
QuestionsWithHistory AS (
    SELECT ph.PostId, MAX(ph.CreationDate) AS LastEditDate,
        COUNT(DISTINCT ph.PostHistoryTypeId) AS HistoryEventsCount,
        BOOL_OR(ph.PostHistoryTypeId IN (10, 11)) AS WasClosedOrReopened
    FROM PostHistory ph
    GROUP BY ph.PostId
),
UserActivityRank AS (
    SELECT u.Id, u.DisplayName, 
        rank() OVER (ORDER BY COALESCE(qc.QuestionsCount, 0) DESC, COALESCE(ab.BadgeCount, 0) DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS QuestionsCount
        FROM Posts
        WHERE PostTypeId = 1
          AND CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
        GROUP BY OwnerUserId
    ) qc ON u.Id = qc.OwnerUserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount
        FROM Badges
        WHERE Date >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
        GROUP BY UserId
    ) ab ON u.Id = ab.UserId
),
BenchmarkSet AS (
    SELECT tq.Id AS QuestionId, tq.OwnerUserId, tq.Title, tq.Score, tq.Tags, 
        ab.BadgeCount, ab.GoldBadges, ab.SilverBadges, ab.BronzeBadges, 
        cs.CommentCount, cs.AnonymousComments, cs.AvgCommentLength,
        aav.Id AS AcceptedAnswerId, aav.AnswerScore, aav.UpVotes, aav.DownVotes, aav.AnswerOwnerName,
        qwh.LastEditDate, qwh.HistoryEventsCount, qwh.WasClosedOrReopened,
        dup.OriginalQuestionId,
        uar.ActivityRank
    FROM TopQuestions tq
    LEFT JOIN QuestionBadges ab ON tq.OwnerUserId = ab.UserId
    LEFT JOIN CommentsStats cs ON tq.Id = cs.PostId
    LEFT JOIN AcceptedAnswersWithVotes aav ON tq.AcceptedAnswerId = aav.Id
    LEFT JOIN QuestionsWithHistory qwh ON tq.Id = qwh.PostId
    LEFT JOIN DuplicateQuestions dup ON tq.Id = dup.DuplicateId
    LEFT JOIN UserActivityRank uar ON tq.OwnerUserId = uar.Id
    WHERE tq.rn = 1
)
SELECT *
FROM BenchmarkSet bs
WHERE 
    (bs.Score + COALESCE(bs.BadgeCount,0) * 2) * (COALESCE(bs.CommentCount,0) + 1) > 50
    AND (bs.WasClosedOrReopened = FALSE OR bs.WasClosedOrReopened IS NULL)
    AND (
        (bs.Tags IS NOT NULL AND bs.Tags LIKE '%<sql>%') 
        OR bs.ActivityRank <= 100 
        OR COALESCE(bs.GoldBadges, 0) >= 3
    )
ORDER BY bs.ActivityRank ASC NULLS LAST, bs.Score DESC
LIMIT 100;