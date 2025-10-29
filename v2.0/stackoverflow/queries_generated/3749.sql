-- {"query": "3749.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2114} 

/*  Comprehensive benchmark query mixing CTEs, window functions, outer joins, 
    correlated subqueries, set operators, complex predicates, string ops and NULL logic  */
WITH
    /* 1️⃣ Basic user activity metrics */
    usr AS (
        SELECT
            u.Id                                   AS UserId,
            u.DisplayName,
            u.Reputation,
            COALESCE(u.UpVotes,0)                  AS UpVotes,
            COALESCE(u.DownVotes,0)                AS DownVotes,
            COUNT(p.Id)                            AS TotalPosts,
            SUM(COALESCE(p.Score,0))               AS TotalPostScore,
            AVG(COALESCE(p.Score,0))               AS AvgPostScore,
            MAX(p.CreationDate)                   AS LastPostDate,
            MIN(p.CreationDate)                   AS FirstPostDate
        FROM Users u
        LEFT JOIN Posts p
               ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
    ),
    
    /* 2️⃣ Badge aggregation with tag‑based flag */
    bdg AS (
        SELECT
            b.UserId,
            COUNT(*)                                 AS BadgeCount,
            SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBadgeCount,
            MAX(CASE WHEN b.Class = 1 THEN b.Date END)      AS LatestGoldBadgeDate
        FROM Badges b
        GROUP BY b.UserId
    ),
    
    /* 3️⃣ Recent voting activity per user (correlated subquery) */
    vote_recent AS (
        SELECT
            v.UserId,
            COUNT(*)                                 AS RecentVoteCount,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END)   AS RecentUpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS RecentDownVotes,
            MAX(v.CreationDate)                      AS LastVoteDate
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30' DAY
        GROUP BY v.UserId
    ),
    
    /* 4️⃣ Latest comment per post (correlated subquery) */
    latest_comment AS (
        SELECT
            c.PostId,
            (SELECT TEXT
               FROM Comments c2
              WHERE c2.PostId = c.PostId
              ORDER BY c2.CreationDate DESC
              LIMIT 1)                                 AS LastCommentText,
            (SELECT MAX(CreationDate)
               FROM Comments c3
              WHERE c3.PostId = c.PostId)              AS LastCommentDate
        FROM Comments c
        GROUP BY c.PostId
    ),
    
    /* 5️⃣ Tag‑wise post statistics – using string split via regex */
    tag_stats AS (
        SELECT
            t.TagName,
            COUNT(p.Id)                               AS TagPostCount,
            SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TagQuestionCount,
            AVG(COALESCE(p.Score,0))                  AS TagAvgScore,
            MAX(p.CreationDate)                       AS TagMostRecentPost
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT regexp_split_to_table(
                       TRIM(BOTH '<>' FROM p.Tags),
                       '><'
                   ) AS Tag
        ) AS tag_split
        JOIN Tags t ON t.TagName = tag_split.Tag
        WHERE p.Tags IS NOT NULL
          AND p.PostTypeId IN (1,2)                     -- questions & answers
        GROUP BY t.TagName
    ),
    
    /* 6️⃣ Combine user‑centric aggregates */
    user_combined AS (
        SELECT
            u.UserId,
            u.DisplayName,
            u.Reputation,
            u.TotalPosts,
            u.TotalPostScore,
            u.AvgPostScore,
            COALESCE(b.BadgeCount,0)               AS BadgeCount,
            COALESCE(b.TagBadgeCount,0)            AS TagBadgeCount,
            b.LatestGoldBadgeDate,
            COALESCE(v.RecentVoteCount,0)          AS RecentVoteCount,
            COALESCE(v.RecentUpVotes,0)            AS RecentUpVotes,
            COALESCE(v.RecentDownVotes,0)          AS RecentDownVotes,
            v.LastVoteDate,
            u.LastPostDate,
            u.FirstPostDate,
            /* 7️⃣ Window: running total of post scores ordered by last post date */
            SUM(u.TotalPostScore) OVER (
                PARTITION BY u.Reputation / 1000
                ORDER BY u.LastPostDate
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            )                                         AS RunningScoreByRepBand
        FROM usr u
        LEFT JOIN bdg b   ON b.UserId = u.UserId
        LEFT JOIN vote_recent v ON v.UserId = u.UserId
    ),
    
    /* 8️⃣ Users with recent activity on duplicate‑linked questions (set operator) */
    dup_users AS (
        SELECT DISTINCT
            pu.OwnerUserId                         AS UserId
        FROM Posts pu
        JOIN PostLinks pl
          ON pl.PostId = pu.Id
         AND pl.LinkTypeId = 3                      -- Duplicate link
        WHERE pu.PostTypeId = 1                     -- Question
          AND pl.CreationDate >= CURRENT_DATE - INTERVAL '90' DAY
        UNION
        SELECT DISTINCT
            pu2.OwnerUserId
        FROM Posts pu2
        JOIN PostLinks pl2
          ON pl2.RelatedPostId = pu2.Id
         AND pl2.LinkTypeId = 3
        WHERE pu2.PostTypeId = 1
          AND pl2.CreationDate >= CURRENT_DATE - INTERVAL '90' DAY
    )
    
/* Final SELECT – pick top users by reputation, enrich with latest comment on their top post,
   and filter to those involved in duplicate links, applying complex predicates and NULL handling */
SELECT
    uc.UserId,
    uc.DisplayName,
    uc.Reputation,
    uc.TotalPosts,
    uc.TotalPostScore,
    uc.AvgPostScore,
    uc.BadgeCount,
    uc.TagBadgeCount,
    TO_CHAR(uc.LatestGoldBadgeDate, 'YYYY-MM-DD')       AS LatestGoldBadge,
    uc.RecentVoteCount,
    uc.RecentUpVotes,
    uc.RecentDownVotes,
    TO_CHAR(uc.LastVoteDate, 'YYYY-MM-DD HH24:MI')      AS LastVote,
    TO_CHAR(uc.LastPostDate, 'YYYY-MM-DD HH24:MI')      AS LastPost,
    COALESCE(lc.LastCommentText, '<no comments>')       AS LastCommentSnippet,
    CASE
        WHEN uc.Reputation IS NULL THEN 'Unknown'
        WHEN uc.Reputation >= 20000 THEN 'Legendary'
        WHEN uc.Reputation >= 10000 THEN 'Expert'
        WHEN uc.Reputation >= 5000  THEN 'Experienced'
        ELSE 'Novice'
    END                                                 AS ReputationTier,
    uc.RunningScoreByRepBand
FROM user_combined uc
LEFT JOIN latest_comment lc
       ON lc.PostId = (
            SELECT p.Id
            FROM Posts p
            WHERE p.OwnerUserId = uc.UserId
              AND p.PostTypeId = 1               -- question
            ORDER BY p.Score DESC NULLS LAST
            LIMIT 1
       )
WHERE uc.UserId IN (SELECT UserId FROM dup_users)
  AND (uc.TotalPosts > 5 OR uc.BadgeCount > 0)
  AND COALESCE(uc.RecentVoteCount,0) > 0
ORDER BY uc.Reputation DESC, uc.TotalPostScore DESC
FETCH FIRST 20 ROWS ONLY;
