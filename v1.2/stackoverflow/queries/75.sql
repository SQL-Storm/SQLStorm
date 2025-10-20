WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 AS Level,
        ARRAY[t.Id] AS Path
    FROM Tags t
    WHERE t.IsRequired = TRUE

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.IsRequired = TRUE AND NOT t2.Id = ANY(r.Path)
    WHERE r.Level < 3
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
UserReputationStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COALESCE(ubc_gold.BadgeCount, 0) AS GoldBadges,
        COALESCE(ubc_silver.BadgeCount, 0) AS SilverBadges,
        COALESCE(ubc_bronze.BadgeCount, 0) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc_gold ON ubc_gold.UserId = u.Id AND ubc_gold.Class = 1
    LEFT JOIN UserBadgeCounts ubc_silver ON ubc_silver.UserId = u.Id AND ubc_silver.Class = 2
    LEFT JOIN UserBadgeCounts ubc_bronze ON ubc_bronze.UserId = u.Id AND ubc_bronze.Class = 3
),
TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.DisplayName AS OwnerName,
        DENSE_RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
      AND p.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '1 year')
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN a.OwnerUserId IS NULL THEN 0 ELSE 1 END) AS AnsweredByRegisteredUsers
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
QuestionCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        COUNT(*) AS CloseVotesCount
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        -- use RANGE with numeric number of days represented as seconds for compatibility:
        COUNT(*) FILTER (WHERE p.CreationDate BETWEEN p.CreationDate - INTERVAL '30 days' AND p.CreationDate) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS PostsLast30Days,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) FILTER (WHERE p.CreationDate BETWEEN p.CreationDate - INTERVAL '30 days' AND p.CreationDate) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS QuestionsLast30Days,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) FILTER (WHERE p.CreationDate BETWEEN p.CreationDate - INTERVAL '30 days' AND p.CreationDate) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS AnswersLast30Days
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '1 year')
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        p1.Title AS PostTitle,
        p2.Title AS RelatedPostTitle,
        pl.CreationDate
    FROM PostLinks pl
    JOIN Posts p1 ON p1.Id = pl.PostId
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE pl.LinkTypeId = 3
),
ComplexUserSummary AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(bc.Gold, 0) AS GoldBadges,
        COALESCE(bc.Silver, 0) AS SilverBadges,
        COALESCE(bc.Bronze, 0) AS BronzeBadges,
        COALESCE(pq.QuestionCount, 0) AS QuestionsPosted,
        COALESCE(pa.AnswerCount, 0) AS AnswersPosted,
        COALESCE(cmt.CommentCount, 0) AS CommentsMade,
        COALESCE(vt.UpVotes, 0) AS UpVotesGiven,
        COALESCE(vt.DownVotes, 0) AS DownVotesGiven,
        CASE WHEN u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days') THEN 1 ELSE 0 END AS ActiveLast30Days
    FROM Users u
    LEFT JOIN (
        SELECT UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS Gold,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS Silver,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS Bronze
        FROM Badges
        GROUP BY UserId
    ) bc ON bc.UserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS QuestionCount
        FROM Posts
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
    ) pq ON pq.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY OwnerUserId
    ) pa ON pa.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY UserId
    ) cmt ON cmt.UserId = u.Id
    LEFT JOIN (
        SELECT UserId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY UserId
    ) vt ON vt.UserId = u.Id
)
SELECT
    tq.Id AS QuestionId,
    tq.Title,
    tq.OwnerUserId,
    tq.OwnerName,
    tq.Score,
    tq.ViewCount,
    tq.AnswerCount,
    tq.FavoriteCount,
    tq.ClosedDate,
    COALESCE(ac.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(ac.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(ac.MaxAnswerScore, 0) AS MaxAnswerScore,
    COALESCE(ac.AnsweredByRegisteredUsers, 0) AS AnswersByRegisteredUsers,
    qcr.CloseReasonName,
    qcr.CloseVotesCount,
    us.ReputationRank,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    ua.PostsLast30Days,
    ua.QuestionsLast30Days,
    ua.AnswersLast30Days,
    dl.RelatedPostId AS DuplicateOfPostId,
    dl.RelatedPostTitle AS DuplicateOfPostTitle,
    CASE
        WHEN tq.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN tq.FavoriteCount > 10 THEN 'Popular'
        WHEN tq.Score > 50 THEN 'Highly Scored'
        ELSE 'Normal'
    END AS QuestionStatus,
    concat_ws(' | ',
        COALESCE(tq.Tags, 'NoTags'),
        'Owner: ' || COALESCE(tq.OwnerName, 'Anonymous'),
        'Score: ' || CAST(tq.Score AS text),
        'Views: ' || CAST(tq.ViewCount AS text),
        'Answers: ' || CAST(tq.AnswerCount AS text),
        'Favorites: ' || CAST(tq.FavoriteCount AS text),
        'ClosedReason: ' || COALESCE(qcr.CloseReasonName, 'None')
    ) AS QuestionSummary
FROM TopQuestions tq
LEFT JOIN AnswerStats ac ON ac.QuestionId = tq.Id
LEFT JOIN QuestionCloseReasons qcr ON qcr.PostId = tq.Id
LEFT JOIN UserReputationStats us ON us.UserId = tq.OwnerUserId
LEFT JOIN UserActivityWindow ua ON ua.UserId = tq.OwnerUserId AND ua.PostId = tq.Id
LEFT JOIN DuplicateLinks dl ON dl.PostId = tq.Id
GROUP BY
    tq.Id,
    tq.Title,
    tq.OwnerUserId,
    tq.OwnerName,
    tq.Score,
    tq.ViewCount,
    tq.AnswerCount,
    tq.FavoriteCount,
    tq.ClosedDate,
    ac.TotalAnswers,
    ac.AvgAnswerScore,
    ac.MaxAnswerScore,
    ac.AnsweredByRegisteredUsers,
    qcr.CloseReasonName,
    qcr.CloseVotesCount,
    us.ReputationRank,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    ua.PostsLast30Days,
    ua.QuestionsLast30Days,
    ua.AnswersLast30Days,
    dl.RelatedPostId,
    dl.RelatedPostTitle,
    tq.ScoreRank,
    tq.Tags,
    ua.PostId
ORDER BY tq.ScoreRank, tq.ViewCount DESC
LIMIT 100;