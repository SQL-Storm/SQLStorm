-- {"query": "3476.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2195} 

WITH QuestionStats AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        COALESCE(u.Reputation,0)                AS OwnerReputation,
        (SELECT COUNT(*) FROM Votes v
         WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) FROM Votes v
         WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
        (SELECT COUNT(*) FROM Comments c
         WHERE c.PostId = p.Id)                  AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                           ORDER BY p.Score DESC) AS RankByScore
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
TagExplode AS (
    SELECT
        qs.Id               AS QuestionId,
        TRIM(BOTH '<>' FROM regexp_split_to_table(qs.Tags, '><')) AS Tag
    FROM QuestionStats qs
    WHERE qs.Tags IS NOT NULL
),
TagStats AS (
    SELECT
        te.Tag,
        COUNT(DISTINCT te.QuestionId)          AS QuestionCount,
        SUM(qs.Score)                          AS TotalScore,
        AVG(qs.Score)                          AS AvgScore
    FROM TagExplode te
    JOIN QuestionStats qs ON te.QuestionId = qs.Id
    GROUP BY te.Tag
),
UserBadgeAgg AS (
    SELECT
        b.UserId,
        STRING_AGG(DISTINCT b.Name, ', ')      AS Badges,
        COUNT(*) FILTER (WHERE b.Class = 1)    AS GoldCount,
        COUNT(*) FILTER (WHERE b.Class = 2)    AS SilverCount,
        COUNT(*) FILTER (WHERE b.Class = 3)    AS BronzeCount
    FROM Badges b
    GROUP BY b.UserId
),
RecentClosed AS (
    SELECT
        p.Id,
        p.Title,
        ph.CreationDate                        AS ClosedDate,
        cr.Name                                AS CloseReason,
        ROW_NUMBER() OVER (ORDER BY ph.CreationDate DESC) AS RecencyRank
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id
    JOIN CloseReasonTypes cr ON ph.Comment = cr.Id::varchar
    WHERE ph.PostHistoryTypeId = 10
),
DuplicatedLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name                                AS LinkType,
        ROW_NUMBER() OVER (PARTITION BY pl.PostId
                           ORDER BY pl.CreationDate DESC) AS LinkRank
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Id = 3
)

SELECT
    qs.Id                                 AS QuestionId,
    qs.Title,
    qs.CreationDate,
    qs.Score,
    qs.ViewCount,
    qs.OwnerReputation,
    qs.UpVoteCount,
    qs.DownVoteCount,
    qs.CommentCount,
    qs.RankByScore,
    COALESCE(uba.Badges, '')              AS OwnerBadges,
    uba.GoldCount,
    uba.SilverCount,
    uba.BronzeCount,
    rc.ClosedDate,
    rc.CloseReason,
    dl.RelatedPostId                       AS DuplicateOf,
    te.Tag,
    ts.QuestionCount,
    ts.TotalScore,
    ts.AvgScore
FROM QuestionStats qs
LEFT JOIN UserBadgeAgg uba      ON qs.OwnerUserId = uba.UserId
LEFT JOIN RecentClosed rc      ON qs.Id = rc.Id AND rc.RecencyRank = 1
LEFT JOIN DuplicatedLinks dl   ON qs.Id = dl.PostId AND dl.LinkRank = 1
LEFT JOIN TagExplode te        ON qs.Id = te.QuestionId
LEFT JOIN TagStats ts          ON te.Tag = ts.Tag
WHERE
      (qs.Score > 10 AND qs.ViewCount > 5000)
   OR (qs.RankByScore = 1 AND qs.OwnerReputation > 20000)
   OR (dl.RelatedPostId IS NOT NULL AND rc.CloseReason IS NOT NULL)
ORDER BY qs.Score DESC
LIMIT 100

UNION ALL

SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
FROM (SELECT 1) AS dummy
WHERE FALSE;
