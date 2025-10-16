-- {"query": "9020.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3911} 

WITH
    recent_posts AS (
        SELECT
            p.Id,
            p.Title,
            p.Tags,
            p.OwnerUserId,
            p.Score,
            p.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.CreationDate > now() - INTERVAL '30 days'
    ),
    top_badges AS (
        SELECT
            b.UserId,
            COUNT(*)                              AS GoldBadgeCount,
            ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS Rank
        FROM Badges b
        WHERE b.Class = 1
        GROUP BY b.UserId
    ),
    comment_counts AS (
        SELECT
            c.PostId,
            COUNT(*) AS TotalComments
        FROM Comments c
        GROUP BY c.PostId
    ),
    tags_expanded AS (
        SELECT
            p.Id                           AS QuestionId,
            unnest(
                string_to_array(
                    substring(p.Tags, 2, length(p.Tags) - 2),
                    '><'
                )
            )                                AS Tag
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    ),
    tag_diversity AS (
        SELECT
            QuestionId,
            COUNT(DISTINCT Tag)            AS DistinctTags,
            lower(string_agg(DISTINCT Tag, ',')) AS AggTags
        FROM tags_expanded
        GROUP BY QuestionId
    ),
    diverse_recent AS (
        SELECT
            rp.Id         AS QuestionId,
            rp.OwnerUserId
        FROM recent_posts rp
        JOIN tag_diversity td
          ON td.QuestionId = rp.Id
         AND td.DistinctTags > 3
    ),
    low_participation AS (
        SELECT
            u.Id AS UserId
        FROM Users u
        WHERE u.Reputation BETWEEN 100 AND 1000
          AND NOT EXISTS (
              SELECT 1
                FROM recent_posts rp
               WHERE rp.OwnerUserId = u.Id
          )
    ),
    selected_users AS (
        SELECT OwnerUserId AS UserId FROM diverse_recent
        UNION
        SELECT UserId           FROM low_participation
    )
SELECT
    u.Id                           AS UserId,
    u.DisplayName,
    COALESCE(tb.GoldBadgeCount, 0) AS GoldBadges,
    rp.Title                       AS RecentTitle,
    td.DistinctTags,
    td.AggTags,
    cc.TotalComments,
    COALESCE(
        (
            SELECT COUNT(*)
              FROM Votes v
             WHERE v.PostId = rp.Id
               AND v.VoteTypeId = 2
        ), 0
    )                               AS RecentUpvotes,
    CASE
        WHEN rp.Score > 0
          AND rp.Score >= (
              SELECT AVG(p.Score)
                FROM Posts p
               WHERE p.PostTypeId = 1
          )
            THEN 'AboveAvg'
        WHEN rp.Score = 0 THEN 'ZeroScore'
        ELSE 'BelowAvg'
    END                              AS ScoreCategory
FROM selected_users su
LEFT JOIN Users u
  ON u.Id = su.UserId
LEFT JOIN top_badges tb
  ON tb.UserId = u.Id
 AND tb.Rank <= 5
LEFT JOIN recent_posts rp
  ON rp.OwnerUserId = u.Id
 AND rp.rn = 1
LEFT JOIN comment_counts cc
  ON cc.PostId = rp.Id
LEFT JOIN tag_diversity td
  ON td.QuestionId = rp.Id
WHERE (u.WebsiteUrl IS NOT NULL OR u.AboutMe IS NOT NULL)
  AND COALESCE(u.LastAccessDate, now() - INTERVAL '1 year')
      > now() - INTERVAL '7 days'
ORDER BY GoldBadges DESC, td.DistinctTags DESC NULLS LAST;
