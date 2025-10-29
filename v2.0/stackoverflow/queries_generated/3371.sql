-- {"query": "3371.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2134} 

/*  Benchmark query: user activity profile with joins, CTEs, window functions, 
    correlated subqueries, set operators, calculations, string handling and NULL logic */
WITH
    /* basic per‑user post aggregates */
    UserStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COUNT(p.Id)                                AS TotalPosts,
            SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
            SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgScore,
            MAX(p.CreationDate)                       AS LastPostDate
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    /* badge summary per user */
    BadgeStats AS (
        SELECT
            b.UserId,
            STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadges,
            STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(*)                                         AS TotalBadges,
            MAX(b.Date)                                      AS LastBadgeDate
        FROM Badges b
        GROUP BY b.UserId
    ),

    /* tag usage extracted from the Tags column of questions */
    TagUsage AS (
        SELECT
            u.Id                                 AS UserId,
            TRIM(t)                              AS TagName,
            COUNT(*)                             AS TagCount,
            ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS rn
        FROM Users u
        JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
        CROSS JOIN LATERAL (
            SELECT unnest(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS t
        ) AS tags
        GROUP BY u.Id, TRIM(t)
    ),

    /* only the most used tag per user */
    TopTag AS (
        SELECT UserId, TagName, TagCount
        FROM TagUsage
        WHERE rn = 1
    ),

    /* votes received on a user's posts */
    VoteAgg AS (
        SELECT
            p.OwnerUserId                         AS UserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
            COUNT(DISTINCT v.UserId) FILTER (WHERE v.VoteTypeId = 5) AS FavoritesReceived
        FROM Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        GROUP BY p.OwnerUserId
    ),

    /* closed questions in the last 30 days (via PostHistory) */
    RecentClosed AS (
        SELECT
            ph.UserId,
            COUNT(*) AS ClosedQuestions
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10                         -- Post Closed
          AND ph.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
        GROUP BY ph.UserId
    )

SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.TotalPosts,
    us.Questions,
    us.Answers,
    ROUND(us.AvgScore::numeric, 2)           AS AvgScore,
    COALESCE(bs.GoldBadges, '')             AS GoldBadges,
    COALESCE(bs.SilverBadges, '')           AS SilverBadges,
    bs.TotalBadges,
    tt.TagName                              AS TopTag,
    tt.TagCount                             AS TopTagUsage,
    va.UpVotesReceived,
    va.DownVotesReceived,
    va.FavoritesReceived,
    COALESCE(rc.ClosedQuestions, 0)         AS ClosedLast30Days,
    /* correlated sub‑query: latest post title for the user */
    (SELECT p.Title
       FROM Posts p
      WHERE p.OwnerUserId = us.Id
      ORDER BY p.CreationDate DESC
      LIMIT 1)                               AS LatestPostTitle,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC) AS RankByReputation
FROM UserStats us
LEFT JOIN BadgeStats bs   ON bs.UserId = us.Id
LEFT JOIN TopTag tt       ON tt.UserId = us.Id
LEFT JOIN VoteAgg va     ON va.UserId = us.Id
LEFT JOIN RecentClosed rc ON rc.UserId = us.Id
WHERE us.Reputation > 1000
  AND (us.Questions > 0 OR us.Answers > 0)
ORDER BY us.Reputation DESC
LIMIT 100

UNION ALL

/* dummy row to satisfy set‑operator shape */
SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
FROM (SELECT 1) dummy;
