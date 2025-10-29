-- {"query": "2636.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2009} 

WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByType,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPostsByType
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
      AND p.CreationDate > current_date - INTERVAL '2 years'
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
QuestionAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreation,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        COALESCE(a.AnswerCount, 0) AS AnswerCount,
        COALESCE(a.MaxAnswerScore, 0) AS MaxAnswerScore,
        u.DisplayName AS OwnerName,
        COALESCE(ub.GoldBadges, 0) AS OwnerGoldBadges,
        COALESCE(ub.SilverBadges, 0) AS OwnerSilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS OwnerBronzeBadges,
        COALESCE(ub.TotalBadges, 0) AS OwnerTotalBadges,
        pht.Name AS LastClosedReason,
        clt.Name AS LinkTypeName,
        pl.RelatedPostId,
        row_number() OVER (PARTITION BY q.Id ORDER BY COALESCE(v.ScoreSum,0) DESC) AS VoteRank
    FROM Posts q
    LEFT JOIN (
        SELECT 
            ParentId,
            COUNT(*) AS AnswerCount,
            MAX(Score) AS MaxAnswerScore
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) a ON a.ParentId = q.Id
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = q.OwnerUserId
    LEFT JOIN PostHistory ph ON ph.PostId = q.Id AND ph.PostHistoryTypeId = 10 -- Post Closed
    LEFT JOIN CloseReasonTypes pht ON pht.Id = CAST(ph.Comment AS int) AND ph.PostHistoryTypeId = 10
    LEFT JOIN PostLinks pl ON pl.PostId = q.Id
    LEFT JOIN LinkTypes clt ON clt.Id = pl.LinkTypeId
    LEFT JOIN (
        SELECT 
            v.PostId,
            SUM(
                CASE 
                    WHEN vt.Name = 'UpMod' THEN 1
                    WHEN vt.Name = 'DownMod' THEN -1
                    ELSE 0
                END
            ) AS ScoreSum
        FROM Votes v
        INNER JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    ) v ON v.PostId = q.Id
    WHERE q.PostTypeId = 1
      AND q.CreationDate > current_date - INTERVAL '3 years'
),
TopQuestionsWithAnswers AS (
    SELECT * FROM QuestionAnswerStats
    WHERE AnswerCount > 0
      AND QuestionScore > 5
      AND OwnerTotalBadges > 0
),
UserRecentActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        MAX(ph.CreationDate) AS LastPostEditDate,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT ph.Id) AS TotalEdits,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(COALESCE(vt_up.VoteCount,0)) AS TotalUpVotes,
        SUM(COALESCE(vt_down.VoteCount,0)) AS TotalDownVotes
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VoteCount FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId
    ) vt_up ON vt_up.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VoteCount FROM Votes WHERE VoteTypeId = 3 GROUP BY PostId
    ) vt_down ON vt_down.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
),
FilteredActiveUsers AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.LastPostEditDate,
        ua.LastCommentDate,
        ua.TotalPosts,
        ua.TotalEdits,
        ua.TotalComments,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        u.Reputation,
        CASE 
            WHEN u.Location IS NOT NULL THEN LEFT(u.Location, 20)
            ELSE 'Unknown'
        END AS LocationAbbrev,
        COALESCE(ub.GoldBadges,0) AS GoldBadges,
        COALESCE(ub.SilverBadges,0) AS SilverBadges,
        COALESCE(ub.BronzeBadges,0) AS BronzeBadges
    FROM UserRecentActivity ua
    INNER JOIN Users u ON u.Id = ua.UserId
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = ua.UserId
    WHERE ua.TotalPosts > 10
      AND ua.TotalEdits > 5
      AND ua.LastPostEditDate > current_date - INTERVAL '6 months'
)
SELECT 
    tq.QuestionId,
    tq.Title AS QuestionTitle,
    CONCAT('Tags: ', COALESCE(tq.Tags, '<none>')) AS TagsSummary,
    tq.QuestionCreation,
    tq.QuestionScore,
    tq.QuestionViews,
    tq.AnswerCount,
    tq.MaxAnswerScore,
    tq.OwnerName,
    tq.OwnerGoldBadges,
    tq.OwnerSilverBadges,
    tq.OwnerBronzeBadges,
    tq.OwnerTotalBadges,
    COALESCE(tq.LastClosedReason, 'Open') AS CloseReason,
    COALESCE(tq.LinkTypeName, 'None') AS LinkType,
    tq.RelatedPostId,
    fa.DisplayName AS ActiveUserName,
    fa.LocationAbbrev AS ActiveUserLocation,
    fa.Reputation AS ActiveUserReputation,
    fa.GoldBadges AS ActiveUserGoldBadges,
    fa.SilverBadges AS ActiveUserSilverBadges,
    fa.BronzeBadges AS ActiveUserBronzeBadges,
    fa.TotalPosts AS ActiveUserPosts,
    fa.TotalEdits AS ActiveUserEdits,
    fa.TotalComments AS ActiveUserComments,
    fa.TotalUpVotes - fa.TotalDownVotes AS ActiveUserNetVotes,
    ROW_NUMBER() OVER (PARTITION BY tq.QuestionId ORDER BY fa.Reputation DESC, fa.TotalPosts DESC) AS ActiveUserRank
FROM TopQuestionsWithAnswers tq
LEFT JOIN FilteredActiveUsers fa
  ON fa.UserId = (
    SELECT OwnerUserId 
    FROM Posts 
    WHERE Id = tq.QuestionId
    )
WHERE tq.OwnerTotalBadges > 5
  AND (tq.QuestionScore * 1.5 + tq.QuestionViews / 1000.0) > 20
UNION
SELECT
    p.Id AS QuestionId,
    p.Title AS QuestionTitle,
    CONCAT('Tags: ', COALESCE(p.Tags, '<none>')) AS TagsSummary,
    p.CreationDate AS QuestionCreation,
    p.Score AS QuestionScore,
    p.ViewCount AS QuestionViews,
    0 AS AnswerCount,
    0 AS MaxAnswerScore,
    u.DisplayName AS OwnerName,
    COALESCE(ub.GoldBadges, 0),
    COALESCE(ub.SilverBadges, 0),
    COALESCE(ub.BronzeBadges, 0),
    COALESCE(ub.TotalBadges, 0),
    'No Close Reason' AS CloseReason,
    'N/A' AS LinkType,
    NULL AS RelatedPostId,
    NULL AS ActiveUserName,
    NULL AS ActiveUserLocation,
    u.Reputation,
    COALESCE(ub.GoldBadges,0),
    COALESCE(ub.SilverBadges,0),
    COALESCE(ub.BronzeBadges,0),
    0 AS ActiveUserPosts,
    0 AS ActiveUserEdits,
    0 AS ActiveUserComments,
    0 AS ActiveUserNetVotes,
    0 AS ActiveUserRank
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
LEFT JOIN UserBadgeCounts ub ON ub.UserId = u.Id
WHERE p.PostTypeId = 1
  AND p.AnswerCount IS NULL
  AND p.CreationDate > current_date - INTERVAL '1 year'
ORDER BY QuestionScore DESC, QuestionViews DESC, ActiveUserReputation DESC
LIMIT 100;
