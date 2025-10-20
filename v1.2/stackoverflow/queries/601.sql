WITH UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges,
        ROW_NUMBER() OVER (ORDER BY COUNT(b.Id) DESC, u.Reputation DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsersPosts AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score END) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
RecentClosedQuestions AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS ClosedDate,
        crt.Name AS CloseReason,
        p.Title,
        p.Tags,
        u.DisplayName AS OwnerName
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId AND pht.Name = 'Post Closed'
    INNER JOIN CloseReasonTypes crt ON CAST(crt.Id AS VARCHAR) = ph.Comment
    INNER JOIN Posts p ON p.Id = ph.PostId
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE ph.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
),
PostLinkCounts AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN lt.Name = 'Duplicate' THEN 1 END) AS DuplicateLinks,
        COUNT(CASE WHEN lt.Name = 'Linked' THEN 1 END) AS LinkedPosts
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY pl.PostId
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        COUNT(c.Id) OVER (PARTITION BY u.Id ORDER BY c.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeComments,
        RANK() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS PostScoreRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE u.Reputation > 1000
),
HighEngagementPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        COALESCE(plc.DuplicateLinks,0) AS DuplicateLinks,
        COALESCE(plc.LinkedPosts,0) AS LinkedPosts,
        CASE 
            WHEN p.FavoriteCount > 10 AND p.ViewCount > 1000 THEN 'High Interest'
            WHEN p.AnswerCount > 5 THEN 'High Activity'
            ELSE 'Normal'
        END AS EngagementCategory
    FROM Posts p
    LEFT JOIN PostLinkCounts plc ON plc.PostId = p.Id
    WHERE p.PostTypeId = 1
),
CorrelatedUserLastVote AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        (
            SELECT MAX(v.CreationDate)
            FROM Votes v
            WHERE v.UserId = u.Id
        ) AS LastVoteDate,
        (
            SELECT COUNT(*)
            FROM Votes v2
            WHERE v2.UserId = u.Id AND v2.VoteTypeId = 2
        ) AS UpVotesGiven,
        (
            SELECT COUNT(*)
            FROM Votes v3
            WHERE v3.UserId = u.Id AND v3.VoteTypeId = 3
        ) AS DownVotesGiven
    FROM Users u
    WHERE u.Reputation > 5000
)
SELECT
    ubc.UserId,
    ubc.DisplayName,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ubc.TotalBadges,
    tup.TotalPosts,
    tup.Questions,
    tup.Answers,
    tup.AvgScore,
    tup.LastPostDate,
    cau.LastVoteDate,
    cau.UpVotesGiven,
    cau.DownVotesGiven,
    ua.CumulativeComments,
    ua.PostScoreRank,
    hep.Id AS HighEngagementPostId,
    hep.Title AS HighEngagementPostTitle,
    hep.Score AS HighEngagementPostScore,
    hep.ViewCount AS HighEngagementPostViews,
    hep.DuplicateLinks,
    hep.LinkedPosts,
    hep.EngagementCategory,
    rcq.ClosedDate AS RecentCloseDate,
    rcq.CloseReason AS RecentCloseReason,
    rcq.Title AS RecentlyClosedQuestionTitle,
    rcq.Tags AS RecentlyClosedQuestionTags
FROM UserBadgeCounts ubc
LEFT JOIN TopUsersPosts tup ON tup.OwnerUserId = ubc.UserId
LEFT JOIN CorrelatedUserLastVote cau ON cau.UserId = ubc.UserId
LEFT JOIN UserActivityWindow ua ON ua.UserId = ubc.UserId
LEFT JOIN HighEngagementPosts hep ON hep.Id = ua.PostId
LEFT JOIN RecentClosedQuestions rcq ON rcq.OwnerName = ubc.DisplayName
WHERE ubc.BadgeRank <= 50
  AND (ua.PostScoreRank <= 10 OR ua.PostScoreRank IS NULL)
ORDER BY ubc.TotalBadges DESC, tup.TotalPosts DESC, hep.Score DESC
LIMIT 100;