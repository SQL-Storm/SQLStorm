WITH 
ActiveUsers AS (
    SELECT DISTINCT OwnerUserId AS UserId
    FROM   Posts
    WHERE  OwnerUserId IS NOT NULL
    UNION
    SELECT DISTINCT UserId
    FROM   Badges
),
UserPostStats AS (
    SELECT u.Id                                          AS UserId,
           COUNT(p.Id)                                   AS TotalPosts,
           SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
           SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
           AVG(p.Score)                                  AS AvgPostScore,
           MAX(p.CreationDate)                           AS LastPostDate
    FROM   Users u
    LEFT JOIN Posts p
           ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
UserBadgeStats AS (
    SELECT u.Id                                          AS UserId,
           COUNT(b.Id)                                   AS TotalBadges,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM   Users u
    LEFT JOIN Badges b
           ON b.UserId = u.Id
    GROUP BY u.Id
),
UserVoteStats AS (
    SELECT u.Id                                          AS UserId,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVotesReceived,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVotesReceived,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END),0) AS FavoritesReceived
    FROM   Users u
    LEFT JOIN Posts p
           ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v
           ON v.PostId = p.Id
    GROUP BY u.Id
),
UserTopTags AS (
    SELECT u.Id                                          AS UserId,
           STRING_AGG(t.TagName, ', ' ORDER BY tag_counts.cnt DESC) AS TopTags
    FROM   Users u
    JOIN   Posts p
           ON p.OwnerUserId = u.Id
    JOIN   LATERAL (
              SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS Tag
           ) pt
           ON TRUE
    JOIN   Tags t
           ON t.TagName = pt.Tag
    JOIN (
           SELECT p2.OwnerUserId AS OwnerUserId, pt2.Tag AS Tag, COUNT(*) AS cnt
           FROM Posts p2
           JOIN LATERAL (
              SELECT unnest(string_to_array(trim(both '<>' FROM p2.Tags), '><')) AS Tag
           ) pt2 ON TRUE
           GROUP BY p2.OwnerUserId, pt2.Tag
         ) tag_counts
         ON tag_counts.OwnerUserId = p.OwnerUserId AND tag_counts.Tag = pt.Tag
    GROUP BY u.Id
    HAVING COUNT(*) > 0
),
UserRecentHistory AS (
    SELECT u.Id                                          AS UserId,
           (SELECT MAX(ph.CreationDate)
            FROM   PostHistory ph
            WHERE  ph.UserId = u.Id)                      AS LastHistoryDate
    FROM   Users u
),
Combined AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(ups.TotalPosts,0)      AS TotalPosts,
           COALESCE(ups.Questions,0)       AS Questions,
           COALESCE(ups.Answers,0)         AS Answers,
           COALESCE(ups.AvgPostScore,0)    AS AvgPostScore,
           COALESCE(ubs.TotalBadges,0)     AS TotalBadges,
           COALESCE(ubs.GoldBadges,0)      AS GoldBadges,
           COALESCE(ubs.SilverBadges,0)    AS SilverBadges,
           COALESCE(ubs.BronzeBadges,0)    AS BronzeBadges,
           COALESCE(uvs.UpVotesReceived,0) AS UpVotesReceived,
           COALESCE(uvs.DownVotesReceived,0) AS DownVotesReceived,
           COALESCE(uvs.FavoritesReceived,0) AS FavoritesReceived,
           COALESCE(ut.TopTags,'')         AS TopTags,
           GREATEST(
               COALESCE(ups.LastPostDate, CAST('1970-01-01' AS TIMESTAMP)),
               COALESCE(urh.LastHistoryDate, CAST('1970-01-01' AS TIMESTAMP))
           )                               AS LastActivity
    FROM   Users u
    LEFT JOIN UserPostStats      ups   ON ups.UserId = u.Id
    LEFT JOIN UserBadgeStats     ubs   ON ubs.UserId = u.Id
    LEFT JOIN UserVoteStats      uvs   ON uvs.UserId = u.Id
    LEFT JOIN UserTopTags        ut    ON ut.UserId = u.Id
    LEFT JOIN UserRecentHistory  urh   ON urh.UserId = u.Id
),
Ranked AS (
    SELECT Id,
           DisplayName,
           Reputation,
           TotalPosts,
           Questions,
           Answers,
           AvgPostScore,
           TotalBadges,
           GoldBadges,
           SilverBadges,
           BronzeBadges,
           UpVotesReceived,
           DownVotesReceived,
           FavoritesReceived,
           TopTags,
           LastActivity,
           ROW_NUMBER() OVER (ORDER BY
               ((Reputation * 0.5) +
               (TotalPosts * 2) +
               (GoldBadges * 10) +
               (SilverBadges * 5) +
               (BronzeBadges * 2) +
               (UpVotesReceived - DownVotesReceived) +
               (FavoritesReceived * 3)) DESC)                AS EngagementRank,
           PERCENT_RANK() OVER (ORDER BY
               ((Reputation * 0.5) +
               (TotalPosts * 2) +
               (GoldBadges * 10) +
               (SilverBadges * 5) +
               (BronzeBadges * 2) +
               (UpVotesReceived - DownVotesReceived) +
               (FavoritesReceived * 3)))                      AS EngagementPct
    FROM   Combined
    WHERE  Id IN (SELECT UserId FROM ActiveUsers)
)

SELECT Id,
       COALESCE(DisplayName, 'Anonymous')          AS DisplayName,
       Reputation,
       TotalPosts,
       Questions,
       Answers,
       ROUND(CAST(AvgPostScore AS NUMERIC),2)                       AS AvgPostScore,
       TotalBadges,
       GoldBadges,
       SilverBadges,
       BronzeBadges,
       UpVotesReceived,
       DownVotesReceived,
       FavoritesReceived,
       TopTags,
       LastActivity,
       EngagementRank,
       ROUND(CAST((EngagementPct*100) AS NUMERIC),1)                  AS EngagementPercentile
FROM   Ranked
WHERE  EngagementRank <= 100
ORDER BY EngagementRank;