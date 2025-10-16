WITH
    UserPostAgg AS (
        SELECT
            u.Id                                   AS UserId,
            u.DisplayName,
            u.Reputation,
            COUNT(p.Id)                            AS TotalPosts,
            SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
            SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
            AVG(p.Score)                             AS AvgScore,
            MAX(p.CreationDate)                     AS LastPostDate
        FROM Users u
        LEFT JOIN Posts p
               ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    UserBadgeAgg AS (
        SELECT
            b.UserId,
            COUNT(*)                                           AS TotalBadges,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)       AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)       AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)       AS BronzeBadges,
            -- portable aggregation of distinct names into a comma-separated list
            (SELECT STRING_AGG(x.Name, ', ')
             FROM (
               SELECT DISTINCT b2.Name
               FROM Badges b2
               WHERE b2.UserId = b.UserId
             ) x
            )                                               AS BadgeList
        FROM Badges b
        GROUP BY b.UserId
    ),

    UserVoteAgg AS (
        SELECT
            v.UserId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END)        AS UpVotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END)        AS DownVotes,
            SUM(CASE WHEN vt.Id = 5 THEN 1 ELSE 0 END)        AS Favorites,
            SUM(CASE
                    WHEN vt.Id = 2 THEN 1
                    WHEN vt.Id = 3 THEN -1
                    ELSE 0
                END)                                          AS VoteScore
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.UserId
    ),

    RecentClosedQuestions AS (
        SELECT
            p.Id,
            p.Title,
            -- turn '<c#><sql>' into 'c#, sql' in a portable way
            REPLACE(REPLACE(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><', ', '), '>', '') AS TagList,
            ph.CreationDate                              AS ClosedDate,
            COALESCE(NULLIF(ph.Comment, ''), 'No reason') AS CloseReason,
            p.OwnerUserId,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                               ORDER BY ph.CreationDate DESC) AS rn
        FROM Posts p
        JOIN PostHistory ph
              ON ph.PostId = p.Id
        WHERE p.PostTypeId = 1
          AND ph.PostHistoryTypeId = 10
    ),

    TopUsers AS (
        SELECT UserId, DisplayName, Reputation, TotalPosts, Questions, Answers, AvgScore, LastPostDate
        FROM UserPostAgg
        ORDER BY Reputation DESC
        LIMIT 10
    )

SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.Questions,
    tu.Answers,
    ROUND(CAST(tu.AvgScore AS NUMERIC), 2)                AS AvgScore,
    tu.LastPostDate,
    COALESCE(uba.TotalBadges, 0)                  AS TotalBadges,
    COALESCE(uba.GoldBadges, 0)                   AS GoldBadges,
    COALESCE(uba.SilverBadges, 0)                 AS SilverBadges,
    COALESCE(uba.BronzeBadges, 0)                 AS BronzeBadges,
    uba.BadgeList,
    COALESCE(uva.UpVotes, 0)                      AS UpVotes,
    COALESCE(uva.DownVotes, 0)                    AS DownVotes,
    COALESCE(uva.Favorites, 0)                    AS Favorites,
    COALESCE(uva.VoteScore, 0)                    AS VoteScore,
    CASE
        WHEN tu.Reputation > 20000 THEN 'Elite'
        WHEN tu.Reputation > 10000 THEN 'Pro'
        ELSE 'Member'
    END                                           AS Tier,
    rcq.Title                                      AS RecentClosedQuestion,
    rcq.TagList,
    rcq.CloseReason,
    rcq.ClosedDate
FROM TopUsers tu
LEFT JOIN UserBadgeAgg uba
       ON uba.UserId = tu.UserId
LEFT JOIN UserVoteAgg uva
       ON uva.UserId = tu.UserId
LEFT JOIN (
    SELECT Id, Title, TagList, CloseReason, ClosedDate, OwnerUserId
    FROM RecentClosedQuestions
    WHERE rn = 1
) rcq
       ON rcq.OwnerUserId = tu.UserId
WHERE tu.Reputation IS NOT NULL

UNION ALL
SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL
WHERE FALSE;