-- {"query": "25089.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2992} 

WITH 
/* ------------------------------------------------------------------
   Users that have at least one post OR at least one badge.
   Demonstrates a UNION set operator.
------------------------------------------------------------------- */
ActiveUsers AS (
    SELECT DISTINCT OwnerUserId AS UserId
    FROM   Posts
    WHERE  OwnerUserId IS NOT NULL
    UNION
    SELECT DISTINCT UserId
    FROM   Badges
),

/* ------------------------------------------------------------------
   Aggregate post statistics per user (outer join keeps users with
   zero posts).
------------------------------------------------------------------- */
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

/* ------------------------------------------------------------------
   Badge counts per class.
------------------------------------------------------------------- */
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

/* ------------------------------------------------------------------
   Votes received on a user's posts.
------------------------------------------------------------------- */
UserVoteStats AS (
    SELECT u.Id                                          AS UserId,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 END),0) AS UpVotesReceived,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 END),0) AS DownVotesReceived,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 END),0) AS FavoritesReceived
    FROM   Users u
    LEFT JOIN Posts p
           ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v
           ON v.PostId = p.Id
    GROUP BY u.Id
),

/* ------------------------------------------------------------------
   Top three tags used by the user (comma‑separated string).
------------------------------------------------------------------- */
UserTopTags AS (
    SELECT u.Id                                          AS UserId,
           STRING_AGG(t.TagName, ', ' ORDER BY cnt DESC) AS TopTags
    FROM   Users u
    JOIN   Posts p
           ON p.OwnerUserId = u.Id
    /* split the <tag><tag> list into rows */
    JOIN   LATERAL (
              SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS Tag
           ) pt
           ON TRUE
    JOIN   Tags t
           ON t.TagName = pt.Tag
    GROUP BY u.Id
    HAVING COUNT(*) > 0
),

/* ------------------------------------------------------------------
   Most recent PostHistory entry per user (correlated sub‑query).
------------------------------------------------------------------- */
UserRecentHistory AS (
    SELECT u.Id                                          AS UserId,
           (SELECT MAX(ph.CreationDate)
            FROM   PostHistory ph
            WHERE  ph.UserId = u.Id)                      AS LastHistoryDate
    FROM   Users u
),

/* ------------------------------------------------------------------
   Combine all per‑user metrics.
------------------------------------------------------------------- */
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
               COALESCE(ups.LastPostDate, TIMESTAMP '1970-01-01'),
               COALESCE(urh.LastHistoryDate, TIMESTAMP '1970-01-01')
           )                               AS LastActivity
    FROM   Users u
    LEFT JOIN UserPostStats      ups   ON ups.UserId = u.Id
    LEFT JOIN UserBadgeStats     ubs   ON ubs.UserId = u.Id
    LEFT JOIN UserVoteStats      uvs   ON uvs.UserId = u.Id
    LEFT JOIN UserTopTags        ut    ON ut.UserId = u.Id
    LEFT JOIN UserRecentHistory  urh   ON urh.UserId = u.Id
),

/* ------------------------------------------------------------------
   Ranking by a composite engagement score.
------------------------------------------------------------------- */
Ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY
               (Reputation * 0.5) +
               (TotalPosts * 2) +
               (GoldBadges * 10) +
               (SilverBadges * 5) +
               (BronzeBadges * 2) +
               (UpVotesReceived - DownVotesReceived) +
               (FavoritesReceived * 3) DESC)                AS EngagementRank,
           PERCENT_RANK() OVER (ORDER BY
               (Reputation * 0.5) +
               (TotalPosts * 2) +
               (GoldBadges * 10) +
               (SilverBadges * 5) +
               (BronzeBadges * 2) +
               (UpVotesReceived - DownVotesReceived) +
               (FavoritesReceived * 3))                      AS EngagementPct
    FROM   Combined
    WHERE  UserId IN (SELECT UserId FROM ActiveUsers)   -- use the UNION result
)

SELECT Id,
       COALESCE(DisplayName, 'Anonymous')          AS DisplayName,
       Reputation,
       TotalPosts,
       Questions,
       Answers,
       ROUND(AvgPostScore,2)                       AS AvgPostScore,
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
       ROUND(EngagementPct*100,1)                  AS EngagementPercentile
FROM   Ranked
WHERE  EngagementRank <= 100
ORDER BY EngagementRank;
