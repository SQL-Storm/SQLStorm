WITH 
    UserPostAgg AS (
        SELECT 
            u.Id                               AS UserId,
            COUNT(p.Id)                        AS TotalPosts,
            SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
            SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
            AVG(p.Score)                         AS AvgScore,
            MAX(p.CreationDate)                AS LastPostDate
        FROM Users u
        LEFT JOIN Posts p
               ON p.OwnerUserId = u.Id
        GROUP BY u.Id
    ),

    UserBadgeAgg AS (
        SELECT 
            b.UserId,
            COUNT(*)                                           AS TotalBadges,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)       AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)       AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)       AS BronzeBadges,
            STRING_AGG(DISTINCT b.Name, ';')                  AS BadgeList
        FROM Badges b
        GROUP BY b.UserId
    ),

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

    UserRecentTags AS (
        SELECT 
            p.OwnerUserId                                    AS UserId,
            trim(both '<>' FROM token)                        AS Tag
        FROM Posts p,
        LATERAL (
            SELECT regexp_split_to_table(COALESCE(p.Tags, ''), '><') AS token
        ) s
        WHERE p.PostTypeId = 1
          AND p.CreationDate > (DATE '2024-10-01' - INTERVAL '30 days')
    ),

    UserTopTag AS (
        SELECT 
            urt.UserId,
            t.TagName,
            COUNT(*)                                          AS TagUsage,
            ROW_NUMBER() OVER (PARTITION BY urt.UserId 
                               ORDER BY COUNT(*) DESC, t.TagName)      AS rn
        FROM UserRecentTags urt
        JOIN Tags t ON t.TagName = urt.Tag
        GROUP BY urt.UserId, t.TagName
    ),

    TopTagPerUser AS (
        SELECT UserId, TagName AS Tag
        FROM UserTopTag
        WHERE rn = 1
    ),

    SelectedUsers AS (
        SELECT u.Id,
               u.DisplayName,
               COALESCE(upa.TotalPosts,0)                AS TotalPosts,
               COALESCE(upa.Questions,0)                 AS Questions,
               COALESCE(upa.Answers,0)                   AS Answers,
               COALESCE(upa.AvgScore,0)                  AS AvgScore,
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
                                  AND p2.CreationDate > (DATE '2024-10-01' - INTERVAL '90 days'))
                   THEN 1 ELSE 0 
               END                                      AS HasRecentNegativeScorePost,
               u.Reputation,
               u.Views,
               u.CreationDate
        FROM Users u
        LEFT JOIN UserPostAgg   upa ON upa.UserId = u.Id
        LEFT JOIN UserBadgeAgg  uba ON uba.UserId = u.Id
        LEFT JOIN UserVoteAgg   uvg ON uvg.UserId = u.Id
        LEFT JOIN TopTagPerUser tt  ON tt.UserId = u.Id
        WHERE u.CreationDate < (DATE '2024-10-01' - INTERVAL '1 year')
          AND (u.Reputation > 1000 OR u.Views > 5000)
    ),

    SelectedAndOrdered AS (
      SELECT Id,
             DisplayName,
             TotalPosts,
             Questions,
             Answers,
             ROUND(AvgScore::numeric,2)      AS AvgScore,
             LastPostDate,
             TotalBadges,
             GoldBadges,
             SilverBadges,
             BronzeBadges,
             BadgeList,
             UpVotesGiven,
             DownVotesGiven,
             LastVoteDate,
             TopRecentTag,
             HasRecentNegativeScorePost,
             Reputation
      FROM SelectedUsers
      ORDER BY TotalPosts DESC, Reputation DESC
      LIMIT 100
    )

SELECT Id,
       DisplayName,
       TotalPosts,
       Questions,
       Answers,
       ROUND(AvgScore,2)      AS AvgScore,
       LastPostDate,
       TotalBadges,
       GoldBadges,
       SilverBadges,
       BronzeBadges,
       BadgeList,
       UpVotesGiven,
       DownVotesGiven,
       LastVoteDate,
       TopRecentTag,
       HasRecentNegativeScorePost
FROM SelectedAndOrdered

UNION ALL

SELECT 
    -1                                            AS Id,
    'Aggregate Summary'                           AS DisplayName,
    SUM(TotalPosts)                AS TotalPosts,
    SUM(Questions)                 AS Questions,
    SUM(Answers)                   AS Answers,
    ROUND(AVG(AvgScore),2)         AS AvgScore,
    MAX(LastPostDate)              AS LastPostDate,
    SUM(TotalBadges)               AS TotalBadges,
    SUM(GoldBadges)                AS GoldBadges,
    SUM(SilverBadges)              AS SilverBadges,
    SUM(BronzeBadges)              AS BronzeBadges,
    NULL                           AS BadgeList,
    SUM(UpVotesGiven)              AS UpVotesGiven,
    SUM(DownVotesGiven)            AS DownVotesGiven,
    MAX(LastVoteDate)              AS LastVoteDate,
    NULL                           AS TopRecentTag,
    NULL                           AS HasRecentNegativeScorePost
FROM SelectedUsers;