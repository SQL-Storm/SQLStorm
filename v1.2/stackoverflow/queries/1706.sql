WITH RankedPosts AS (
    SELECT p.Id, p.PostTypeId, p.CreationDate, p.Score, p.OwnerUserId,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS UserPostRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
), QAStats AS (
    SELECT r.OwnerUserId,
           COUNT(CASE WHEN r.PostTypeId = 1 THEN 1 END) AS QuestionCount,
           COUNT(CASE WHEN r.PostTypeId = 2 THEN 1 END) AS AnswerCount,
           AVG(r.Score) AS AverageScore
    FROM RankedPosts r
    GROUP BY r.OwnerUserId
), BadgeCounts AS (
    SELECT b.UserId,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
           COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
), LatestCommentPerPost AS (
    SELECT c.PostId,
           c.Id AS CommentId,
           c.CreationDate
    FROM Comments c
    WHERE c.Id = (
        SELECT c2.Id
        FROM Comments c2
        WHERE c2.PostId = c.PostId
        ORDER BY c2.CreationDate DESC, c2.Id DESC
        LIMIT 1
    )
)
SELECT u.Id AS UserId,
       u.DisplayName,
       COALESCE(q.QuestionCount, 0) AS QuestionCount,
       COALESCE(q.AnswerCount, 0) AS AnswerCount,
       COALESCE(q.AverageScore, 0) AS AverageScore,
       COALESCE(b.GoldBadges, 0) AS GoldBadges,
       COALESCE(b.SilverBadges, 0) AS SilverBadges,
       COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
       COALESCE(b.TotalBadges, 0) AS TotalBadges,
       lp.PostId AS LatestCommentPostId,
       lp.CommentId AS LatestCommentId,
       lp.CreationDate AS LatestCommentDate
FROM Users u
LEFT JOIN QAStats q ON q.OwnerUserId = u.Id
LEFT JOIN BadgeCounts b ON b.UserId = u.Id
LEFT JOIN LatestCommentPerPost lp ON lp.PostId = (
    SELECT p_inner.Id
    FROM Posts p_inner
    WHERE p_inner.OwnerUserId = u.Id
    ORDER BY p_inner.CreationDate DESC, p_inner.Id DESC
    LIMIT 1
)
GROUP BY
    u.Id,
    u.DisplayName,
    q.QuestionCount,
    q.AnswerCount,
    q.AverageScore,
    b.GoldBadges,
    b.SilverBadges,
    b.BronzeBadges,
    b.TotalBadges,
    lp.PostId,
    lp.CommentId,
    lp.CreationDate;