-- {"query": "3411.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2499} 

WITH
    UserReps AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
        FROM Users u
        WHERE u.Reputation IS NOT NULL
    ),
    PostStats AS (
        SELECT
            p.OwnerUserId AS UserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1)          AS QuestionCount,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2)          AS AnswerCount,
            AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)      AS AvgQuestionScore,
            AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)      AS AvgAnswerScore,
            MAX(p.CreationDate)                              AS LastPostDate
        FROM Posts p
        GROUP BY p.OwnerUserId
    ),
    BadgeStats AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
            MAX(b.Date)                                   AS LastBadgeDate
        FROM Badges b
        GROUP BY b.UserId
    ),
    TagUsage AS (
        SELECT
            p.OwnerUserId AS UserId,
            COUNT(DISTINCT UNNEST(string_to_array(trim(both '><' FROM p.Tags), '><'))) AS DistinctTagCount
        FROM Posts p
        WHERE p.Tags IS NOT NULL AND p.Tags <> ''
        GROUP BY p.OwnerUserId
    ),
    VoteBalance AS (
        SELECT
            v.PostId,
            SUM(CASE
                    WHEN v.VoteTypeId = 2 THEN 1   -- UpMod
                    WHEN v.VoteTypeId = 3 THEN -1  -- DownMod
                    ELSE 0
                END) AS NetScore
        FROM Votes v
        GROUP BY v.PostId
    ),
    UserVoteStats AS (
        SELECT
            p.OwnerUserId AS UserId,
            COALESCE(SUM(vb.NetScore), 0)                          AS TotalNetScore,
            COUNT(*) FILTER (WHERE vb.NetScore > 0)               AS PostsWithPositiveNet,
            COUNT(*) FILTER (WHERE vb.NetScore < 0)               AS PostsWithNegativeNet
        FROM Posts p
        LEFT JOIN VoteBalance vb ON vb.PostId = p.Id
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    RecentActivity AS (
        SELECT
            u.Id AS UserId,
            GREATEST(
                COALESCE(u.LastAccessDate,          TIMESTAMP '1970-01-01'),
                COALESCE(ps.LastPostDate,          TIMESTAMP '1970-01-01'),
                COALESCE(bs.LastBadgeDate,        TIMESTAMP '1970-01-01')
            ) AS LastActivity
        FROM Users u
        LEFT JOIN PostStats ps ON ps.UserId = u.Id
        LEFT JOIN BadgeStats bs ON bs.UserId = u.Id
    )
SELECT
    ur.Id,
    ur.DisplayName,
    ur.Reputation,
    COALESCE(ps.QuestionCount, 0)                       AS QuestionCount,
    COALESCE(ps.AnswerCount, 0)                         AS AnswerCount,
    ROUND(COALESCE(ps.AvgQuestionScore, 0)::numeric, 2) AS AvgQuestionScore,
    ROUND(COALESCE(ps.AvgAnswerScore, 0)::numeric, 2)   AS AvgAnswerScore,
    COALESCE(bs.GoldBadges, 0)                          AS GoldBadges,
    COALESCE(bs.SilverBadges, 0)                        AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0)                        AS BronzeBadges,
    COALESCE(tu.DistinctTagCount, 0)                    AS DistinctTagCount,
    uv.TotalNetScore,
    uv.PostsWithPositiveNet,
    uv.PostsWithNegativeNet,
    ra.LastActivity,
    CASE
        WHEN uv.TotalNetScore = 0 THEN NULL
        ELSE ROUND(uv.TotalNetScore::numeric /
                   NULLIF((ps.QuestionCount + ps.AnswerCount), 0), 2)
    END                                              AS AvgNetScorePerPost,
    CASE
        WHEN uv.TotalNetScore > 0 THEN 'Positive'
        WHEN uv.TotalNetScore < 0 THEN 'Negative'
        ELSE 'Neutral'
    END                                              AS NetScoreSign,
    (SELECT COUNT(*)
     FROM Comments c
     WHERE c.UserId = ur.Id
       AND c.CreationDate > now() - INTERVAL '30 days') AS RecentCommentCount
FROM UserReps ur
LEFT JOIN PostStats      ps ON ps.UserId = ur.Id
LEFT JOIN BadgeStats     bs ON bs.UserId = ur.Id
LEFT JOIN TagUsage       tu ON tu.UserId = ur.Id
LEFT JOIN UserVoteStats  uv ON uv.UserId = ur.Id
LEFT JOIN RecentActivity ra ON ra.UserId = ur.Id
WHERE ur.rn <= 100
ORDER BY ur.Reputation DESC, ur.Id;
