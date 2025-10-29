-- {"query": "3760.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3428} 

/*  Benchmark Query – heavy use of CTEs, window functions, outer joins, 
    correlated subqueries, set operators, string ops and NULL logic   */
WITH
-- Per‑user basic stats
UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown')                 AS Location,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id)            AS TotalPosts,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT MAX(CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate,
        (SELECT p.Title
         FROM Posts p
         WHERE p.OwnerUserId = u.Id
         ORDER BY p.CreationDate DESC
         LIMIT 1)                                     AS LastPostTitle,
        /* Grab up to 5 distinct tags from the user's recent posts */
        (SELECT STRING_AGG(tag, ',')
         FROM (
               SELECT DISTINCT regexp_split_to_table(p.Tags, '\><') AS tag
               FROM Posts p
               WHERE p.OwnerUserId = u.Id
                 AND p.Tags IS NOT NULL
               LIMIT 5
              ) t)                                   AS SampleTags
    FROM Users u
),

-- Badge aggregates per user
BadgeAgg AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCount,
        COUNT(*)                                      AS TotalBadges,
        MAX(b.Date)                                   AS MostRecentBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),

-- Vote totals per post
VoteStats AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId IN (2,3))      AS TotalVotes
    FROM Votes v
    GROUP BY v.PostId
),

-- Per‑user post score window
PostScores AS (
    SELECT
        p.OwnerUserId,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId)      AS AvgScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                           ORDER BY p.Score DESC NULLS LAST) AS ScoreRank
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),

-- Combine vote totals back to users
UserVoteAgg AS (
    SELECT
        p.OwnerUserId,
        SUM(vs.UpVotes)   AS UpVotes,
        SUM(vs.DownVotes) AS DownVotes,
        SUM(vs.TotalVotes)AS TotalVotes
    FROM Posts p
    LEFT JOIN VoteStats vs ON vs.PostId = p.Id
    GROUP BY p.OwnerUserId
)

-- First result set: rich user profile
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.Location,
    us.TotalPosts,
    us.QuestionCount,
    us.AnswerCount,
    us.LastPostDate,
    COALESCE(us.LastPostTitle, 'No posts')          AS LastPostTitle,
    us.SampleTags,
    COALESCE(ba.GoldCount,0)   AS GoldBadges,
    COALESCE(ba.SilverCount,0) AS SilverBadges,
    COALESCE(ba.BronzeCount,0) AS BronzeBadges,
    COALESCE(ba.TotalBadges,0) AS TotalBadges,
    ba.MostRecentBadgeDate,
    ps.AvgScore,
    ps.ScoreRank,
    uv.UpVotes,
    uv.DownVotes,
    uv.TotalVotes,
    CASE
        WHEN us.Reputation > 20000 THEN 'Elite'
        WHEN us.Reputation > 10000 THEN 'Pro'
        ELSE 'Member'
    END                                            AS Tier,
    CASE
        WHEN COALESCE(ba.GoldCount,0) >= 5 AND us.Reputation > 15000 THEN 1
        ELSE 0
    END                                            AS HighImpactFlag
FROM UserStats us
LEFT JOIN BadgeAgg   ba ON ba.UserId   = us.Id
LEFT JOIN PostScores ps ON ps.OwnerUserId = us.Id AND ps.ScoreRank = 1
LEFT JOIN UserVoteAgg uv ON uv.OwnerUserId = us.Id
WHERE us.Reputation IS NOT NULL
  AND (us.TotalPosts > 0 OR ba.TotalBadges > 0)

UNION ALL

-- Users with no posts and no badges (to stress outer joins)
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    'N/A'                AS Location,
    0                    AS TotalPosts,
    0                    AS QuestionCount,
    0                    AS AnswerCount,
    NULL                 AS LastPostDate,
    NULL                 AS LastPostTitle,
    NULL                 AS SampleTags,
    0                    AS GoldBadges,
    0                    AS SilverBadges,
    0                    AS BronzeBadges,
    0                    AS TotalBadges,
    NULL                 AS MostRecentBadgeDate,
    NULL                 AS AvgScore,
    NULL                 AS ScoreRank,
    0                    AS UpVotes,
    0                    AS DownVotes,
    0                    AS TotalVotes,
    CASE
        WHEN u.Reputation > 5000 THEN 'Rising'
        ELSE 'Newbie'
    END                  AS Tier,
    0                    AS HighImpactFlag
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts  p WHERE p.OwnerUserId = u.Id)
  AND NOT EXISTS (SELECT 1 FROM Badges b WHERE b.UserId     = u.Id)

INTERSECT

-- Narrowed view: high‑rep active users only
SELECT Id, DisplayName, Reputation, Location, TotalPosts, QuestionCount,
       AnswerCount, LastPostDate, LastPostTitle, SampleTags,
       GoldBadges, SilverBadges, BronzeBadges, TotalBadges,
       MostRecentBadgeDate, AvgScore, ScoreRank,
       UpVotes, DownVotes, TotalVotes, Tier, HighImpactFlag
FROM (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.Location,
        us.TotalPosts,
        us.QuestionCount,
        us.AnswerCount,
        us.LastPostDate,
        us.LastPostTitle,
        us.SampleTags,
        COALESCE(ba.GoldCount,0)   AS GoldBadges,
        COALESCE(ba.SilverCount,0) AS SilverBadges,
        COALESCE(ba.BronzeCount,0) AS BronzeBadges,
        COALESCE(ba.TotalBadges,0) AS TotalBadges,
        ba.MostRecentBadgeDate,
        ps.AvgScore,
        ps.ScoreRank,
        uv.UpVotes,
        uv.DownVotes,
        uv.TotalVotes,
        CASE
            WHEN us.Reputation > 20000 THEN 'Elite'
            WHEN us.Reputation > 10000 THEN 'Pro'
            ELSE 'Member'
        END                     AS Tier,
        CASE
            WHEN COALESCE(ba.GoldCount,0) >= 5 AND us.Reputation > 15000 THEN 1
            ELSE 0
        END                     AS HighImpactFlag
    FROM UserStats us
    LEFT JOIN BadgeAgg   ba ON ba.UserId   = us.Id
    LEFT JOIN PostScores ps ON ps.OwnerUserId = us.Id AND ps.ScoreRank = 1
    LEFT JOIN UserVoteAgg uv ON uv.OwnerUserId = us.Id
    WHERE us.Reputation > 5000
) sub
ORDER BY Reputation DESC NULLS LAST
LIMIT 100;
