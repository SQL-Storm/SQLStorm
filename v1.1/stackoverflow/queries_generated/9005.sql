-- {"query": "9005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 5758} 

WITH MonthlyContributors AS (
    SELECT
        u.Id                              AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id)              AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE v.VoteTypeId WHEN 2 THEN  1
                              WHEN 3 THEN -1
                              ELSE  0 END)     AS VoteBalance,
        ROW_NUMBER() OVER (
            ORDER BY
              SUM(CASE v.VoteTypeId WHEN 2 THEN  1
                                  WHEN 3 THEN -1
                                  ELSE  0 END) DESC
        )                                  AS RankInMonth
    FROM Users u
    LEFT JOIN Posts p
      ON p.OwnerUserId = u.Id
     AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 month'
    LEFT JOIN Votes v
      ON v.PostId = p.Id
     AND v.VoteTypeId IN (2,3)
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 0
),
RecentHotPosts AS (
    SELECT
        p.Id                            AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        UNNEST(
          string_to_array(
            substring(p.Tags FROM 2 FOR length(p.Tags)-2),
            '><'
          )
        )                                AS TagName,
        RANK() OVER (
          PARTITION BY p.PostTypeId
          ORDER BY p.Score DESC
        )                                AS ScoreRank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '7 days'
),
UserBadges AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
LastActivity AS (
    SELECT
        u.Id AS UserId,
        (SELECT MAX(h.CreationDate) FROM PostHistory h WHERE h.UserId = u.Id) AS LastEdit,
        (SELECT MAX(c.CreationDate) FROM Comments     c WHERE c.UserId = u.Id) AS LastComment,
        (SELECT MAX(v.CreationDate) FROM Votes        v WHERE v.UserId = u.Id) AS LastVote
    FROM Users u
),
UserTagCloud AS (
    SELECT
        p.OwnerUserId AS UserId,
        COALESCE(
          replace(
            string_agg(
              DISTINCT UNNEST(
                string_to_array(
                  substring(p.Tags FROM 2 FOR length(p.Tags)-2),
                  '><'
                )
              ),
              ','
            ),
            ',',
            '|'
          ),
          'NoTags'
        ) AS TagCloud
    FROM Posts p
    WHERE p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId
),
LinkRelations AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name   AS LinkType,
        p1.Score  AS OrigScore,
        p2.Score  AS RelatedScore
    FROM PostLinks pl
    LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    LEFT JOIN Posts p1     ON p1.Id = pl.PostId
    RIGHT JOIN Posts p2     ON p2.Id = pl.RelatedPostId
)
SELECT
    mc.DisplayName,
    mc.QuestionCount,
    mc.AnswerCount,
    mc.VoteBalance,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    la.LastEdit,
    la.LastComment,
    la.LastVote,
    utc.TagCloud,
    rhp.Title   AS HotTitle,
    rhp.Score   AS HotScore,
    rhp.TagName AS HotTag,
    lr.LinkType,
    lr.OrigScore,
    lr.RelatedScore,
    COALESCE(mc.VoteBalance,0) * NULLIF(mc.AnswerCount,0) / NULLIF(mc.QuestionCount,1) AS PerformanceMetric,
    CASE
      WHEN mc.RankInMonth = 1  THEN 'TopContributor'
      WHEN mc.RankInMonth <= 10 THEN 'SuperbContributor'
      ELSE 'Contributor'
    END AS ContributorLevel
FROM MonthlyContributors mc
FULL OUTER JOIN UserBadges   ub  ON ub.UserId       = mc.UserId
LEFT JOIN LastActivity      la  ON la.UserId       = mc.UserId
LEFT JOIN UserTagCloud      utc ON utc.UserId      = mc.UserId
LEFT JOIN RecentHotPosts    rhp ON rhp.ScoreRank   <= 3
LEFT JOIN LinkRelations     lr  ON lr.PostId       = rhp.PostId
WHERE (ub.GoldBadges >= 1 AND mc.VoteBalance > 100)
   OR (mc.RankInMonth <= 5 AND rhp.Score IS NOT NULL)
UNION
SELECT
    u.DisplayName,
    0             AS QuestionCount,
    0             AS AnswerCount,
    0             AS VoteBalance,
    0             AS GoldBadges,
    0             AS SilverBadges,
    0             AS BronzeBadges,
    NULL          AS LastEdit,
    NULL          AS LastComment,
    NULL          AS LastVote,
    'NoTags'      AS TagCloud,
    NULL          AS HotTitle,
    NULL          AS HotScore,
    NULL          AS HotTag,
    NULL          AS LinkType,
    NULL          AS OrigScore,
    NULL          AS RelatedScore,
    0.0           AS PerformanceMetric,
    'Newbie'      AS ContributorLevel
FROM Users u
WHERE u.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 day';
