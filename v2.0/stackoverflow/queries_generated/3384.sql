-- {"query": "3384.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1730} 

/*  Benchmarking query:  a heavy‑weight analytic that pulls together users, badges,
    their recent activity, post statistics and tag information, using CTEs,
    window functions, outer joins, correlated sub‑queries, set operators and
    extensive NULL handling. */

WITH 
-- 1. Core user profile with reputation rank and total vote score
UserRanks AS (
    SELECT 
        u.Id                              AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS LocRank
    FROM Users u
),

-- 2. Badge aggregates, including tag‑based badge breakdown
BadgeAgg AS (
    SELECT 
        b.UserId,
        COUNT(*)                                   AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Gold,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silver,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronze,
        SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBadges
    FROM Badges b
    GROUP BY b.UserId
),

-- 3. Recent posts (last 90 days) per user, with answer‑to‑question ratio
RecentPosts AS (
    SELECT 
        p.OwnerUserId                         AS UserId,
        COUNT(*)                               AS RecentPostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS RecentQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS RecentAnswers,
        AVG(COALESCE(p.Score,0))               AS AvgScore,
        MAX(p.CreationDate)                   AS LastPostDate
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

-- 4. Comment activity per user, including longest comment text length
CommentStats AS (
    SELECT 
        c.UserId                              AS UserId,
        COUNT(*)                               AS CommentCount,
        MAX(LENGTH(c.Text))                    AS MaxCommentLength,
        COUNT(DISTINCT c.PostId)               AS DistinctPostsCommented
    FROM Comments c
    WHERE c.CreationDate >= CURRENT_DATE - INTERVAL '180 days'
    GROUP BY c.UserId
),

-- 5. Tag breakdown for questions posted by the user (using string split simulation)
TagCounts AS (
    SELECT 
        p.OwnerUserId                         AS UserId,
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag,
        COUNT(*)                               AS TagUseCount
    FROM Posts p
    WHERE p.PostTypeId = 1                     -- only questions
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
),

-- 6. Top tags overall (to be used in a LEFT OUTER JOIN later)
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
)

-- 7. Combine users with all the above metrics; use LEFT OUTER JOIN for optional parts
SELECT 
    ur.UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.RepRank,
    ur.LocRank,
    COALESCE(ba.TotalBadges,0)                 AS TotalBadges,
    COALESCE(ba.Gold,0)                        AS GoldBadges,
    COALESCE(ba.Silver,0)                      AS SilverBadges,
    COALESCE(ba.Bronze,0)                      AS BronzeBadges,
    COALESCE(ba.TagBadges,0)                   AS TagBasedBadges,
    COALESCE(rp.RecentPostCount,0)             AS RecentPostCount,
    COALESCE(rp.RecentQuestions,0)             AS RecentQuestions,
    COALESCE(rp.RecentAnswers,0)               AS RecentAnswers,
    CASE 
        WHEN COALESCE(rp.RecentQuestions,0) = 0 THEN NULL
        ELSE ROUND( COALESCE(rp.RecentAnswers,0)::numeric 
                    / rp.RecentQuestions, 2) 
    END                                          AS AnswerQuestionRatio,
    COALESCE(rp.AvgScore,0)                    AS AvgPostScore,
    rp.LastPostDate,
    COALESCE(cs.CommentCount,0)                AS CommentCount,
    COALESCE(cs.MaxCommentLength,0)            AS MaxCommentLength,
    COALESCE(cs.DistinctPostsCommented,0)      AS DistinctPostsCommented,
    -- Correlated sub‑query: most used tag by this user
    (SELECT tc.Tag
     FROM TagCounts tc
     WHERE tc.UserId = ur.UserId
     ORDER BY tc.TagUseCount DESC, tc.Tag
     LIMIT 1)                                   AS TopUserTag,
    -- Sub‑query with NULL logic: total votes received on user's posts
    (SELECT SUM(COALESCE(vp.Score,0))
     FROM (
         SELECT p.Id, p.Score
         FROM Posts p
         WHERE p.OwnerUserId = ur.UserId
     ) vp)                                        AS TotalPostScore,
    -- Set operator: flag users who either have >10 gold badges OR have posted >100 recent posts
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM BadgeAgg ba2 
            WHERE ba2.UserId = ur.UserId AND ba2.Gold >= 10
        )
        OR EXISTS (
            SELECT 1 FROM RecentPosts rp2 
            WHERE rp2.UserId = ur.UserId AND rp2.RecentPostCount > 100
        )
        THEN 'PowerUser' 
        ELSE 'RegularUser' 
    END                                        AS UserTier,
    -- Outer join to fetch tag popularity info for the top user tag
    tt.TagName,
    tt.Count                              AS TagGlobalCount,
    tt.TagRank
FROM UserRanks ur
LEFT OUTER JOIN BadgeAgg ba        ON ba.UserId = ur.UserId
LEFT OUTER JOIN RecentPosts rp    ON rp.UserId = ur.UserId
LEFT OUTER JOIN CommentStats cs   ON cs.UserId = ur.UserId
LEFT OUTER JOIN TopTags tt
     ON tt.TagName = (
            SELECT tc.Tag
            FROM TagCounts tc
            WHERE tc.UserId = ur.UserId
            ORDER BY tc.TagUseCount DESC, tc.Tag
            LIMIT 1
        )
WHERE ur.RepRank <= 5000                           -- focus on top 5k users
  AND ur.Reputation > 1000                         -- additional filter
ORDER BY ur.RepRank ASC
LIMIT 1000;
