-- {"query": "3854.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3217}
WITH
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
            SELECT p2.Id
            FROM Posts p2
            WHERE p2.OwnerUserId = u.Id
            ORDER BY p2.CreationDate DESC, p2.Id DESC
            LIMIT 1
        )
    LEFT JOIN (
        SELECT
            OwnerUserId,
            MAX(CreationDate) AS LatestPostDate
        FROM Posts
        GROUP BY OwnerUserId
    ) p_latest
        ON p_latest.OwnerUserId = u.Id
),

UserScoring AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalPosts,
        ua.TotalAnswers,
        ua.TotalQuestions,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.UpVotes,
        ua.DownVotes,
        ua.LatestPostDate,
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

UserMetrics AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.TotalPosts,
        us.TotalAnswers,
        us.TotalQuestions,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.UpVotes,
        us.DownVotes,
        us.LatestPostDate,
        us.CompositeScore,
        us.Rank,
        us.Percentile,
        (SELECT COUNT(*)
         FROM Comments c
         WHERE c.UserId = us.UserId
           AND c.Score > 0)                        AS PositiveCommentCount,
        (SELECT COUNT(*)
         FROM PostLinks pl
         JOIN Posts p ON p.Id = pl.PostId
         WHERE p.OwnerUserId = us.UserId
           AND pl.LinkTypeId = 3)                  AS DuplicateLinkCount,
        CASE
            WHEN us.Rank <= 10  THEN 'Top10'
            WHEN us.Rank <= 100 THEN 'Top100'
            ELSE 'Other'
        END                                         AS Tier,
        COALESCE(NULLIF(us.DisplayName, ''), 'Anonymous') AS CleanDisplayName,
        'User_' || CAST(us.UserId AS VARCHAR)       AS Identifier
    FROM UserScoring us
),

CommunitySummary AS (
    SELECT
        -1                                          AS UserId,
        'Community'                                 AS DisplayName,
        CAST(NULL AS INTEGER)                       AS Reputation,
        SUM(TotalPosts)                             AS TotalPosts,
        SUM(TotalAnswers)                           AS TotalAnswers,
        SUM(TotalQuestions)                         AS TotalQuestions,
        CAST(NULL AS INTEGER)                       AS GoldBadges,
        CAST(NULL AS INTEGER)                       AS SilverBadges,
        CAST(NULL AS INTEGER)                       AS BronzeBadges,
        CAST(NULL AS INTEGER)                       AS UpVotes,
        CAST(NULL AS INTEGER)                       AS DownVotes,
        MAX(LatestPostDate)                         AS LatestPostDate,
        CAST(NULL AS NUMERIC)                       AS CompositeScore,
        CAST(NULL AS INTEGER)                       AS Rank,
        CAST(NULL AS NUMERIC)                       AS Percentile,
        'Community'                                 AS Tier,
        'Community'                                 AS CleanDisplayName,
        'User_Community'                            AS Identifier,
        CAST(NULL AS INTEGER)                       AS PositiveCommentCount,
        CAST(NULL AS INTEGER)                       AS DuplicateLinkCount
    FROM UserActivity
    WHERE TotalPosts > 0
)

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
WHERE (um.Reputation IS NOT NULL AND um.Reputation > 1000)
   OR (um.GoldBadges IS NOT NULL AND um.GoldBadges > 0)

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
    Rank ASC,
    TotalPosts DESC;