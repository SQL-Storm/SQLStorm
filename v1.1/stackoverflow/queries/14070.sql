WITH cte1 AS (
    SELECT 
        p.Id AS PostId, 
        p.OwnerUserId,
        p.Score,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS PostStatus,
        CAST(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate)) / 86400 AS integer) AS DaysSinceCreation,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS ScoreRank
    FROM Posts p
),
cte2 AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        CAST(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.CreationDate)) / 86400 AS integer) AS DaysSinceCreation,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.CreationDate
),
cte3 AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate,
        p.Body,
        p.Tags,
        CAST(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate)) / 86400 AS integer) AS DaysSinceCreation,
        COALESCE(
          -- emulate SUBSTRING_INDEX(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '><', 1)
          NULLIF(SPLIT_PART(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '><', 1), ''),
          ''
        ) AS MainTag,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        COALESCE(
          CAST(EXTRACT(EPOCH FROM (p.ClosedDate - p.CreationDate)) / 86400 AS integer),
          0
        ) AS DaysToClose
    FROM Posts p
)
SELECT 
    c1.PostId,
    c1.OwnerUserId,
    c1.Score,
    c1.AnswerCount,
    c1.CommentCount,
    c1.FavoriteCount,
    c1.PostStatus,
    c1.DaysSinceCreation,
    c1.ScoreRank,
    c2.UserId,
    c2.Reputation,
    c2.UpVotes,
    c2.DownVotes,
    c2.Views,
    c2.DaysSinceCreation AS UserDaysSinceCreation,
    c2.GoldBadges,
    c2.SilverBadges,
    c2.BronzeBadges,
    c3.PostTypeId,
    c3.AcceptedAnswerId,
    c3.ParentId,
    c3.CreationDate AS PostCreationDate,
    c3.Body,
    c3.Tags,
    c3.DaysSinceCreation AS PostDaysSinceCreation,
    c3.MainTag,
    c3.PostType,
    c3.DaysToClose
FROM cte1 c1
JOIN cte2 c2 ON c1.OwnerUserId = c2.UserId
JOIN cte3 c3 ON c1.PostId = c3.PostId
WHERE c1.DaysSinceCreation BETWEEN 30 AND 365
ORDER BY c1.ScoreRank
LIMIT 1000;