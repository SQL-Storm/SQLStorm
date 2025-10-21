WITH RECURSIVE
    recent_posts AS (
        SELECT p.Id,
               p.PostTypeId,
               p.OwnerUserId,
               p.CreationDate,
               p.Score,
               p.ViewCount,
               p.AnswerCount,
               p.FavoriteCount,
               p.Tags,
               p.Title,
               p.ParentId
        FROM   Posts p
        WHERE  p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '12' MONTH
               AND p.OwnerUserId IS NOT NULL
    ),
    post_tags AS (
        SELECT rp.Id            AS PostId,
               UNNEST(string_to_array(trim(both '<>' FROM rp.Tags), '><')) AS Tag
        FROM   recent_posts rp
        WHERE  rp.Tags IS NOT NULL
    ),
    tag_popularity AS (
        SELECT pt.Tag,
               COUNT(DISTINCT pt.PostId) AS RecentPostCount,
               SUM(rp.Score)            AS TotalScore,
               SUM(rp.ViewCount)        AS TotalViews
        FROM   post_tags pt
               JOIN recent_posts rp ON rp.Id = pt.PostId
        GROUP  BY pt.Tag
    ),
    user_activity AS (
        SELECT rp.OwnerUserId                               AS UserId,
               COUNT(*)                                     AS PostCount,
               SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
               SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
               SUM(rp.Score)                                AS NetScore,
               SUM(rp.ViewCount)                            AS TotalViews,
               SUM(rp.FavoriteCount)                        AS Favorites,
               COALESCE(SUM(v.UpVotes),0)                   AS UpVoteSum,
               COALESCE(SUM(v.DownVotes),0)                 AS DownVoteSum
        FROM   recent_posts rp
               LEFT JOIN (
                   SELECT p.Id,
                          SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
                          SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
                   FROM   Posts p
                          JOIN Votes v ON v.PostId = p.Id
                   WHERE  v.VoteTypeId IN (2,3)
                          AND v.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '12' MONTH
                   GROUP  BY p.Id
               ) v ON v.Id = rp.Id
        GROUP  BY rp.OwnerUserId
    ),
    user_badges AS (
        SELECT b.UserId,
               SUM(CASE
                       WHEN b.Class = 1 THEN 100
                       WHEN b.Class = 2 THEN 30
                       WHEN b.Class = 3 THEN 10
                       ELSE 5
                   END) AS BadgeScore
        FROM   Badges b
        WHERE  b.Date >= CAST('2024-10-01' AS DATE) - INTERVAL '12' MONTH
        GROUP  BY b.UserId
    ),
    rep_growth AS (
        SELECT u.Id                                    AS UserId,
               u.Reputation                            AS CurrentRep,
               (SELECT COALESCE(SUM(v.BountyAmount),0)
                FROM   Votes v
                WHERE  v.UserId = u.Id
                       AND v.VoteTypeId = 8
                       AND v.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '12' MONTH) AS BountyEarned
        FROM   Users u
        WHERE  u.CreationDate <= CAST('2024-10-01' AS DATE) - INTERVAL '12' MONTH
    ),
    user_scores AS (
        SELECT ua.UserId,
               ua.PostCount,
               ua.QuestionCount,
               ua.AnswerCount,
               ua.NetScore,
               ua.TotalViews,
               ua.Favorites,
               ua.UpVoteSum,
               ua.DownVoteSum,
               COALESCE(ub.BadgeScore,0)     AS BadgeScore,
               rg.CurrentRep,
               rg.BountyEarned,
               (ua.NetScore * 1.5
                + ua.TotalViews * 0.01
                + ua.Favorites * 3
                + ua.UpVoteSum * 2
                - ua.DownVoteSum * 1
                + ub.BadgeScore * 0.5
                + rg.CurrentRep * 0.001
                + rg.BountyEarned * 5)      AS WeightedScore,
               ROW_NUMBER() OVER (ORDER BY
                     (ua.NetScore * 1.5
                      + ua.TotalViews * 0.01
                      + ua.Favorites * 3
                      + ua.UpVoteSum * 2
                      - ua.DownVoteSum * 1
                      + ub.BadgeScore * 0.5
                      + rg.CurrentRep * 0.001
                      + rg.BountyEarned * 5) DESC) AS Rank
        FROM   user_activity ua
               LEFT JOIN user_badges ub ON ub.UserId = ua.UserId
               LEFT JOIN rep_growth rg ON rg.UserId = ua.UserId
    )
SELECT us.Rank,
       u.Id                               AS UserId,
       u.DisplayName,
       us.PostCount,
       us.QuestionCount,
       us.AnswerCount,
       us.NetScore,
       us.TotalViews,
       us.Favorites,
       us.UpVoteSum,
       us.DownVoteSum,
       us.BadgeScore,
       us.CurrentRep,
       us.BountyEarned,
       ROUND(us.WeightedScore,2)          AS WeightedScore,
       (SELECT string_agg(t.TagName, ', ') 
        FROM   (
                 SELECT pt.Tag,
                        COUNT(*) AS Cnt
                 FROM   post_tags pt
                        JOIN recent_posts rp ON rp.Id = pt.PostId
                 WHERE  rp.OwnerUserId = u.Id
                 GROUP  BY pt.Tag
                 ORDER  BY Cnt DESC
                 LIMIT 5
               ) AS top_tags
               JOIN Tags t ON t.TagName = top_tags.Tag) AS TopTags,
       (SELECT COUNT(*)
        FROM   PostLinks pl
               JOIN Posts p ON p.Id = pl.PostId
        WHERE  pl.LinkTypeId = 3
               AND p.PostTypeId = 1
               AND p.OwnerUserId = u.Id) AS DuplicateCount,
       (SELECT ROUND(AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)))/3600,1)
        FROM   Posts q
               JOIN Posts a ON a.ParentId = q.Id
        WHERE  q.PostTypeId = 1
               AND q.OwnerUserId = u.Id
               AND a.PostTypeId = 2) AS AvgHoursToFirstAnswer
FROM   user_scores us
       JOIN Users u ON u.Id = us.UserId
WHERE  us.Rank <= 20
ORDER  BY us.Rank;