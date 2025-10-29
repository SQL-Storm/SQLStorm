-- {"query": "3258.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2294} 

WITH 
-- 1️⃣ Aggregate user‑level statistics
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1)                AS QuestionCount,
        COUNT(DISTINCT a.Id) FILTER (WHERE a.PostTypeId = 2)                AS AnswerCount,
        COALESCE(SUM(p.Score),0)                                            AS TotalScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)                        AS AvgQuestionScore,
        MAX(p.CreationDate)                                                AS LastPostDate,
        COUNT(b.Id)                                                         AS BadgeCount,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END)                             AS GoldBadgeCount,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END)                             AS SilverBadgeCount,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END)                             AS BronzeBadgeCount
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    LEFT JOIN Posts a   ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    LEFT JOIN Badges b  ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

-- 2️⃣ Rank the high‑reputation users
TopUsers AS (
    SELECT 
        *,
        RANK() OVER (ORDER BY Reputation DESC, BadgeCount DESC) AS RepRank
    FROM UserStats
    WHERE Reputation > 10000
),

-- 3️⃣ Tag‑level activity (uses string parsing & aggregation)
TagActivity AS (
    SELECT 
        t.TagName,
        COUNT(p.Id)                                           AS QuestionCount,
        AVG(p.Score)                                          AS AvgScore,
        STRING_AGG(DISTINCT u.DisplayName, ', ') 
            FILTER (WHERE u.Reputation > 20000)               AS TopUserNames
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 100
),

-- 4️⃣ Recent voting activity (set operator inside the CTE)
RecentVotes AS (
    SELECT 
        v.PostId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')   AS UpVotes,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotes,
        MAX(v.CreationDate)                         AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.PostId
)

-- 5️⃣ Final result mixing everything (outer joins, correlated subquery, window, NULL logic, UNION)
SELECT 
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.TotalScore,
    tu.AvgQuestionScore,
    tu.GoldBadgeCount,
    tu.SilverBadgeCount,
    tu.BronzeBadgeCount,
    COALESCE(rv.UpVotes,0)          AS RecentUpVotes,
    COALESCE(rv.DownVotes,0)        AS RecentDownVotes,
    rv.LastVoteDate,
    ARRAY_AGG(DISTINCT ta.TagName) FILTER (WHERE ta.AvgScore > 0) AS ActiveHighScoreTags,
    STRING_AGG(DISTINCT ta.TopUserNames, '; ')                     AS TagTopUserSummaries
FROM TopUsers tu
LEFT JOIN LATERAL (
        SELECT Id 
        FROM Posts p 
        WHERE p.OwnerUserId = tu.Id 
        ORDER BY p.CreationDate DESC 
        LIMIT 1
) latest_post ON TRUE                                          -- correlated subquery via LATERAL
LEFT JOIN RecentVotes rv   ON rv.PostId = latest_post.Id
LEFT JOIN TagActivity ta   ON ta.TagName = ANY (
                                    SELECT UNNEST(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><'))
                                    FROM Posts p
                                    WHERE p.Id = latest_post.Id
                                )
GROUP BY 
    tu.Id, tu.DisplayName, tu.Reputation, tu.QuestionCount, tu.AnswerCount,
    tu.TotalScore, tu.AvgQuestionScore, tu.GoldBadgeCount, tu.SilverBadgeCount,
    tu.BronzeBadgeCount, rv.UpVotes, rv.DownVotes, rv.LastVoteDate
HAVING COUNT(*) > 0

UNION ALL

-- 6️⃣ Summary row using set operator
SELECT 
    NULL                     AS Id,
    'SUMMARY'                AS DisplayName,
    NULL                     AS Reputation,
    SUM(QuestionCount)       AS QuestionCount,
    SUM(AnswerCount)         AS AnswerCount,
    SUM(TotalScore)          AS TotalScore,
    AVG(AvgQuestionScore)    AS AvgQuestionScore,
    SUM(GoldBadgeCount)      AS GoldBadgeCount,
    SUM(SilverBadgeCount)    AS SilverBadgeCount,
    SUM(BronzeBadgeCount)    AS BronzeBadgeCount,
    SUM(RecentUpVotes)       AS RecentUpVotes,
    SUM(RecentDownVotes)     AS RecentDownVotes,
    MAX(LastVoteDate)        AS LastVoteDate,
    NULL                     AS ActiveHighScoreTags,
    NULL                     AS TagTopUserSummaries
FROM (
    SELECT 
        tu.*, 
        rv.UpVotes, 
        rv.DownVotes, 
        rv.LastVoteDate
    FROM TopUsers tu
    LEFT JOIN RecentVotes rv ON rv.PostId = (
        SELECT Id 
        FROM Posts p 
        WHERE p.OwnerUserId = tu.Id 
        ORDER BY p.CreationDate DESC 
        LIMIT 1
    )
) sub;
