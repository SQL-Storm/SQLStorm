-- {"query": "3854.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3217} 

/*  Complex performance‑benchmark query on the StackOverflow schema  */

WITH
/*---------------------------------------------------------------*/
/*  1️⃣  Aggregate user activity across posts, badges and votes    */
/*---------------------------------------------------------------*/
UserActivity AS (
    SELECT
        u.Id                                           AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(p_stats.TotalPosts,          0)       AS TotalPosts,
        COALESCE(p_stats.TotalAnswers,        0)       AS TotalAnswers,
        COALESCE(p_stats.TotalQuestions,      0)       AS TotalQuestions,
        COALESCE(b_stats.GoldBadges,          0)       AS GoldBadges,
        COALESCE(b_stats.SilverBadges,        0)       AS SilverBadges,
        COALESCE(b_stats.BronzeBadges,        0)       AS BronzeBadges,
        COALESCE(v_stats.UpVotes,             0)       AS UpVotes,
        COALESCE(v_stats.DownVotes,           0)       AS DownVotes,
        GREATEST(
            COALESCE(p_latest.LatestPostDate, TIMESTAMP '1970-01-01 00:00:00')
        )                                               AS LatestPostDate
    FROM Users u
    /*--- Posts aggregation ------------------------------------------------*/
    LEFT JOIN (
        SELECT
            OwnerUserId,
            COUNT(*)                                 AS TotalPosts,
            SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
            SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) p_stats
        ON p_stats.OwnerUserId = u.Id
    /*--- Badges aggregation ------------------------------------------------*/
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) b_stats
        ON b_stats.UserId = u.Id
    /*--- Votes aggregation (latest post per user) --------------------------*/
    LEFT JOIN (
        SELECT
            v.PostId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    ) v_stats
        ON v_stats.PostId = (
            SELECT TOP 1 p2.Id
            FROM Posts p2
            WHERE p2.OwnerUserId = u.Id
            ORDER BY p2.CreationDate DESC, p2.Id DESC
        )
    /*--- Latest post date per user (correlated subquery) -------------------*/
    LEFT JOIN (
        SELECT
            OwnerUserId,
            MAX(CreationDate) AS LatestPostDate
        FROM Posts
        GROUP BY OwnerUserId
    ) p_latest
        ON p_latest.OwnerUserId = u.Id
),

/*---------------------------------------------------------------*/
/*  2️⃣  Compute a composite score and rank users                */
/*---------------------------------------------------------------*/
UserScoring AS (
    SELECT
        ua.*,
        /* Composite score mixing reputation, vote balance and badges */
        (   ua.Reputation
          + (ua.UpVotes - ua.DownVotes) * 5
          + ua.GoldBadges   * 200
          + ua.SilverBadges * 100
          + ua.BronzeBadges * 50
        )                                            AS CompositeScore,
        ROW_NUMBER() OVER (
            ORDER BY
                (   ua.Reputation
                  + (ua.UpVotes - ua.DownVotes) * 5
                  + ua.GoldBadges   * 200
                  + ua.SilverBadges * 100
                  + ua.BronzeBadges * 50
                ) DESC
        )                                            AS Rank,
        PERCENT_RANK() OVER (
            ORDER BY
                (   ua.Reputation
                  + (ua.UpVotes - ua.DownVotes) * 5
                  + ua.GoldBadges   * 200
                  + ua.SilverBadges * 100
                  + ua.BronzeBadges * 50
                ) DESC
        )                                            AS Percentile
    FROM UserActivity ua
),

/*---------------------------------------------------------------*/
/*  3️⃣  Pull additional per‑user metrics using scalar sub‑queries*/
/*---------------------------------------------------------------*/
UserMetrics AS (
    SELECT
        us.*,
        /* Positive comments authored by the user */
        (SELECT COUNT(*)
         FROM Comments c
         WHERE c.UserId = us.UserId
           AND c.Score > 0)                        AS PositiveCommentCount,
        /* Number of duplicate links originated from user's posts */
        (SELECT COUNT(*)
         FROM PostLinks pl
         JOIN Posts p ON p.Id = pl.PostId
         WHERE p.OwnerUserId = us.UserId
           AND pl.LinkTypeId = 3)                  AS DuplicateLinkCount,
        /* Tier classification based on rank */
        CASE
            WHEN us.Rank <= 10  THEN 'Top10'
            WHEN us.Rank <= 100 THEN 'Top100'
            ELSE 'Other'
        END                                         AS Tier,
        /* Ensure a non‑null, non‑empty display name */
        COALESCE(NULLIF(us.DisplayName, ''), 'Anonymous') AS CleanDisplayName,
        /* Build a deterministic identifier string */
        CONCAT('User_', CAST(us.UserId AS varchar)) AS Identifier
    FROM UserScoring us
),

/*---------------------------------------------------------------*/
/*  4️⃣  Assemble a community‑wide summary row (set operator)    */
/*---------------------------------------------------------------*/
CommunitySummary AS (
    SELECT
        -1                                          AS UserId,
        'Community'                                 AS DisplayName,
        NULL                                        AS Reputation,
        SUM(TotalPosts)                             AS TotalPosts,
        SUM(TotalAnswers)                           AS TotalAnswers,
        SUM(TotalQuestions)                         AS TotalQuestions,
        NULL                                        AS GoldBadges,
        NULL                                        AS SilverBadges,
        NULL                                        AS BronzeBadges,
        NULL                                        AS UpVotes,
        NULL                                        AS DownVotes,
        MAX(LatestPostDate)                         AS LatestPostDate,
        NULL                                        AS CompositeScore,
        NULL                                        AS Rank,
        NULL                                        AS Percentile,
        'Community'                                 AS Tier,
        'Community'                                 AS CleanDisplayName,
        'User_Community'                            AS Identifier,
        NULL                                        AS PositiveCommentCount,
        NULL                                        AS DuplicateLinkCount
    FROM UserActivity
    WHERE TotalPosts > 0
)

/*=======================================================================*/
/*  Final result: union the detailed user rows with the community summary */
/*=======================================================================*/
SELECT
    um.UserId,
    um.CleanDisplayName               AS DisplayName,
    um.Reputation,
    um.TotalPosts,
    um.TotalAnswers,
    um.TotalQuestions,
    um.GoldBadges,
    um.SilverBadges,
    um.BronzeBadges,
    um.UpVotes,
    um.DownVotes,
    um.LatestPostDate,
    um.CompositeScore,
    um.Rank,
    um.Percentile,
    um.Tier,
    um.Identifier,
    um.PositiveCommentCount,
    um.DuplicateLinkCount
FROM UserMetrics um
WHERE um.Reputation > 1000
   OR um.GoldBadges   > 0

UNION ALL

SELECT
    cs.UserId,
    cs.DisplayName,
    cs.Reputation,
    cs.TotalPosts,
    cs.TotalAnswers,
    cs.TotalQuestions,
    cs.GoldBadges,
    cs.SilverBadges,
    cs.BronzeBadges,
    cs.UpVotes,
    cs.DownVotes,
    cs.LatestPostDate,
    cs.CompositeScore,
    cs.Rank,
    cs.Percentile,
    cs.Tier,
    cs.Identifier,
    cs.PositiveCommentCount,
    cs.DuplicateLinkCount
FROM CommunitySummary cs
ORDER BY
    Rank ASC NULLS LAST,
    TotalPosts DESC;
