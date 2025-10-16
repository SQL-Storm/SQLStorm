WITH
  AllPosts AS (
    SELECT Id, Title, PostTypeId, Tags, ViewCount,
           Score, CreationDate, LastActivityDate, OwnerUserId
    FROM Posts
    WHERE PostTypeId IN (1,4)
  ),
  QuestionPosts AS (
    SELECT * FROM AllPosts WHERE PostTypeId = 1
  ),
  TagWikiPosts AS (
    SELECT * FROM AllPosts WHERE PostTypeId = 4
  ),
  TagPostCounts AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT qp.Id)      AS QuestionCnt,
      SUM(qp.Score)              AS TotalScore,
      MIN(qp.CreationDate)       AS FirstQuestion,
      MAX(qp.CreationDate)       AS LastQuestion
    FROM Tags t
    JOIN QuestionPosts qp
      ON (',' || qp.Tags || ',') LIKE '%,' || t.TagName || ',%'
    GROUP BY t.TagName
  ),
  BadgeAgg AS (
    SELECT
      t.TagName,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Tags t
    LEFT JOIN Badges b
      ON b.TagBased = TRUE AND b.Name = t.TagName
    GROUP BY t.TagName
  ),
  UserStats AS (
    SELECT
      u.Id                AS UserId,
      u.Reputation,
      (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVotesCount,
      (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS DownVotesCount
    FROM Users u
  ),
  PostVoteStats AS (
    SELECT
      pv.Id          AS PostId,
      COUNT(v.Id)    AS TotalVotes,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM PostHistory pv
    JOIN Votes v ON v.PostId = pv.PostId
    WHERE pv.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY)
    GROUP BY pv.Id
  ),
  RankedTopPosts AS (
    SELECT
      qp.Id,
      qp.Title,
      qp.Score,
      qp.ViewCount,
      qp.OwnerUserId,
      u.Reputation AS OwnerRep,
      t.TagName,
      ROW_NUMBER() OVER (PARTITION BY t.TagName
                         ORDER BY qp.Score DESC,
                                  qp.LastActivityDate DESC) AS RankPos
    FROM QuestionPosts qp
    JOIN Tags t
      ON (',' || qp.Tags || ',') LIKE '%,' || t.TagName || ',%'
    LEFT JOIN UserStats u ON u.UserId = qp.OwnerUserId
    WHERE qp.Score IS NOT NULL
  ),
  Final AS (
    SELECT
      tp.TagName,
      tp.QuestionCnt,
      tp.TotalScore,
      ba.GoldBadges,
      ba.SilverBadges,
      ba.BronzeBadges,
      rp.Title,
      rp.Score,
      rp.ViewCount,
      rp.OwnerRep,
      vps.TotalVotes,
      vps.UpVotes,
      vps.DownVotes
    FROM TagPostCounts tp
    LEFT JOIN BadgeAgg ba ON ba.TagName = tp.TagName
    LEFT JOIN RankedTopPosts rp ON rp.TagName = tp.TagName AND rp.RankPos = 1
    LEFT JOIN PostVoteStats vps ON vps.PostId = rp.Id
    ORDER BY tp.QuestionCnt DESC
    LIMIT 20
  )
SELECT * FROM Final;