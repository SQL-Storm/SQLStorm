-- {"query": "3671.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2535} 

WITH 
    -- Per‑user aggregates
    UserStats AS (
        SELECT 
            u.Id,
            u.DisplayName,
            u.Reputation,
            COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)               AS NetVotes,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
            (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
            (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount
        FROM Users u
    ),

    -- Tag usage and contributors
    TagStats AS (
        SELECT 
            t.TagName,
            t.Count                                            AS TagUsage,
            ROW_NUMBER() OVER (ORDER BY t.Count DESC)          AS TagRank,
            STRING_AGG(DISTINCT CAST(p.OwnerUserId AS varchar), ',')
                FILTER (WHERE p.OwnerUserId IS NOT NULL)      AS ContributingUserIds
        FROM Tags t
        LEFT JOIN Posts p 
            ON p.Tags LIKE '%<' || t.TagName || '>%'
        GROUP BY t.Id, t.TagName, t.Count
    ),

    -- Average scores of a user’s questions
    QuestionScore AS (
        SELECT 
            p.OwnerUserId,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL)   AS AvgQuestionScore,
            MAX(p.Score)                                      AS MaxQuestionScore,
            MIN(p.Score)                                      AS MinQuestionScore
        FROM Posts p
        WHERE p.PostTypeId = 1
        GROUP BY p.OwnerUserId
    ),

    -- Most recent activity per user
    RecentActivity AS (
        SELECT 
            u.Id,
            MAX(p.LastActivityDate)   AS LastPostActivity,
            MAX(c.CreationDate)       AS LastCommentDate,
            MAX(v.CreationDate)       AS LastVoteDate
        FROM Users u
        LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
        LEFT JOIN Comments c ON c.UserId      = u.Id
        LEFT JOIN Votes    v ON v.UserId      = u.Id
        GROUP BY u.Id
    ),

    -- Combine all per‑user data and compute ranking/window functions
    Combined AS (
        SELECT 
            us.Id,
            us.DisplayName,
            us.Reputation,
            us.NetVotes,
            us.GoldBadges,
            us.SilverBadges,
            us.BronzeBadges,
            us.QuestionCount,
            us.AnswerCount,
            qs.AvgQuestionScore,
            qs.MaxQuestionScore,
            qs.MinQuestionScore,
            ra.LastPostActivity,
            ra.LastCommentDate,
            ra.LastVoteDate,
            ROW_NUMBER()   OVER (ORDER BY us.Reputation DESC)               AS RepRank,
            PERCENT_RANK() OVER (ORDER BY us.Reputation DESC)               AS RepPercentile
        FROM UserStats       us
        LEFT JOIN QuestionScore   qs ON qs.OwnerUserId = us.Id
        LEFT JOIN RecentActivity  ra ON ra.Id         = us.Id
    )

-- Final result set mixing detailed rows with an aggregated summary
SELECT
    c.Id,
    c.DisplayName,
    c.Reputation,
    c.NetVotes,
    c.GoldBadges,
    c.SilverBadges,
    c.BronzeBadges,
    c.QuestionCount,
    c.AnswerCount,
    ROUND(c.AvgQuestionScore::numeric,2)   AS AvgQScore,
    c.MaxQuestionScore,
    c.MinQuestionScore,
    COALESCE(c.LastPostActivity, TIMESTAMP '1970-01-01') AS LastPostActivity,
    COALESCE(c.LastCommentDate,  TIMESTAMP '1970-01-01') AS LastCommentDate,
    COALESCE(c.LastVoteDate,     TIMESTAMP '1970-01-01') AS LastVoteDate,
    c.RepRank,
    ROUND(c.RepPercentile*100,1)           AS RepPercentilePct,
    CASE
        WHEN c.GoldBadges > 0 THEN 'Elite'
        WHEN c.SilverBadges > 5 THEN 'Veteran'
        ELSE 'Member'
    END                                    AS UserTier,
    t.TagName,
    t.TagUsage,
    t.TagRank,
    t.ContributingUserIds
FROM Combined c
LEFT JOIN LATERAL (
    SELECT ts.TagName, ts.TagUsage, ts.TagRank, ts.ContributingUserIds
    FROM TagStats ts
    WHERE ts.ContributingUserIds LIKE '%' || c.Id::varchar || '%'
    ORDER BY ts.TagUsage DESC
    LIMIT 1
) t ON TRUE
WHERE c.RepPercentile > 0.75

UNION ALL

-- Aggregate row for quick overview
SELECT
    NULL        AS Id,
    'Aggregated Stats' AS DisplayName,
    NULL,
    NULL,
    SUM(us.GoldBadges)   AS GoldBadges,
    SUM(us.SilverBadges) AS SilverBadges,
    SUM(us.BronzeBadges) AS BronzeBadges,
    SUM(us.QuestionCount) AS TotalQuestions,
    SUM(us.AnswerCount)   AS TotalAnswers,
    ROUND(AVG(us.AvgQuestionScore)::numeric,2) AS AvgQScoreOverall,
    MAX(us.MaxQuestionScore)                 AS MaxQScoreOverall,
    MIN(us.MinQuestionScore)                 AS MinQScoreOverall,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM UserStats us
WHERE us.Reputation IS NOT NULL;
