WITH TagQuestion AS (
    SELECT
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag,
        p.Id              AS QId,
        p.CreationDate    AS QCreated,
        p.Score           AS QScore,
        p.ViewCount       AS QViews,
        p.OwnerUserId     AS AskerId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
AnswerStats AS (
    SELECT
        tq.Tag,
        count(a.Id)                                            AS AnswerCount,
        avg(a.Score)                                          AS AvgAnswerScore,
        avg(extract(epoch FROM (a.CreationDate - tq.QCreated))) AS AvgTimeToAnswerSecs
    FROM TagQuestion tq
    JOIN Posts a
      ON a.ParentId = tq.QId
     AND a.PostTypeId = 2
    GROUP BY tq.Tag
),
DupLinkStats AS (
    SELECT
        tq.Tag,
        count(pl.Id) AS DuplicateLinkCount
    FROM TagQuestion tq
    JOIN PostLinks pl
      ON pl.PostId = tq.QId
     AND pl.LinkTypeId = 3
    GROUP BY tq.Tag
),
AskerStats AS (
    SELECT
        tq.Tag,
        count(DISTINCT tq.AskerId) FILTER (WHERE tq.AskerId > 0) AS AskerCount,
        avg(u.Reputation)                                    AS AvgAskerReputation
    FROM TagQuestion tq
    LEFT JOIN Users u
      ON u.Id = tq.AskerId
    GROUP BY tq.Tag
),
BadgeStats AS (
    SELECT
        b.Name                                                  AS Tag,
        count(*) FILTER (WHERE b.Class = 1)                     AS GoldBadges,
        count(*) FILTER (WHERE b.Class = 2)                     AS SilverBadges,
        count(*) FILTER (WHERE b.Class = 3)                     AS BronzeBadges,
        count(*)                                               AS TotalTagBadges
    FROM Badges b
    WHERE b.TagBased = TRUE
    GROUP BY b.Name
),
Combined AS (
    SELECT
        a.Tag,
        a.AnswerCount,
        round(CAST(a.AvgAnswerScore AS numeric),      2) AS AvgAnswerScore,
        round(CAST(a.AvgTimeToAnswerSecs/3600 AS numeric), 2) AS AvgTimeToAnswerHrs,
        coalesce(ds.DuplicateLinkCount, 0)     AS DuplicateLinkCount,
        coalesce(ask.AskerCount, 0)           AS AskerCount,
        round(CAST(coalesce(ask.AvgAskerReputation, 0) AS numeric), 2) AS AvgAskerRep,
        coalesce(b.GoldBadges,   0)           AS GoldBadges,
        coalesce(b.SilverBadges, 0)           AS SilverBadges,
        coalesce(b.BronzeBadges, 0)           AS BronzeBadges,
        coalesce(b.TotalTagBadges, 0)         AS TotalTagBadges,
        rank() OVER (ORDER BY a.AnswerCount DESC) AS AnswerRank,
        row_number() OVER (ORDER BY a.AnswerCount DESC, coalesce(ds.DuplicateLinkCount, 0) DESC) AS rn
    FROM AnswerStats a
    LEFT JOIN DupLinkStats ds ON ds.Tag = a.Tag
    LEFT JOIN AskerStats   ask ON ask.Tag = a.Tag
    LEFT JOIN BadgeStats   b   ON b.Tag = a.Tag
)
SELECT
    Tag,
    AnswerCount,
    AvgAnswerScore,
    AvgTimeToAnswerHrs,
    DuplicateLinkCount,
    AskerCount,
    AvgAskerRep,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TotalTagBadges,
    AnswerRank
FROM Combined
WHERE rn <= 10
ORDER BY AnswerRank;