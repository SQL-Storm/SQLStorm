-- {"query": "3740.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1763} 

WITH 
-- 1. Basic user metrics with correlated sub‑queries
UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.Location, 'Unknown') AS Location,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id)                         AS TotalBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1)        AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2)        AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3)        AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2)   AS UpVotesCast,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3)   AS DownVotesCast
    FROM Users u
),
-- 2. Recent activity windowed per user (last 90 days)
RecentActivity AS (
    SELECT 
        p.OwnerUserId                     AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)               AS RecentQuestions,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)               AS RecentAnswers,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1)           AS QuestionScoreSum,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2)           AS AnswerScoreSum,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId 
                           ORDER BY p.CreationDate DESC)      AS RecentPostRank
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
-- 3. Tag‑wise engagement (tags appear in question posts)
TagEngagement AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id)                     AS QuestionsWithTag,
        SUM(p.ViewCount)                         AS TotalViews,
        AVG(p.Score)                             AS AvgScore,
        STRING_AGG(DISTINCT u.DisplayName, ', ') FILTER (WHERE u.Reputation > 10000) 
                                                 AS TopContributors
    FROM Posts p
    JOIN LATERAL (
        SELECT unnest(string_to_array(
            regexp_replace(p.Tags, '^<|>$', '', 'g'), '><')) AS Tag
    ) AS taglist ON TRUE
    JOIN Tags t ON t.TagName = taglist.Tag
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1               -- only questions
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) > 1000
),
-- 4. Badge‑to‑post‑score ratio (only gold/silver)
BadgeScoreRatio AS (
    SELECT 
        um.Id                                 AS UserId,
        um.DisplayName,
        (CASE 
            WHEN um.TotalBadges = 0 THEN NULL
            ELSE ROUND( (um.QuestionCount + um.AnswerCount)::numeric / um.TotalBadges, 2)
         END)                                 AS PostsPerBadge,
        (CASE 
            WHEN um.GoldBadges = 0 THEN 0
            ELSE (um.QuestionCount * 2 + um.AnswerCount) / um.GoldBadges
         END)                                 AS WeightedScorePerGold
    FROM UserMetrics um
    WHERE um.Reputation >= 5000
),
-- 5. Union of two performance‑heavy extracts
TopUsersAndTags AS (
    SELECT 
        um.Id                                 AS EntityId,
        um.DisplayName                        AS EntityName,
        um.Reputation,
        um.GoldBadges,
        ra.RecentQuestions,
        ra.RecentAnswers,
        bsr.PostsPerBadge,
        bsr.WeightedScorePerGold,
        NULL::varchar                         AS TagName,
        NULL::int                             AS QuestionsWithTag,
        NULL::bigint                          AS TotalViews,
        NULL::numeric                         AS AvgScore,
        NULL::varchar                         AS TopContributors,
        ROW_NUMBER() OVER (ORDER BY um.Reputation DESC) AS RankOverall
    FROM UserMetrics um
    LEFT JOIN RecentActivity ra ON ra.UserId = um.Id
    LEFT JOIN BadgeScoreRatio bsr ON bsr.UserId = um.Id

    UNION ALL

    SELECT 
        NULL::int                            AS EntityId,
        te.TagName                           AS EntityName,
        NULL::int                            AS Reputation,
        NULL::int                            AS GoldBadges,
        NULL::int                            AS RecentQuestions,
        NULL::int                            AS RecentAnswers,
        NULL::numeric                        AS PostsPerBadge,
        NULL::numeric                        AS WeightedScorePerGold,
        te.TagName,
        te.QuestionsWithTag,
        te.TotalViews,
        te.AvgScore,
        te.TopContributors,
        ROW_NUMBER() OVER (ORDER BY te.QuestionsWithTag DESC) AS RankOverall
    FROM TagEngagement te
)
SELECT 
    t.EntityId,
    t.EntityName,
    COALESCE(t.Reputation::text, 'N/A')                     AS Reputation,
    COALESCE(t.GoldBadges::text, '0')                       AS GoldBadges,
    COALESCE(t.RecentQuestions::text, '0')                 AS RecentQuestions,
    COALESCE(t.RecentAnswers::text, '0')                   AS RecentAnswers,
    COALESCE(t.PostsPerBadge::text, 'NULL')                AS PostsPerBadge,
    COALESCE(t.WeightedScorePerGold::text, '0')            AS WeightedScorePerGold,
    COALESCE(t.TagName, '-')                               AS TagName,
    COALESCE(t.QuestionsWithTag::text, '-')               AS QuestionsWithTag,
    COALESCE(t.TotalViews::text, '-')                      AS TotalViews,
    COALESCE(ROUND(t.AvgScore, 2)::text, '-')              AS AvgScore,
    COALESCE(t.TopContributors, 'None')                    AS TopContributors,
    t.RankOverall
FROM TopUsersAndTags t
ORDER BY t.RankOverall
LIMIT 200;
