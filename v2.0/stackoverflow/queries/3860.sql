-- {"query": "3860.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2179}
WITH 
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)  AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)  AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)  AS BronzeBadges,
        COUNT(*)                                        AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserPostMetrics AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)                            AS Questions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)                            AS Answers,
        AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score END)                   AS AvgScore,
        MAX(p.CreationDate)                                                     AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserRecentVotes AS (
    SELECT 
        v.UserId,
        ROW_NUMBER() OVER (PARTITION BY v.UserId ORDER BY v.CreationDate DESC) AS VoteRank,
        v.VoteTypeId,
        v.CreationDate
    FROM Votes v
    WHERE v.UserId IS NOT NULL
),
TopUsers AS (
    SELECT 
        u.Id,
        COALESCE(u.DisplayName, 'Anonymous')                         AS DisplayName,
        u.Reputation,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TotalBadges,
        upm.Questions,
        upm.Answers,
        ROUND(CAST(upm.AvgScore AS NUMERIC), 2)                         AS AvgScore,
        upm.LastPostDate,
        (SELECT COUNT(*) 
         FROM Posts p2 
         WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1)            AS DirectQuestionCount,
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.UserId = u.Id)                                       AS CommentCount,
        (SELECT STRING_AGG(t.TagName, ', ')
         FROM Tags t
         JOIN (
             SELECT DISTINCT TRIM(BOTH '<>' FROM tag) AS TagName
             FROM (
                 SELECT UNNEST(string_to_array(p.Tags, '><')) AS tag
                 FROM Posts p
                 WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1
             ) sub
         ) pt ON pt.TagName = t.TagName
         LIMIT 5)                                                     AS TopTags,
        CASE 
            WHEN u.Reputation > 20000 THEN 'PowerUser'
            WHEN u.Reputation > 10000 THEN 'Trusted'
            ELSE 'Newbie'
        END                                                         AS ReputationBand,
        (COALESCE(u.DisplayName, 'User') || ' (' || COALESCE(u.Location, 'Unknown') || ')') AS UserLabel
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
    LEFT JOIN UserPostMetrics upm ON upm.UserId = u.Id
    WHERE (u.Reputation > 5000 OR COALESCE(ubc.TotalBadges,0) > 10)
      AND (u.Location IS NOT NULL OR LOWER(COALESCE(u.AboutMe,'')) LIKE '%sql%')
),
UserWithNoPosts AS (
    SELECT 
        u.Id,
        COALESCE(u.DisplayName, 'Anonymous')                         AS DisplayName,
        u.Reputation,
        CAST(NULL AS INTEGER)                                         AS GoldBadges,
        CAST(NULL AS INTEGER)                                         AS SilverBadges,
        CAST(NULL AS INTEGER)                                         AS BronzeBadges,
        CAST(NULL AS INTEGER)                                         AS TotalBadges,
        0                                                            AS Questions,
        0                                                            AS Answers,
        CAST(NULL AS NUMERIC)                                         AS AvgScore,
        CAST(NULL AS TIMESTAMP)                                       AS LastPostDate,
        0                                                            AS DirectQuestionCount,
        0                                                            AS CommentCount,
        CAST(NULL AS TEXT)                                            AS TopTags,
        'NoPosts'                                                     AS ReputationBand,
        (COALESCE(u.DisplayName, 'User') || ' (' || COALESCE(u.Location, 'Unknown') || ')') AS UserLabel
    FROM Users u
    WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
)
SELECT Combined.Id,
       Combined.DisplayName,
       Combined.Reputation,
       Combined.GoldBadges,
       Combined.SilverBadges,
       Combined.BronzeBadges,
       Combined.TotalBadges,
       Combined.Questions,
       Combined.Answers,
       Combined.AvgScore,
       Combined.LastPostDate,
       Combined.DirectQuestionCount,
       Combined.CommentCount,
       Combined.TopTags,
       Combined.ReputationBand,
       Combined.UserLabel,
       Combined.RankOverall
FROM (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        u.TotalBadges,
        u.Questions,
        u.Answers,
        u.AvgScore,
        u.LastPostDate,
        u.DirectQuestionCount,
        u.CommentCount,
        u.TopTags,
        u.ReputationBand,
        u.UserLabel,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.TotalBadges DESC) AS RankOverall
    FROM TopUsers u
    UNION ALL
    SELECT 
        n.Id,
        n.DisplayName,
        n.Reputation,
        n.GoldBadges,
        n.SilverBadges,
        n.BronzeBadges,
        n.TotalBadges,
        n.Questions,
        n.Answers,
        n.AvgScore,
        n.LastPostDate,
        n.DirectQuestionCount,
        n.CommentCount,
        n.TopTags,
        n.ReputationBand,
        n.UserLabel,
        CAST(NULL AS BIGINT) AS RankOverall
    FROM UserWithNoPosts n
) AS Combined
ORDER BY RankOverall NULLS LAST, Reputation DESC
LIMIT 100;