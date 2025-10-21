-- {"query": "39036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2598} 

WITH ParsedTags AS (
    SELECT
        p.Id        AS PostId,
        p.OwnerUserId AS UserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagMetrics AS (
    SELECT
        pt.Tag,
        COUNT(DISTINCT pt.PostId)        AS QuestionsPosted,
        SUM(p.Score)                     AS TotalQuestionScore,
        AVG(p.ViewCount)                 AS AvgViewCount
    FROM ParsedTags pt
    JOIN Posts p
      ON p.Id = pt.PostId
    GROUP BY pt.Tag
),
UserBadgeMetrics AS (
    SELECT
        b.UserId,
        COUNT(*)                             AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserEngagement AS (
    SELECT
        p.OwnerUserId                       AS UserId,
        COUNT(DISTINCT c.Id)                AS CommentCount,
        COUNT(DISTINCT l.Id) FILTER (WHERE l.LinkTypeId = 3) AS DuplicateLinks,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 12) AS Deletions
    FROM Posts p
    LEFT JOIN Comments     c  ON c.PostId = p.Id
    LEFT JOIN PostLinks    l  ON l.PostId = p.Id
    LEFT JOIN PostHistory  ph ON ph.PostId = p.Id
    GROUP BY p.OwnerUserId
),
TagContributorMetrics AS (
    SELECT
        pt.Tag,
        SUM(ub.GoldBadges)       AS TagGoldBadges,
        SUM(ub.SilverBadges)     AS TagSilverBadges,
        SUM(ub.BronzeBadges)     AS TagBronzeBadges,
        SUM(ue.CommentCount)     AS TagCommentCount,
        SUM(ue.DuplicateLinks)   AS TagDuplicateLinks,
        SUM(ue.Deletions)        AS TagDeletions
    FROM ParsedTags pt
    JOIN UserBadgeMetrics ub ON ub.UserId = pt.UserId
    JOIN UserEngagement ue   ON ue.UserId = pt.UserId
    GROUP BY pt.Tag
)
SELECT
    tm.Tag,
    tm.QuestionsPosted,
    tm.TotalQuestionScore,
    tm.AvgViewCount,
    tcm.TagGoldBadges,
    tcm.TagSilverBadges,
    tcm.TagBronzeBadges,
    tcm.TagCommentCount,
    tcm.TagDuplicateLinks,
    tcm.TagDeletions,
    RANK() OVER (
        ORDER BY tm.QuestionsPosted DESC,
                 tm.TotalQuestionScore DESC
    ) AS TagPopularityRank
FROM TagMetrics tm
JOIN TagContributorMetrics tcm
  ON tcm.Tag = tm.Tag
ORDER BY TagPopularityRank
LIMIT 20;
