WITH RECURSIVE RecursiveTagCounts AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count,
        p.Id AS QuestionId,
        p.CreationDate,
        u.Id AS OwnerUserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryChangeDate,
        ph.UserId AS EditorUserId,
        ph.UserDisplayName AS EditorDisplayName
    FROM Tags t
    JOIN Posts p ON p.Id = t.ExcerptPostId AND p.PostTypeId = 1
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)
    WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '365 days'
    UNION ALL
    SELECT
        rtc.TagId,
        rtc.TagName,
        rtc.Count,
        p2.Id,
        p2.CreationDate,
        u2.Id,
        u2.DisplayName,
        u2.Reputation,
        u2.Location,
        ph2.PostHistoryTypeId,
        ph2.CreationDate,
        ph2.UserId,
        ph2.UserDisplayName
    FROM RecursiveTagCounts rtc
    JOIN PostLinks pl ON pl.PostId = rtc.QuestionId AND pl.LinkTypeId = 1
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId AND p2.PostTypeId = 1
    LEFT JOIN Users u2 ON u2.Id = p2.OwnerUserId
    LEFT JOIN PostHistory ph2 ON ph2.PostId = p2.Id AND ph2.PostHistoryTypeId IN (4,5,6)
    WHERE p2.CreationDate > rtc.CreationDate
),
LatestUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        MAX(p.CreationDate) OVER (PARTITION BY u.Id) AS LastPostDate,
        MAX(c.CreationDate) OVER (PARTITION BY u.Id) AS LastCommentDate,
        MAX(ph.CreationDate) OVER (PARTITION BY u.Id) AS LastEditDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
),
RankedPostsByScore AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostRanking
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.Score >= 0
),
AnswerStatsByQuestion AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(a.Id) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore,
        COUNT(DISTINCT a.OwnerUserId) AS DistinctAnswerers
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
),
ClosedQuestionsWithReasons AS (
    SELECT
        p.Id,
        p.Title,
        p.ClosedDate,
        CAST(ph.Comment AS SMALLINT) AS CloseReasonId,
        crt.Name AS CloseReasonName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS SMALLINT)
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.ClosedDate IS NOT NULL
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS DistinctBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserVotesSummary AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesCast,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesCast,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoritesCast,
        COUNT(DISTINCT v.PostId) AS VotedPostsCount
    FROM Votes v
    GROUP BY v.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.Views,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.DistinctBadges,
    us.LastBadgeDate,
    uv.UpVotesCast,
    uv.DownVotesCast,
    uv.FavoritesCast,
    uv.VotedPostsCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year') AS QuestionsLastYear,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2 AND p.Score > 5) AS HighScoreAnswers,
    (SELECT AVG(score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS AvgQuestionScore,
    (SELECT COUNT(DISTINCT p.Tags) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS DistinctTagSetsUsed,
    LAG(u.Reputation) OVER (ORDER BY u.Reputation) AS PrevUserReputation,
    LEAD(u.Reputation) OVER (ORDER BY u.Reputation) AS NextUserReputation,
    rs.TotalAnswers,
    rs.AvgAnswerScore,
    rs.MaxAnswerScore,
    rs.MinAnswerScore,
    rs.DistinctAnswerers,
    cp.Title AS RecentlyClosedQuestionTitle,
    cp.CloseReasonName,
    cp.ClosedDate
FROM Users u
LEFT JOIN UserBadgeSummary us ON us.UserId = u.Id
LEFT JOIN UserVotesSummary uv ON uv.UserId = u.Id
LEFT JOIN (
    SELECT
        q.OwnerUserId,
        q.Id,
        a.TotalAnswers,
        a.AvgAnswerScore,
        a.MaxAnswerScore,
        a.MinAnswerScore,
        a.DistinctAnswerers
    FROM Posts q
    LEFT JOIN AnswerStatsByQuestion a ON q.Id = a.QuestionId
    WHERE q.PostTypeId = 1
) rs ON rs.OwnerUserId = u.Id
LEFT JOIN LATERAL (
    SELECT cp2.Title, cp2.ClosedDate, crt.Name AS CloseReasonName
    FROM Posts cp2
    JOIN PostHistory ph2 ON ph2.PostId = cp2.Id AND ph2.PostHistoryTypeId = 10
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph2.Comment AS SMALLINT)
    WHERE cp2.OwnerUserId = u.Id AND cp2.ClosedDate IS NOT NULL
    ORDER BY cp2.ClosedDate DESC
    LIMIT 1
) cp ON TRUE
WHERE u.Reputation > 100
ORDER BY u.Reputation DESC
LIMIT 100;