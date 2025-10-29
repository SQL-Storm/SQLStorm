-- {"query": "3403.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2839} 

WITH 
    /* Aggregate posts per user */
    UserPostAgg AS (
        SELECT 
            u.Id                               AS UserId,
            COUNT(p.Id)                        AS TotalPosts,
            SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
            SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgScore,
            MAX(p.CreationDate)                AS LastPostDate
        FROM Users u
        LEFT JOIN Posts p
               ON p.OwnerUserId = u.Id
        GROUP BY u.Id
    ),

    /* Aggregate badges per user */
    UserBadgeAgg AS (
        SELECT 
            b.UserId,
            COUNT(*)                                           AS TotalBadges,
            COUNT(*) FILTER (WHERE b.Class = 1)                AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2)                AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3)                AS BronzeBadges,
            STRING_AGG(DISTINCT b.Name, ';')                   AS BadgeList
        FROM Badges b
        GROUP BY b.UserId
    ),

    /* Aggregate votes given by each user */
    UserVoteAgg AS (
        SELECT 
            v.UserId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END)        AS UpVotesGiven,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END)        AS DownVotesGiven,
            MAX(v.CreationDate)                               AS LastVoteDate
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.UserId
    ),

    /* Extract recent tags used in questions (last 30 days) */
    UserRecentTags AS (
        SELECT 
            p.OwnerUserId                                    AS UserId,
            UNNEST(string_to_array(
                      TRIM(BOTH '<>' FROM COALESCE(p.Tags, '')),
                      '><'))                                 AS Tag
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.CreationDate > CURRENT_DATE - INTERVAL '30 days'
    ),

    /* Determine each user's most used recent tag */
    UserTopTag AS (
        SELECT 
            urt.UserId,
            t.TagName,
            COUNT(*)                                          AS TagUsage,
            ROW_NUMBER() OVER (PARTITION BY urt.UserId 
                               ORDER BY COUNT(*) DESC)      AS rn
        FROM UserRecentTags urt
        JOIN Tags t ON t.TagName = urt.Tag
        GROUP BY urt.UserId, t.TagName
    ),

    /* Final top‑tag per user */
    TopTagPerUser AS (
        SELECT UserId, TagName AS Tag
        FROM UserTopTag
        WHERE rn = 1
    )

SELECT 
    u.Id,
    u.DisplayName,
    COALESCE(upa.TotalPosts,0)                AS TotalPosts,
    COALESCE(upa.Questions,0)                 AS Questions,
    COALESCE(upa.Answers,0)                   AS Answers,
    ROUND(COALESCE(upa.AvgScore,0),2)         AS AvgScore,
    upa.LastPostDate,
    COALESCE(uba.TotalBadges,0)               AS TotalBadges,
    COALESCE(uba.GoldBadges,0)                AS GoldBadges,
    COALESCE(uba.SilverBadges,0)              AS SilverBadges,
    COALESCE(uba.BronzeBadges,0)              AS BronzeBadges,
    uba.BadgeList,
    COALESCE(uvg.UpVotesGiven,0)              AS UpVotesGiven,
    COALESCE(uvg.DownVotesGiven,0)            AS DownVotesGiven,
    uvg.LastVoteDate,
    COALESCE(tt.Tag, 'NoRecentTag')           AS TopRecentTag,
    CASE 
        WHEN EXISTS (SELECT 1 
                     FROM Posts p2
                     WHERE p2.OwnerUserId = u.Id
                       AND p2.Score < 0
                       AND p2.CreationDate > CURRENT_DATE - INTERVAL '90 days')
        THEN 1 ELSE 0 
    END                                      AS HasRecentNegativeScorePost
FROM Users u
LEFT JOIN UserPostAgg   upa ON upa.UserId = u.Id
LEFT JOIN UserBadgeAgg  uba ON uba.UserId = u.Id
LEFT JOIN UserVoteAgg   uvg ON uvg.UserId = u.Id
LEFT JOIN TopTagPerUser tt  ON tt.UserId = u.Id
WHERE u.CreationDate < CURRENT_DATE - INTERVAL '1 year'
  AND (u.Reputation > 1000 OR u.Views > 5000)
ORDER BY TotalPosts DESC, u.Reputation DESC
LIMIT 100

UNION ALL

SELECT 
    -1                                            AS Id,
    'Aggregate Summary'                           AS DisplayName,
    SUM(COALESCE(upa.TotalPosts,0))                AS TotalPosts,
    SUM(COALESCE(upa.Questions,0))                 AS Questions,
    SUM(COALESCE(upa.Answers,0))                   AS Answers,
    ROUND(AVG(COALESCE(upa.AvgScore,0)),2)         AS AvgScore,
    MAX(upa.LastPostDate)                         AS LastPostDate,
    SUM(COALESCE(uba.TotalBadges,0))               AS TotalBadges,
    SUM(COALESCE(uba.GoldBadges,0))                AS GoldBadges,
    SUM(COALESCE(uba.SilverBadges,0))              AS SilverBadges,
    SUM(COALESCE(uba.BronzeBadges,0))              AS BronzeBadges,
    NULL                                           AS BadgeList,
    SUM(COALESCE(uvg.UpVotesGiven,0))              AS UpVotesGiven,
    SUM(COALESCE(uvg.DownVotesGiven,0))            AS DownVotesGiven,
    MAX(uvg.LastVoteDate)                         AS LastVoteDate,
    NULL                                           AS TopRecentTag,
    NULL                                           AS HasRecentNegativeScorePost
FROM Users u
LEFT JOIN UserPostAgg   upa ON upa.UserId = u.Id
LEFT JOIN UserBadgeAgg  uba ON uba.UserId = u.Id
LEFT JOIN UserVoteAgg   uvg ON uvg.UserId = u.Id
WHERE u.CreationDate < CURRENT_DATE - INTERVAL '1 year'
  AND (u.Reputation > 1000 OR u.Views > 5000);
