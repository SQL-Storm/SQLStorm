-- {"query": "3415.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2450} 

WITH
    -- List of tags that are not moderator‑only
    TagList AS (
        SELECT t.Id   AS TagId,
               t.TagName,
               t.IsModeratorOnly
        FROM   Tags t
        WHERE  t.TagName IS NOT NULL
    ),

    -- All question posts that have a non‑null Tags column
    QuestionPosts AS (
        SELECT p.Id          AS QId,
               p.Tags,
               p.OwnerUserId,
               p.CreationDate
        FROM   Posts p
        WHERE  p.PostTypeId = 1               -- Question
          AND  p.Tags IS NOT NULL
    ),

    -- Explode the tag string into one row per tag (Postgres syntax)
    ExplodedTags AS (
        SELECT q.QId,
               q.OwnerUserId,
               q.CreationDate,
               regexp_split_to_table(trim(both '<>' FROM q.Tags), '><') AS TagName
        FROM   QuestionPosts q
    ),

    -- All answer posts
    Answers AS (
        SELECT a.Id         AS AId,
               a.ParentId  AS QId,
               a.OwnerUserId,
               a.Score,
               a.CreationDate
        FROM   Posts a
        WHERE  a.PostTypeId = 2               -- Answer
    ),

    -- Per‑user aggregate stats (badges, net votes, etc.)
    UserStats AS (
        SELECT u.Id                                 AS UserId,
               u.Reputation,
               COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
               (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
               (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
               (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
        FROM   Users u
    ),

    -- Aggregation of answers per (tag, user)
    TagAnswerStats AS (
        SELECT et.TagName,
               a.OwnerUserId,
               COUNT(*)                           AS AnswerCount,
               SUM(a.Score)                       AS TotalScore,
               AVG(a.Score)                       AS AvgScore,
               MAX(a.CreationDate)                AS LastAnswerDate
        FROM   ExplodedTags et
        JOIN   Answers a ON a.QId = et.QId
        GROUP  BY et.TagName, a.OwnerUserId
    ),

    -- Rank users within each tag by total score then answer count
    RankedTagAnswers AS (
        SELECT tas.*,
               ROW_NUMBER() OVER (PARTITION BY tas.TagName
                                  ORDER BY tas.TotalScore DESC,
                                           tas.AnswerCount DESC) AS RankInTag
        FROM   TagAnswerStats tas
    )

SELECT
    tl.TagName,
    rta.RankInTag,
    u.DisplayName,
    u.Id                                   AS UserId,
    rta.AnswerCount,
    rta.TotalScore,
    rta.AvgScore,
    us.Reputation,
    us.NetVotes,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    CASE
        WHEN EXISTS (SELECT 1
                     FROM   Votes v
                     WHERE  v.PostId = (SELECT a.Id
                                        FROM   Answers a
                                        WHERE  a.OwnerUserId = u.Id
                                        LIMIT 1)
                       AND  v.VoteTypeId = 2) THEN 'HasUpvote'
        ELSE 'NoUpvote'
    END                                     AS UpvoteFlag,
    COALESCE(rta.LastAnswerDate, TIMESTAMP '1970-01-01') AS LastAnswerDate
FROM   RankedTagAnswers rta
LEFT   JOIN Users u          ON u.Id = rta.OwnerUserId
LEFT   JOIN UserStats us    ON us.UserId = u.Id
LEFT   JOIN TagList tl      ON tl.TagName = rta.TagName
WHERE  rta.RankInTag <= 5                                 -- top‑5 per tag
  AND  (us.Reputation IS NOT NULL OR us.Reputation = 0)   -- keep users with zero reputation
  AND  (tl.IsModeratorOnly = 0 OR tl.IsModeratorOnly IS NULL)

UNION ALL

-- Overall top contributors (excluding those already in the top‑1 per tag)
SELECT
    'Overall'                               AS TagName,
    NULL                                    AS RankInTag,
    u.DisplayName,
    u.Id                                    AS UserId,
    NULL                                    AS AnswerCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS TotalScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgScore,
    us.Reputation,
    us.NetVotes,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    CASE
        WHEN EXISTS (SELECT 1
                     FROM   Votes v
                     WHERE  v.PostId = p.Id
                       AND  v.VoteTypeId = 2) THEN 'HasUpvote'
        ELSE 'NoUpvote'
    END                                     AS UpvoteFlag,
    MAX(p.CreationDate)                    AS LastAnswerDate
FROM   Users u
LEFT   JOIN UserStats us               ON us.UserId = u.Id
LEFT   JOIN Posts p                    ON p.OwnerUserId = u.Id
                                         AND p.PostTypeId = 2          -- answers only
WHERE  u.Id NOT IN (SELECT OwnerUserId
                    FROM   RankedTagAnswers
                    WHERE  RankInTag = 1)
GROUP  BY u.Id, u.DisplayName,
          us.Reputation, us.NetVotes,
          us.GoldBadges, us.SilverBadges, us.BronzeBadges
HAVING COUNT(p.Id) > 0                                          -- at least one answer
ORDER  BY TagName,
          RankInTag NULLS LAST,
          TotalScore DESC;
