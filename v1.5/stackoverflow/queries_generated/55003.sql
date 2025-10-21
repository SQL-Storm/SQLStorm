-- {"query": "55003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1792} 

WITH RECURSIVE
    -- All posts created in the last 12 months
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
        WHERE  p.CreationDate >= CURRENT_DATE - INTERVAL '12 months'
               AND p.OwnerUserId IS NOT NULL
    ),
    -- Explode the tag list into one row per tag
    post_tags AS (
        SELECT rp.Id            AS PostId,
               UNNEST(string_to_array(trim(both '<>' FROM rp.Tags), '><')) AS Tag
        FROM   recent_posts rp
        WHERE  rp.Tags IS NOT NULL
    ),
    -- Count how many recent posts each tag appears in
    tag_popularity AS (
        SELECT pt.Tag,
               COUNT(DISTINCT pt.PostId) AS RecentPostCount,
               SUM(rp.Score)            AS TotalScore,
               SUM(rp.ViewCount)        AS TotalViews
        FROM   post_tags pt
               JOIN recent_posts rp ON rp.Id = pt.PostId
        GROUP  BY pt.Tag
    ),
    -- Aggregate user activity on recent posts
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
                          AND v.CreationDate >= CURRENT_DATE - INTERVAL '12 months'
                   GROUP  BY p.Id
               ) v ON v.Id = rp.Id
        GROUP  BY rp.OwnerUserId
    ),
    -- Badge weighting per user
    user_badges AS (
        SELECT b.UserId,
               SUM(CASE
                       WHEN b.Class = 1 THEN 100   -- Gold
                       WHEN b.Class = 2 THEN 30    -- Silver
                       WHEN b.Class = 3 THEN 10    -- Bronze
                       ELSE 5
                   END) AS BadgeScore
        FROM   Badges b
        WHERE  b.Date >= CURRENT_DATE - INTERVAL '12 months'
        GROUP  BY b.UserId
    ),
    -- Reputation growth in the last year
    rep_growth AS (
        SELECT u.Id                                    AS UserId,
               u.Reputation                            AS CurrentRep,
               (SELECT COALESCE(SUM(v.BountyAmount),0)
                FROM   Votes v
                WHERE  v.UserId = u.Id
                       AND v.VoteTypeId = 8
                       AND v.CreationDate >= CURRENT_DATE - INTERVAL '12 months') AS BountyEarned
        FROM   Users u
        WHERE  u.CreationDate <= CURRENT_DATE - INTERVAL '12 months'   -- exclude brand‑new accounts
    ),
    -- Join everything together
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
               -- Composite weighted score for benchmarking
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
       -- Top 5 tags the user has contributed to (by recent post count)
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
       -- Number of duplicate relations the user’s questions have (as sources)
       (SELECT COUNT(*)
        FROM   PostLinks pl
               JOIN Posts p ON p.Id = pl.PostId
        WHERE  pl.LinkTypeId = 3                     -- duplicate
               AND p.PostTypeId = 1                  -- question
               AND p.OwnerUserId = u.Id) AS DuplicateCount,
       -- Average time to first answer (in hours) for the user’s questions
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
