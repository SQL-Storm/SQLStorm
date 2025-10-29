-- {"query": "3362.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2514} 

WITH user_stats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
badge_agg AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
recent_votes AS (
    SELECT
        v.PostId,
        v.VoteTypeId,
        v.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),
post_with_latest_vote AS (
    SELECT
        p.Id,
        p.Title,
        p.PostTypeId,
        p.Score,
        rv.VoteTypeId,
        rv.CreationDate AS LatestVoteDate
    FROM Posts p
    LEFT JOIN recent_votes rv ON rv.PostId = p.Id AND rv.rn = 1
),
top_questions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        p.Title,
        p.Score,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS Rank
    FROM user_stats u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    WHERE p.Score IS NOT NULL
    ORDER BY p.Score DESC
    LIMIT 10
),
top_answers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        p.Title,
        p.Score,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS Rank
    FROM user_stats u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
    WHERE p.Score IS NOT NULL
    ORDER BY p.Score DESC
    LIMIT 10
),
combined_top AS (
    SELECT * FROM top_questions
    UNION ALL
    SELECT * FROM top_answers
),
tag_usage AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        STRING_AGG(DISTINCT u.DisplayName, ', ') FILTER (WHERE u.Id IS NOT NULL) AS Users
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%<'||t.TagName||'>%'
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 100
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.QuestionCount,
    us.AnswerCount,
    ROUND(us.AvgPostScore::numeric,2) AS AvgScore,
    COALESCE(ba.GoldBadges,0) AS GoldBadges,
    COALESCE(ba.SilverBadges,0) AS SilverBadges,
    COALESCE(ba.BronzeBadges,0) AS BronzeBadges,
    COALESCE(ba.TotalBadges,0) AS TotalBadges,
    pwlv.Title AS RecentPostTitle,
    pwlv.Score AS RecentPostScore,
    pwlv.VoteTypeId AS RecentVoteType,
    pwlv.LatestVoteDate,
    ct.Rank AS TopRank,
    tu.TagName,
    tu.PostCount,
    tu.TotalScore,
    tu.Users AS TagContributors
FROM user_stats us
LEFT JOIN badge_agg ba ON ba.UserId = us.Id
LEFT JOIN (
    SELECT p.OwnerUserId, p.Title, p.Score, rv.VoteTypeId, rv.CreationDate
    FROM post_with_latest_vote p
    LEFT JOIN recent_votes rv ON rv.PostId = p.Id AND rv.rn = 1
    WHERE p.CreationDate = (
        SELECT MAX(p2.CreationDate)
        FROM Posts p2
        WHERE p2.OwnerUserId = p.OwnerUserId
    )
    ORDER BY p.CreationDate DESC
    LIMIT 1
) pwlv ON pwlv.OwnerUserId = us.Id
LEFT JOIN combined_top ct ON ct.UserId = us.Id
LEFT JOIN LATERAL (
    SELECT tu.TagName, tu.PostCount, tu.TotalScore, tu.Users
    FROM tag_usage tu
    WHERE tu.Users ILIKE '%'||us.DisplayName||'%'
    ORDER BY tu.PostCount DESC
    LIMIT 1
) tu ON true
WHERE us.Reputation > 10000
ORDER BY us.Reputation DESC
LIMIT 50;
