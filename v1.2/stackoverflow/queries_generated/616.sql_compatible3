WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, 0 AS Depth
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE AND t.IsRequired = FALSE
    UNION ALL
    SELECT t2.Id, t2.TagName, t2.Count, t2.ExcerptPostId, t2.WikiPostId, r.Depth + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id > r.Id AND t2.Count < r.Count
    WHERE r.Depth < 3
),
TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS Rank
    FROM Users u
    WHERE u.Reputation > 1000 AND u.Location IS NOT NULL
),
PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS UserPostCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
AcceptedAnswerScores AS (
    SELECT q.Id AS QuestionId, a.Score AS AcceptedAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE q.PostTypeId = 1
),
UserBadgeCounts AS (
    SELECT b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostCloseReasons AS (
    SELECT ph.PostId, crt.Name AS CloseReasonName, COUNT(*) AS CloseVotes
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
UserRecentActivity AS (
    SELECT u.Id AS UserId,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(v.CreationDate) AS LastVoteDate,
        GREATEST(
            COALESCE(MAX(p.CreationDate), TIMESTAMP '1900-01-01'),
            COALESCE(MAX(c.CreationDate), TIMESTAMP '1900-01-01'),
            COALESCE(MAX(v.CreationDate), TIMESTAMP '1900-01-01')
        ) AS LastActivity
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id
),
UserEngagement AS (
    SELECT u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2,3) THEN v.Id END) AS VotesCast
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id
)
SELECT
    tu.Rank,
    tu.DisplayName,
    tu.Reputation,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ue.QuestionsAsked,
    ue.AnswersGiven,
    ue.CommentsMade,
    ue.VotesCast,
    ur.LastActivity,
    (
        SELECT STRING_AGG(tn, ',') FROM (
            SELECT rth.TagName AS tn
            FROM RecursiveTagHierarchy rth
            WHERE rth.TagName = ANY(string_to_array(regexp_replace(COALESCE(ps.Tags, ''), '[<>]', ' ', 'g'), ' '))
            ORDER BY rth.Count DESC, rth.TagName
            LIMIT 5
        ) sub
    ) AS FavoriteTags,
    ps.PostRank,
    ps.Score,
    ps.ViewCount,
    ps.AnswerCount,
    ps.CommentCount,
    ps.FavoriteCount,
    acr.AcceptedAnswerScore,
    COALESCE(pcr.CloseReasonName, 'Open') AS PostCloseStatus,
    CASE 
        WHEN ps.Score > 100 AND ps.ViewCount > 10000 THEN 'Hot Topic'
        WHEN ps.Score BETWEEN 50 AND 100 THEN 'Popular'
        ELSE 'Normal'
    END AS PostPopularityCategory,
    CONCAT(
        COALESCE(ps.Tags, '[no tags]'),
        ' | Owner: ',
        COALESCE(tu.DisplayName, 'Anonymous'),
        ' | Score/ViewRatio: ',
        CASE WHEN ps.ViewCount > 0 THEN CAST(ROUND(CAST(ps.Score AS NUMERIC)/ps.ViewCount, 4) AS VARCHAR) ELSE 'N/A' END,
        ' | AcceptedAnswerScore: ',
        COALESCE(CAST(acr.AcceptedAnswerScore AS VARCHAR), 'None')
    ) AS PostSummary
FROM TopUsers tu
LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = tu.Id
LEFT JOIN UserEngagement ue ON ue.UserId = tu.Id
LEFT JOIN UserRecentActivity ur ON ur.UserId = tu.Id
LEFT JOIN PostStats ps ON ps.OwnerUserId = tu.Id AND ps.PostRank <= 3
LEFT JOIN AcceptedAnswerScores acr ON acr.QuestionId = ps.Id
LEFT JOIN PostCloseReasons pcr ON pcr.PostId = ps.Id
WHERE ps.Id IS NOT NULL
ORDER BY tu.Rank, ps.PostRank
LIMIT 100;