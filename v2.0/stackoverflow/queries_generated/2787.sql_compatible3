WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        p.Id AS PostId,
        1 AS Level
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
  UNION ALL
    SELECT
        rth.TagId,
        rth.TagName,
        pl.RelatedPostId AS PostId,
        rth.Level + 1
    FROM RecursiveTagHierarchy rth
    JOIN PostLinks pl ON pl.PostId = rth.PostId
    WHERE rth.Level < 3
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Date > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    GROUP BY b.UserId, b.Class
),
PostScoreRanks AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC) AS ScoreRank,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS PostTypeCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserReputationWindow AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        AVG(u.Reputation) OVER (ORDER BY u.CreationDate ROWS BETWEEN 100 PRECEDING AND CURRENT ROW) AS AvgRecentReputation,
        COUNT(b.Id) AS RecentBadgesCount
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date > (u.CreationDate - INTERVAL '6 months')
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
QuestionAnswerCounts AS (
    SELECT
        q.Id AS QuestionId,
        COALESCE(q.AnswerCount, 0) AS AnswerCount,
        COUNT(a.Id) AS ActualAnswerCount,
        MAX(a.Score) AS MaxAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.AnswerCount
),
ClosedQuestions AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN COALESCE(NULLIF(ph.Comment, ''), 'Unknown') END) AS CloseReasonId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseVotesCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
LatestUserActivity AS (
    SELECT
        u.Id AS UserId,
        MAX(CASE WHEN p.OwnerUserId = u.Id THEN p.LastActivityDate END) AS LastPostActivity,
        MAX(CASE WHEN c.UserId = u.Id THEN c.CreationDate END) AS LastCommentDate,
        MAX(CASE WHEN v.UserId = u.Id THEN v.CreationDate END) AS LastVoteDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    urw.AvgRecentReputation,
    ubc.BadgeCountGold,
    ubc.BadgeCountSilver,
    ubc.BadgeCountBronze,
    qac.QuestionId,
    qac.AnswerCount,
    qac.ActualAnswerCount,
    qac.MaxAnswerScore,
    cs.CloseReasonId,
    cs.CloseVotesCount,
    psr.ScoreRank AS PostScoreRank,
    psr.PostTypeId,
    psr.Score,
    psr.ViewCount,
    (COALESCE(u.Location, 'Unknown Location') || ' - ' || COALESCE(u.WebsiteUrl, 'No Website')) AS UserLocationWebsite,
    CASE
        WHEN u.AboutMe IS NOT NULL AND CHAR_LENGTH(u.AboutMe) > 100 THEN SUBSTRING(u.AboutMe FROM 1 FOR 97) || '...'
        ELSE COALESCE(u.AboutMe, 'No description')
    END AS ShortAboutMe,
    COALESCE(lua.LastPostActivity, lua.LastCommentDate, lua.LastVoteDate, u.LastAccessDate) AS LatestUserEngagement,
    CASE
        WHEN u.Reputation > urw.AvgRecentReputation THEN 'Above Average'
        ELSE 'Below Average'
    END AS ReputationComparedToRecentUsers,
    (SELECT p2.Title FROM Posts p2 WHERE p2.Id = p.AcceptedAnswerId) AS AcceptedAnswerTitle
FROM Users u
LEFT JOIN UserReputationWindow urw ON urw.UserId = u.Id
LEFT JOIN (
    SELECT 
        UserId,
        SUM(CASE WHEN Class = 1 THEN BadgeCount ELSE 0 END) AS BadgeCountGold,
        SUM(CASE WHEN Class = 2 THEN BadgeCount ELSE 0 END) AS BadgeCountSilver,
        SUM(CASE WHEN Class = 3 THEN BadgeCount ELSE 0 END) AS BadgeCountBronze
    FROM UserBadgeCounts
    GROUP BY UserId
) ubc ON ubc.UserId = u.Id
LEFT JOIN (
    SELECT qac_inner.QuestionId, qac_inner.AnswerCount, qac_inner.ActualAnswerCount, qac_inner.MaxAnswerScore
    FROM QuestionAnswerCounts qac_inner
) qac ON qac.QuestionId IN (
    SELECT p_in.Id FROM Posts p_in WHERE p_in.OwnerUserId = u.Id AND p_in.PostTypeId = 1
)
LEFT JOIN ClosedQuestions cs ON cs.PostId = qac.QuestionId
LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN PostScoreRanks psr ON psr.Id = p.Id
LEFT JOIN LatestUserActivity lua ON lua.UserId = u.Id
WHERE u.Reputation > 1000
AND (
    (u.Location IS NOT NULL AND CHAR_LENGTH(TRIM(u.Location)) > 0)
    OR (u.WebsiteUrl IS NOT NULL AND CHAR_LENGTH(TRIM(u.WebsiteUrl)) > 0)
)
AND EXISTS (
    SELECT 1 FROM Posts p2
    WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1 AND p2.Score > 10
)
ORDER BY urw.AvgRecentReputation DESC, psr.ScoreRank ASC
LIMIT 100;