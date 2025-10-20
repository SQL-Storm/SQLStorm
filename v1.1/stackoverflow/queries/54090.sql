WITH tag_posts AS (
    SELECT
        p.Id AS PostId,
        -- split tags like "<tag1><tag2>" into rows: remove leading/trailing '<' and '>', then split on '><'
        TRIM(tag) AS TagName,
        p.OwnerUserId,
        p.Score,
        p.CreationDate
    FROM Posts p,
    LATERAL (
        SELECT value AS tag
        FROM (SELECT regexp_split_to_table(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '><') AS value) AS s
    ) AS split_tags
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
post_votes AS (
    SELECT PostId,
           COUNT(*) AS VoteCount
    FROM Votes
    GROUP BY PostId
),
tag_stats AS (
    SELECT tp.TagName,
           COUNT(*) AS PostCount,
           AVG(COALESCE(tp.Score, 0)) AS AvgScore,
           SUM(COALESCE(pv.VoteCount, 0)) AS TotalVotes
    FROM tag_posts tp
    LEFT JOIN post_votes pv ON pv.PostId = tp.PostId
    GROUP BY tp.TagName
),
tag_edits AS (
    SELECT tp.TagName,
           COUNT(DISTINCT ph.Id) AS EditCount,
           COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS ClosedCount
    FROM tag_posts tp
    JOIN PostHistory ph ON ph.PostId = tp.PostId
    WHERE ph.PostHistoryTypeId IN (4,5,6,10)
    GROUP BY tp.TagName
),
tag_user_rank AS (
    SELECT tp.TagName,
           u.Id AS UserId,
           u.Reputation,
           COUNT(tp.PostId) AS UserPostCount,
           COALESCE(SUM(pv.VoteCount), 0) AS UserVoteTotal,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           ROW_NUMBER() OVER (PARTITION BY tp.TagName ORDER BY COUNT(tp.PostId) DESC, u.Reputation DESC) AS UserRank
    FROM tag_posts tp
    JOIN Users u ON u.Id = tp.OwnerUserId
    LEFT JOIN post_votes pv ON pv.PostId = tp.PostId
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY tp.TagName, u.Id, u.Reputation
)
SELECT ts.TagName,
       ts.PostCount,
       ts.AvgScore,
       ts.TotalVotes,
       te.EditCount,
       te.ClosedCount,
       tur.UserId,
       u.DisplayName,
       tur.UserPostCount,
       tur.UserVoteTotal,
       tur.GoldBadges,
       tur.SilverBadges,
       tur.BronzeBadges
FROM tag_stats ts
JOIN tag_edits te ON te.TagName = ts.TagName
LEFT JOIN tag_user_rank tur ON tur.TagName = ts.TagName AND tur.UserRank <= 3
LEFT JOIN Users u ON u.Id = tur.UserId
ORDER BY ts.TagName, tur.UserRank;