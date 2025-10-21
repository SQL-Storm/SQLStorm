-- {"query": "55005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1801} 

WITH
    top_users AS (
        SELECT u.Id,
               u.DisplayName,
               u.Reputation,
               ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
        FROM   Users u
        WHERE  u.Reputation > 1000
    ),
    recent_posts AS (
        SELECT p.Id,
               p.PostTypeId,
               p.OwnerUserId,
               p.CreationDate,
               p.Score,
               p.Title,
               p.Tags,
               ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_user
        FROM   Posts p
        WHERE  p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
               AND p.PostTypeId = 1  -- questions only
    ),
    post_votes AS (
        SELECT v.PostId,
               SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END)          AS up_votes,
               SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END)          AS down_votes,
               COUNT(*) FILTER (WHERE vt.Id = 5)                  AS favorite_cnt
        FROM   Votes v
        JOIN   VoteTypes vt ON v.VoteTypeId = vt.Id
        GROUP BY v.PostId
    ),
    tag_usage AS (
        SELECT t.TagName,
               COUNT(p.Id)               AS post_cnt,
               SUM(p.Score)              AS total_score,
               AVG(p.Score)              AS avg_score
        FROM   Posts p
        JOIN   LATERAL (
                 SELECT unnest(string_to_array(trim(both '><' FROM p.Tags), '><')) AS tag
               ) AS tname ON true
        JOIN   Tags t ON t.TagName = tname.tag
        WHERE  p.PostTypeId = 1
        GROUP BY t.TagName
    ),
    post_links AS (
        SELECT pl.PostId,
               pl.RelatedPostId,
               lt.Name        AS link_type,
               pl.CreationDate
        FROM   PostLinks pl
        JOIN   LinkTypes lt ON pl.LinkTypeId = lt.Id
    )
SELECT
    tu.Id                                   AS UserId,
    tu.DisplayName,
    tu.Reputation,
    rp.Id                                   AS PostId,
    rp.Title,
    rp.Score,
    pv.up_votes,
    pv.down_votes,
    pv.favorite_cnt,
    tl.link_type,
    tl.RelatedPostId,
    ru.DisplayName                         AS RelatedUser,
    ru.Reputation                          AS RelatedUserReputation,
    ru_stats.total_score                    AS RelatedUserScoreSum,
    ru_stats.avg_score                      AS RelatedUserScoreAvg,
    tu_tag.TagName,
    tu_tag.post_cnt                         AS TagPostCount,
    tu_tag.total_score                      AS TagTotalScore,
    ROW_NUMBER() OVER (PARTITION BY tu.Id ORDER BY rp.CreationDate DESC) AS RowNum
FROM   top_users tu
JOIN   recent_posts rp
       ON rp.OwnerUserId = tu.Id
      AND rp.rn_user <= 5
LEFT JOIN post_votes pv          ON pv.PostId = rp.Id
LEFT JOIN post_links tl          ON tl.PostId = rp.Id
LEFT JOIN Users ru               ON ru.Id = tl.RelatedPostId
LEFT JOIN (
          SELECT p.OwnerUserId,
                 SUM(p.Score) AS total_score,
                 AVG(p.Score) AS avg_score
          FROM   Posts p
          GROUP BY p.OwnerUserId
        ) ru_stats
       ON ru_stats.OwnerUserId = ru.Id
LEFT JOIN LATERAL (
          SELECT unnest(string_to_array(trim(both '><' FROM rp.Tags), '><')) AS TagName
        ) AS taglist ON true
LEFT JOIN tag_usage tu_tag
       ON tu_tag.TagName = taglist.TagName
WHERE  tu.rn <= 10
ORDER BY tu.Reputation DESC,
         rp.CreationDate DESC
LIMIT 100;
