-- {"query": "35019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 631} 
WITH RecentActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        COUNT(c.Id) AS CommentCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    WHERE u.LastAccessDate > NOW() - INTERVAL '180 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 10 AND COUNT(c.Id) > 5
),
UserBadges AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserVotes AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven
    FROM Votes v
    GROUP BY v.UserId
),
TopQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.PostCount,
    rau.CommentCount,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uv.UpVotesGiven, 0) AS UpVotesGiven,
    COALESCE(uv.DownVotesGiven, 0) AS DownVotesGiven,
    tq.Id AS TopQuestionId,
    tq.Title AS TopQuestionTitle,
    tq.Score AS TopQuestionScore,
    tq.ViewCount AS TopQuestionViews,
    rau.LastPostDate,
    rau.LastCommentDate
FROM RecentActiveUsers rau
LEFT JOIN UserBadges ub ON ub.UserId = rau.UserId
LEFT JOIN UserVotes uv ON uv.UserId = rau.UserId
LEFT JOIN TopQuestions tq ON tq.OwnerUserId = rau.UserId AND tq.rn = 1
ORDER BY rau.Reputation DESC, rau.PostCount DESC
LIMIT 50;