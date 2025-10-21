WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount,
        MIN(b.Date) AS FirstBadgeDate,
        MAX(b.Date) AS LastBadgeDate,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName
    HAVING COUNT(b.Id) >= 10
),
PostStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN CAST(p.Score AS DECIMAL(20, 4)) END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN CAST(p.Score AS DECIMAL(20, 4)) END) AS AvgAnswerScore,
        SUM(p.Score) AS TotalScore,
        COUNT(ph.Id) AS EditCount,
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate))) AS AvgTimeToFirstEdit
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY p.OwnerUserId
),
VoteStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvoteCount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownvoteCount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 8) AS BountyStartCount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 9) AS BountyCloseCount,
        SUM(CASE WHEN v.VoteTypeId IN (8,9) THEN v.BountyAmount ELSE 0 END) AS TotalBountyAmount
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.OwnerUserId
),
CommentStats AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(CAST(c.Score AS DECIMAL(20, 4))) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.UserId
)
SELECT 
    us.UserId,
    us.Reputation,
    us.DisplayName,
    us.BadgeCount,
    us.FirstBadgeDate,
    us.LastBadgeDate,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    ps.QuestionCount,
    ps.AnswerCount,
    ROUND(ps.AvgQuestionScore, 2) AS AvgQuestionScore,
    ROUND(ps.AvgAnswerScore, 2) AS AvgAnswerScore,
    ps.TotalScore,
    ps.EditCount,
    ps.AvgTimeToFirstEdit,
    vs.UpvoteCount,
    vs.DownvoteCount,
    vs.BountyStartCount,
    vs.BountyCloseCount,
    vs.TotalBountyAmount,
    cs.CommentCount,
    ROUND(cs.AvgCommentScore, 2) AS AvgCommentScore,
    RANK() OVER (ORDER BY us.Reputation DESC) AS RepRank
FROM UserStats us
LEFT JOIN PostStats ps ON us.UserId = ps.UserId
LEFT JOIN VoteStats vs ON us.UserId = vs.UserId
LEFT JOIN CommentStats cs ON us.UserId = cs.UserId
ORDER BY us.Reputation DESC
LIMIT 10;