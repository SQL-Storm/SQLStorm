WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        p1.Id AS ExcerptPostId,
        p2.Id AS WikiPostId,
        1 AS Level
    FROM Tags t
    LEFT JOIN Posts p1 ON p1.Id = t.ExcerptPostId AND p1.PostTypeId = 5
    LEFT JOIN Posts p2 ON p2.Id = t.WikiPostId AND p2.PostTypeId = 5
    WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
      AND COALESCE(t.IsRequired, FALSE) = FALSE
    UNION ALL
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        p1.Id,
        p2.Id,
        r.Level + 1
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id = r.Id
    LEFT JOIN Posts p1 ON p1.Id = t.ExcerptPostId AND p1.PostTypeId = 5
    LEFT JOIN Posts p2 ON p2.Id = t.WikiPostId AND p2.PostTypeId = 5
),
UserScoreRankings AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(SUM(vote_up.VotesCount), 0) AS UpVotesReceived,
        COALESCE(SUM(vote_down.VotesCount), 0) AS DownVotesReceived,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COALESCE(SUM(vote_up.VotesCount), 0) DESC) AS RankByReputation
    FROM Users u
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            COUNT(*) AS VotesCount
        FROM Posts p
        JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
        GROUP BY p.OwnerUserId
    ) vote_up ON vote_up.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            COUNT(*) AS VotesCount
        FROM Posts p
        JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 3
        GROUP BY p.OwnerUserId
    ) vote_down ON vote_down.OwnerUserId = u.Id
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostCommentStats AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        COUNT(c.Id) AS CommentCount,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags
),
QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViewCount,
        q.AnswerCount,
        a.Id AS AnswerId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerOwnerUserId,
        u.DisplayName AS AnswerOwnerName,
        CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAccepted,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    WHERE q.PostTypeId = 1
),
PostLinkAggregation AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN 1 END) AS LinkedCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS DuplicateCount,
        STRING_AGG(lt.Name, ', ') AS LinkTypesInvolved
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY pl.PostId
),
BadgeAggregation AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        BOOL_OR(b.TagBased) AS HasTagBasedBadge
    FROM Badges b
    GROUP BY b.UserId
),
UserActivityWindow AS (
    SELECT
        ph.UserId,
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.Text,
        LEAD(ph.PostHistoryTypeId) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextHistoryType,
        LAG(ph.PostHistoryTypeId) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PrevHistoryType,
        ROW_NUMBER() OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate DESC) AS RecentActivityRank
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
),
CloseReasonCount AS (
    SELECT
        p.Id AS QuestionId,
        crt.Name AS CloseReasonName,
        COUNT(*) AS CloseVotes
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS SMALLINT)
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, crt.Name
),
DetailedUserSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(b.TotalBadges, 0) AS BadgeCount,
        COALESCE(b.GoldBadges, 0) AS GoldBadgeCount,
        COALESCE(b.SilverBadges, 0) AS SilverBadgeCount,
        COALESCE(b.BronzeBadges, 0) AS BronzeBadgeCount,
        ua.RecentActivityRank,
        ua.PostHistoryTypeId,
        COUNT(ph.Id) AS TotalEdits,
        COALESCE(us.UpVotesReceived, 0) AS UpVotesReceived,
        COALESCE(us.DownVotesReceived, 0) AS DownVotesReceived
    FROM Users u
    LEFT JOIN BadgeAggregation b ON b.UserId = u.Id
    LEFT JOIN UserActivityWindow ua ON ua.UserId = u.Id AND ua.RecentActivityRank <= 5
    LEFT JOIN UserScoreRankings us ON us.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, b.TotalBadges, b.GoldBadges, b.SilverBadges, b.BronzeBadges, ua.RecentActivityRank, ua.PostHistoryTypeId, us.UpVotesReceived, us.DownVotesReceived
)
SELECT DISTINCT
    qas.QuestionId,
    qas.Title,
    qas.QuestionCreationDate,
    qas.QuestionScore,
    qas.QuestionViewCount,
    qas.AnswerCount,
    qas.AnswerId,
    qas.AnswerCreationDate,
    qas.AnswerScore,
    qas.AnswerOwnerUserId,
    qas.AnswerOwnerName,
    qas.IsAccepted,
    pla.LinkedCount,
    pla.DuplicateCount,
    pla.LinkTypesInvolved,
    pcs.CommentCount,
    pcs.LastCommentDate,
    crc.CloseReasonName,
    crc.CloseVotes,
    dus.DisplayName AS TopContributor,
    dus.Reputation AS TopReputation,
    dus.BadgeCount AS TopBadgeCount,
    dus.GoldBadgeCount AS TopGoldBadges,
    dus.SilverBadgeCount AS TopSilverBadges,
    dus.BronzeBadgeCount AS TopBronzeBadges,
    dus.TotalEdits AS TopEdits,
    dus.UpVotesReceived AS TopUpVotesReceived,
    dus.DownVotesReceived AS TopDownVotesReceived,
    (
      CASE 
        WHEN qas.AnswerScore > qas.QuestionScore THEN 'Answer_Surpasses_Question'
        WHEN qas.AnswerScore IS NULL THEN 'No_Answers_Yet'
        ELSE 'Question_Leads'
      END
    ) || '|' || COALESCE(qas.AnswerOwnerName, 'Anonymous') || '|' || COALESCE(REPLACE(qas.Title, ' ', '_'), 'No_Title') AS PerformanceTag
FROM QuestionAnswerStats qas
LEFT JOIN PostLinkAggregation pla ON pla.PostId = qas.QuestionId
LEFT JOIN PostCommentStats pcs ON pcs.PostId = qas.QuestionId
LEFT JOIN CloseReasonCount crc ON crc.QuestionId = qas.QuestionId
LEFT JOIN LATERAL (
    SELECT dus2.UserId, dus2.DisplayName, dus2.Reputation, dus2.BadgeCount, dus2.GoldBadgeCount, dus2.SilverBadgeCount, dus2.BronzeBadgeCount, dus2.RecentActivityRank, dus2.PostHistoryTypeId, dus2.TotalEdits, dus2.UpVotesReceived, dus2.DownVotesReceived
    FROM DetailedUserSummary dus2
    WHERE dus2.UserId = qas.AnswerOwnerUserId
    ORDER BY dus2.Reputation DESC NULLS LAST
    LIMIT 1
) dus ON TRUE
WHERE qas.QuestionCreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
  AND (COALESCE(qas.AnswerScore, 0) > 5 OR COALESCE(qas.QuestionScore, 0) > 10)
  AND (pcs.CommentCount IS NOT NULL AND pcs.CommentCount > 2)
ORDER BY qas.QuestionCreationDate DESC, qas.QuestionScore DESC, qas.AnswerScore DESC
LIMIT 100;