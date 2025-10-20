WITH UserActivity AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AvgScore,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVoteReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVoteReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 8 THEN v.Id END) AS BountyStarts,
        SUM(v.BountyAmount) AS TotalBountyAmount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY u.Id, u.Reputation, u.DisplayName
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS TagBasedBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostHistorySummary AS (
    SELECT 
        ph.UserId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 END) AS DeleteCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 13 THEN 1 END) AS UndeleteCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 END) AS ReopenCount
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
)
SELECT 
    ua.Id,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalScore,
    ua.TotalViews,
    ROUND(ua.AvgScore, 2) AS AvgScore,
    ua.CommentCount,
    ua.UpVoteReceived,
    ua.DownVoteReceived,
    ua.BountyStarts,
    COALESCE(ua.TotalBountyAmount, 0) AS TotalBountyAmount,
    COALESCE(bs.TotalBadges, 0) AS TotalBadges,
    COALESCE(bs.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(bs.TagBasedBadges, 0) AS TagBasedBadges,
    COALESCE(phs.EditCount, 0) AS EditCount,
    COALESCE(phs.DeleteCount, 0) AS DeleteCount,
    COALESCE(phs.UndeleteCount, 0) AS UndeleteCount,
    COALESCE(phs.CloseCount, 0) AS CloseCount,
    COALESCE(phs.ReopenCount, 0) AS ReopenCount,
    (ua.Reputation + COALESCE(ua.TotalScore,0) + COALESCE(ua.UpVoteReceived,0) - COALESCE(ua.DownVoteReceived,0) + COALESCE(bs.TotalBadges, 0) * 50 + COALESCE(ua.TotalBountyAmount, 0)) AS CompositeActivityScore
FROM UserActivity ua
LEFT JOIN BadgeSummary bs ON ua.Id = bs.UserId
LEFT JOIN PostHistorySummary phs ON ua.Id = phs.UserId
WHERE ua.QuestionCount >= 5 OR ua.AnswerCount >= 10
ORDER BY CompositeActivityScore DESC
LIMIT 500;