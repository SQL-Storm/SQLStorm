-- {"query": "54090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1785} 

WITH tag_posts AS (
    SELECT p.Id          AS PostId,
           unnest(string_to_array(substring(p.Tags, 2, char_length(p.Tags)-2), '><')) AS TagName,
           p.OwnerUserId,
           p.Score,
           p.CreationDate
    FROM   Posts p
    WHERE  p.PostTypeId = 1               /* questions only */
      AND  p.Tags IS NOT NULL
),
post_votes AS (
    SELECT PostId,
           COUNT(*) AS VoteCount
    FROM   Votes
    GROUP  BY PostId
),
tag_stats AS (
    SELECT tp.TagName,
           COUNT(*)                                       AS PostCount,
           AVG(COALESCE(tp.Score,0))                      AS AvgScore,
           SUM(COALESCE(pv.VoteCount,0))                  AS TotalVotes
    FROM   tag_posts tp
    LEFT   JOIN post_votes pv ON pv.PostId = tp.PostId
    GROUP  BY tp.TagName
),
tag_edits AS (
    SELECT tp.TagName,
           COUNT(DISTINCT ph.Id)                                                       AS EditCount,
           COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END)           AS ClosedCount
    FROM   tag_posts tp
           JOIN PostHistory ph ON ph.PostId = tp.PostId
    WHERE  ph.PostHistoryTypeId IN (4,5,6,10)   /* edit & close types */
    GROUP  BY tp.TagName
),
tag_user_rank AS (
    SELECT tp.TagName,
           u.Id                AS UserId,
           u.Reputation,
           COUNT(tp.PostId)                             AS UserPostCount,
           COALESCE(SUM(pv.VoteCount),0)                AS UserVoteTotal,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           ROW_NUMBER() OVER (PARTITION BY tp.TagName ORDER BY COUNT(tp.PostId) DESC, u.Reputation DESC) AS UserRank
    FROM   tag_posts tp
           JOIN Users u ON u.Id = tp.OwnerUserId
           LEFT JOIN post_votes pv ON pv.PostId = tp.PostId
           LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP  BY tp.TagName, u.Id, u.Reputation
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
FROM   tag_stats ts
       JOIN tag_edits te ON te.TagName = ts.TagName
       LEFT JOIN tag_user_rank tur ON tur.TagName = ts.TagName AND tur.UserRank <= 3
       LEFT JOIN Users u ON u.Id = tur.UserId
ORDER  BY ts.TagName, tur.UserRank;
