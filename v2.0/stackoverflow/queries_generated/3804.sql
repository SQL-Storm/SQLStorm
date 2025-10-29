-- {"query": "3804.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1657} 

WITH 
-- 1. Aggregate badge counts per user, pivoted by class
BadgeAgg AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ') FILTER (WHERE b.Class = 1) AS GoldBadgeNames,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 2 THEN b.Name END, ', ') FILTER (WHERE b.Class = 2) AS SilverBadgeNames,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 3 THEN b.Name END, ', ') FILTER (WHERE b.Class = 3) AS BronzeBadgeNames
    FROM Badges b
    GROUP BY b.UserId
),

-- 2. Compute post statistics per user, including a correlated sub‑query for the latest post title
PostStats AS (
    SELECT 
        p.OwnerUserId                                         AS UserId,
        COUNT(*)                                              AS TotalPosts,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)              AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)              AS AnswerCount,
        AVG(p.Score)                                          AS AvgScore,
        MAX(p.CreationDate)                                   AS FirstPostDate,
        MIN(p.CreationDate)                                   AS LastPostDate,
        MAX(p.Title) FILTER (WHERE p.PostTypeId = 1)          AS LatestQuestionTitle,
        (SELECT ph.Text
         FROM PostHistory ph
         WHERE ph.PostId = p.Id
           AND ph.PostHistoryTypeId = 2               -- Initial Body
         ORDER BY ph.CreationDate ASC
         LIMIT 1)                                            AS OriginalBodySnippet
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

-- 3. Recent voting activity per user (last 30 days)
VoteStats AS (
    SELECT 
        v.UserId,
        COUNT(*)                                          AS VotesLast30Days,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS Favorites
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
),

-- 4. Users with no activity (left‑joined to the previous CTEs)
AllUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(b.GoldBadges, 0)      AS GoldBadges,
        COALESCE(b.SilverBadges, 0)    AS SilverBadges,
        COALESCE(b.BronzeBadges, 0)    AS BronzeBadges,
        COALESCE(p.TotalPosts, 0)      AS TotalPosts,
        COALESCE(p.QuestionCount, 0)   AS QuestionCount,
        COALESCE(p.AnswerCount, 0)     AS AnswerCount,
        COALESCE(p.AvgScore, 0)        AS AvgScore,
        p.LatestQuestionTitle,
        p.OriginalBodySnippet,
        COALESCE(v.VotesLast30Days, 0) AS VotesLast30Days,
        COALESCE(v.UpVotes, 0)         AS UpVotes,
        COALESCE(v.DownVotes, 0)       AS DownVotes,
        COALESCE(v.Favorites, 0)       AS Favorites,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        CASE 
            WHEN u.Reputation >= 20000 THEN 'Legendary'
            WHEN u.Reputation >= 10000 THEN 'Guru'
            WHEN u.Reputation >= 5000  THEN 'Expert'
            WHEN u.Reputation >= 1000  THEN 'Contributor'
            ELSE 'Newbie'
        END AS ReputationTier,
        -- Complex calculated field mixing strings, dates, and NULL logic
        (CASE 
            WHEN p.TotalPosts IS NULL THEN 'No posts yet'
            WHEN p.TotalPosts = 0 THEN 'Inactive'
            ELSE CONCAT(
                 'Active for ', 
                 DATE_PART('day', GREATEST(u.LastAccessDate, CURRENT_DATE) - u.CreationDate),
                 ' days, ',
                 COALESCE(p.QuestionCount,0), ' Q, ',
                 COALESCE(p.AnswerCount,0), ' A'
               )
         END) AS ActivitySummary
    FROM Users u
    LEFT JOIN BadgeAgg b   ON b.UserId = u.Id
    LEFT JOIN PostStats p  ON p.UserId = u.Id
    LEFT JOIN VoteStats v  ON v.UserId = u.Id
),

-- 5. Top 10 users by reputation (using UNION ALL to append a static row for comparison)
TopReputation AS (
    SELECT 
        Id,
        DisplayName,
        Reputation,
        ReputationRank,
        'Top10' AS Category
    FROM AllUsers
    WHERE ReputationRank <= 10
    UNION ALL
    SELECT 
        0 AS Id,
        'Community' AS DisplayName,
        SUM(Reputation) AS Reputation,
        NULL AS ReputationRank,
        'Aggregate' AS Category
    FROM AllUsers
)

SELECT 
    a.Id,
    a.DisplayName,
    a.Reputation,
    a.ReputationRank,
    a.ReputationTier,
    a.GoldBadges,
    a.SilverBadges,
    a.BronzeBadges,
    a.TotalPosts,
    a.QuestionCount,
    a.AnswerCount,
    ROUND(a.AvgScore::numeric,2)                  AS AvgScoreRounded,
    a.LatestQuestionTitle,
    LEFT(a.OriginalBodySnippet,200) || CASE 
                                            WHEN LENGTH(a.OriginalBodySnippet) > 200 THEN '...' 
                                            ELSE '' 
                                         END AS OriginalBodyPreview,
    a.VotesLast30Days,
    a.UpVotes,
    a.DownVotes,
    a.Favorites,
    a.ActivitySummary,
    t.Category,
    t.Reputation AS CategoryReputation
FROM AllUsers a
LEFT JOIN TopReputation t 
     ON (t.Id = a.Id AND t.Category = 'Top10')
ORDER BY a.ReputationRank
LIMIT 100;
