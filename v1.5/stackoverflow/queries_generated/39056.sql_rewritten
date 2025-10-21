-- {"query": "39056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 4138} 
WITH recent_badges AS (
    SELECT 
        UserId, 
        COUNT(*)     AS BadgeCount, 
        MAX(Date)    AS LastBadgeDate
    FROM Badges
    GROUP BY UserId
),
post_metrics AS (
    SELECT
        p.Id                  AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        COUNT(DISTINCT c.Id)                                         AS CommentCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId IN (2,3))    AS VoteCount,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (5,6)) AS EditCount,
        string_to_array(
            substring(p.Tags, 2, length(p.Tags) - 2),
            '><'
        )                                                             AS TagArray
    FROM Posts p
    LEFT JOIN Comments    c  ON c.PostId       = p.Id
    LEFT JOIN Votes       v  ON v.PostId       = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId      = p.Id
    WHERE p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
    GROUP BY
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags
),
exploded_tags AS (
    SELECT
        pm.PostId,
        pm.OwnerUserId,
        pm.Score,
        pm.ViewCount,
        pm.CreationDate,
        pm.CommentCount,
        pm.VoteCount,
        pm.EditCount,
        unnest(pm.TagArray) AS Tag
    FROM post_metrics pm
),
tag_stats AS (
    SELECT
        Tag,
        COUNT(DISTINCT PostId)                           AS PostsPerTag,
        AVG(VoteCount)                                    AS AvgVotes,
        SUM(EditCount)                                    AS TotalEdits,
        MAX(Score)                                        AS MaxScore,
        COUNT(DISTINCT OwnerUserId) FILTER (WHERE ViewCount > 100) AS ActiveUsers
    FROM exploded_tags
    WHERE CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '6 months'
    GROUP BY Tag
    HAVING COUNT(DISTINCT PostId) > 50
),
top_tag_users AS (
    SELECT
        et.Tag,
        et.OwnerUserId,
        COUNT(*) AS PostsByUser,
        RANK() OVER (
            PARTITION BY et.Tag
            ORDER BY MAX(et.Score) DESC
        )       AS RankByScore,
        ROW_NUMBER() OVER (
            PARTITION BY et.Tag
            ORDER BY COUNT(*) DESC
        )       AS TopContributorRank
    FROM exploded_tags et
    WHERE et.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '6 months'
    GROUP BY et.Tag, et.OwnerUserId
)
SELECT
    ts.Tag,
    ts.PostsPerTag,
    ts.AvgVotes,
    ts.TotalEdits,
    ts.ActiveUsers,
    ts.MaxScore,
    u.DisplayName      AS TopScorer,
    ttu.PostsByUser,
    rb.BadgeCount,
    rb.LastBadgeDate
FROM tag_stats ts
JOIN top_tag_users ttu 
  ON ttu.Tag = ts.Tag 
 AND ttu.RankByScore = 1
JOIN Users u 
  ON u.Id = ttu.OwnerUserId
LEFT JOIN recent_badges rb 
  ON rb.UserId = u.Id
ORDER BY
    ts.PostsPerTag DESC,
    ts.AvgVotes    DESC
LIMIT 20;