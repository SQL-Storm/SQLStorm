-- {"query": "35086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 634} 
WITH TopActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 20
    ORDER BY TotalScore DESC
    LIMIT 50
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserAnswersVotes AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesReceived,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesReceived
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
),
RecentEdits AS (
    SELECT
        ph.UserId,
        COUNT(*) AS EditsLast30Days
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
      AND ph.CreationDate >= NOW() - INTERVAL '30 day'
    GROUP BY ph.UserId
)
SELECT
    t.UserId,
    t.DisplayName,
    t.Reputation,
    t.PostCount,
    t.Questions,
    t.Answers,
    t.TotalScore,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uav.UpvotesReceived, 0) AS AnswerUpvotesReceived,
    COALESCE(uav.DownvotesReceived, 0) AS AnswerDownvotesReceived,
    COALESCE(re.EditsLast30Days, 0) AS EditsInLast30Days
FROM TopActiveUsers t
LEFT JOIN UserBadges ub ON ub.UserId = t.UserId
LEFT JOIN UserAnswersVotes uav ON uav.UserId = t.UserId
LEFT JOIN RecentEdits re ON re.UserId = t.UserId
ORDER BY t.TotalScore DESC, t.Answers DESC, t.Questions DESC
LIMIT 20;