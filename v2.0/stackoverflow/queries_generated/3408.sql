-- {"query": "3408.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3077} 

WITH UserStats AS (
    SELECT u.Id                       AS UserId,
           u.DisplayName,
           COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score END),0)   AS QuestionScore,
           COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score END),0)   AS AnswerScore,
           COALESCE(AVG(p.ViewCount) FILTER (WHERE p.PostTypeId = 1),0)    AS AvgQuestionViews,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1)           AS QuestionCount,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2)           AS AnswerCount,
           MAX(p.CreationDate)                                         AS LastPostDate
    FROM   Users u
    LEFT   JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP  BY u.Id, u.DisplayName
),

BadgeStats AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)                AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)                AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)                AS BronzeBadges,
           COUNT(*)                                                    AS TotalBadges,
           STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadgeNames
    FROM   Badges b
    GROUP  BY b.UserId
),

TagUsage AS (
    SELECT p.OwnerUserId                                      AS UserId,
           t.TagName,
           COUNT(*)                                            AS TagCount,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                              ORDER BY COUNT(*) DESC)        AS rn
    FROM   Posts p
    JOIN   LATERAL (SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS Tag) AS tags_raw ON TRUE
    JOIN   Tags t ON t.TagName = tags_raw.Tag
    WHERE  p.PostTypeId = 1
      AND  p.Tags IS NOT NULL
    GROUP  BY p.OwnerUserId, t.TagName
),

RecentVotes AS (
    SELECT v.UserId,
           COUNT(*) FILTER (WHERE vt.Name = 'UpMod')   AS UpVotesGiven,
           COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotesGiven,
           MAX(v.CreationDate)                         AS LastVoteDate
    FROM   Votes v
    JOIN   VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE  v.UserId IS NOT NULL
    GROUP  BY v.UserId
),

CommentStats AS (
    SELECT c.UserId,
           COUNT(*)                     AS CommentCount,
           MAX(c.CreationDate)          AS LastCommentDate
    FROM   Comments c
    WHERE  c.UserId IS NOT NULL
    GROUP  BY c.UserId
)

SELECT us.UserId,
       us.DisplayName,
       us.QuestionScore,
       us.AnswerScore,
       us.AvgQuestionViews,
       us.QuestionCount,
       us.AnswerCount,
       COALESCE(bs.GoldBadges,0)                     AS GoldBadges,
       COALESCE(bs.SilverBadges,0)                   AS SilverBadges,
       COALESCE(bs.BronzeBadges,0)                   AS BronzeBadges,
       COALESCE(bs.TotalBadges,0)                    AS TotalBadges,
       bs.GoldBadgeNames,
       rv.UpVotesGiven,
       rv.DownVotesGiven,
       rv.LastVoteDate,
       cs.CommentCount,
       cs.LastCommentDate,
       tu.TagName                                    AS TopTag,
       tu.TagCount                                   AS TopTagCount,
       CASE
           WHEN us.AnswerScore > us.QuestionScore * 2 THEN 'AnswerHeavy'
           WHEN us.QuestionScore > us.AnswerScore * 2 THEN 'QuestionHeavy'
           ELSE 'Balanced'
       END                                          AS ActivityProfile,
       CASE
           WHEN us.LastPostDate IS NULL THEN NULL
           ELSE DATE_PART('day', CURRENT_TIMESTAMP - us.LastPostDate)
       END                                          AS DaysSinceLastPost,
       COALESCE((
           SELECT COUNT(*)
           FROM   PostLinks pl
           WHERE  pl.PostId = (SELECT Id FROM Posts WHERE OwnerUserId = us.UserId LIMIT 1)
             AND  pl.LinkTypeId = 3
       ),0)                                          AS DuplicateLinksCount
FROM   UserStats us
LEFT   JOIN BadgeStats   bs ON bs.UserId = us.UserId
LEFT   JOIN RecentVotes  rv ON rv.UserId = us.UserId
LEFT   JOIN CommentStats cs ON cs.UserId = us.UserId
LEFT   JOIN (
           SELECT UserId, TagName, TagCount
           FROM   TagUsage
           WHERE  rn = 1
       ) tu ON tu.UserId = us.UserId
WHERE  us.QuestionCount + us.AnswerCount > 0
  AND (bs.TotalBadges IS NULL OR bs.TotalBadges >= 5)
ORDER  BY us.AnswerScore DESC NULLS LAST
LIMIT  100

UNION ALL

SELECT NULL                                                AS UserId,
       'AggregatedTotals'                                  AS DisplayName,
       SUM(us.QuestionScore)                               AS QuestionScore,
       SUM(us.AnswerScore)                                 AS AnswerScore,
       AVG(us.AvgQuestionViews)                            AS AvgQuestionViews,
       SUM(us.QuestionCount)                               AS QuestionCount,
       SUM(us.AnswerCount)                                 AS AnswerCount,
       SUM(COALESCE(bs.GoldBadges,0))                      AS GoldBadges,
       SUM(COALESCE(bs.SilverBadges,0))                    AS SilverBadges,
       SUM(COALESCE(bs.BronzeBadges,0))                    AS BronzeBadges,
       SUM(COALESCE(bs.TotalBadges,0))                     AS TotalBadges,
       NULL                                                AS GoldBadgeNames,
       SUM(COALESCE(rv.UpVotesGiven,0))                    AS UpVotesGiven,
       SUM(COALESCE(rv.DownVotesGiven,0))                  AS DownVotesGiven,
       MAX(rv.LastVoteDate)                                AS LastVoteDate,
       SUM(COALESCE(cs.CommentCount,0))                    AS CommentCount,
       MAX(cs.LastCommentDate)                             AS LastCommentDate,
       NULL                                                AS TopTag,
       NULL                                                AS TopTagCount,
       NULL                                                AS ActivityProfile,
       NULL                                                AS DaysSinceLastPost,
       SUM(COALESCE((
           SELECT COUNT(*)
           FROM   PostLinks pl
           WHERE  pl.PostId = (SELECT Id FROM Posts WHERE OwnerUserId = us.UserId LIMIT 1)
             AND  pl.LinkTypeId = 3
       ),0))                                                AS DuplicateLinksCount
FROM   UserStats us
LEFT   JOIN BadgeStats   bs ON bs.UserId = us.UserId
LEFT   JOIN RecentVotes  rv ON rv.UserId = us.UserId
LEFT   JOIN CommentStats cs ON cs.UserId = us.UserId;
